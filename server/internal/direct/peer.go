// Package direct implements a P2P WebRTC media peer using pion/webrtc.
// It replaces LiveKit for 1:1 scenarios, eliminating the external SFU dependency.
// Signaling (offer/answer/ICE) flows through the existing WebSocket hub.
package direct

import (
	"context"
	"encoding/binary"
	"fmt"
	"log"
	"math"
	"sync"
	"sync/atomic"
	"time"

	"github.com/cyberverse/server/internal/mediapeer"
	"github.com/pion/interceptor/pkg/cc"
	"github.com/pion/webrtc/v4"
	"github.com/pion/webrtc/v4/pkg/media"
	opus "gopkg.in/hraban/opus.v2"
)

// Compile-time check: DirectPeer implements mediapeer.MediaPeer.
var _ mediapeer.MediaPeer = (*DirectPeer)(nil)

func directVoiceTrace(event string, label string, format string, args ...any) {
	if label == "" {
		return
	}
	sinceUserFinal := "-"
	if len(args) > 0 {
		if ts, ok := args[0].(time.Time); ok {
			if !ts.IsZero() {
				sinceUserFinal = fmt.Sprintf("%d", time.Since(ts).Milliseconds())
			}
			args = args[1:]
		}
	}
	prefix := fmt.Sprintf(
		"voice_trace event=%-30s %s since_user_final_ms=%s",
		event,
		label,
		sinceUserFinal,
	)
	if format == "" {
		log.Print(prefix)
		return
	}
	allArgs := append([]any{prefix}, args...)
	log.Printf("%s "+format, allArgs...)
}

// SignalingFunc sends a signaling message to the browser via the WebSocket hub.
type SignalingFunc func(sessionID string, msg map[string]any)

const (
	defaultDirectVideoBitrateKbps = 1800
	minDirectVideoBitrateKbps     = 500
	maxDirectVideoBitrateKbps     = 1800
	videoBitrateSafetyPercent     = 65

	maxAudioDelayMS          int64 = 800
	audioDelayStepMS         int64 = 160
	audioDelayFeedbackMaxAge       = 4 * time.Second
)

// DirectPeer is a P2P WebRTC media peer using pion/webrtc directly.
type DirectPeer struct {
	sessionID   string
	signalingFn SignalingFunc
	iceServers  []webrtc.ICEServer
	webrtcAPI   *webrtc.API
	estimatorCh <-chan cc.BandwidthEstimator

	pc         *webrtc.PeerConnection
	videoTrack *webrtc.TrackLocalStaticSample
	audioTrack *webrtc.TrackLocalStaticSample

	userAudioCh chan []byte

	// Opus encoder for outgoing PCM → Opus
	opusMu        sync.Mutex
	opusEncoder   *opus.Encoder
	opusEncoderSR int

	// Connection state
	connected chan struct{}
	mu        sync.Mutex
	mediaMu   sync.Mutex

	// AV pipeline (same pattern as Bot)
	encodeCh         chan *mediapeer.RawAVSegment
	publishCh        chan *mediapeer.AVSegment
	avPipelineCtx    context.Context
	avPipelineCancel context.CancelFunc
	avPipelineWg     sync.WaitGroup

	// RTP timestamp gap correction: tracks the wall-clock time of the
	// last WriteSample call so the next segment's first sample can carry
	// a Duration that advances the RTP timestamp over the idle gap.
	lastVideoWriteTime     time.Time
	lastAudioWriteTime     time.Time
	lastPublishEpoch       uint64
	playbackEpoch          atomic.Uint64
	latestSpeechEpoch      atomic.Uint64
	avCalibrationEnabled   atomic.Bool
	avCalibrationMarkerSeq atomic.Int64
	targetBitrateBps       atomic.Int64

	audioDelayMu           sync.Mutex
	audioDelayTargetMS     int64
	audioDelayCurrentMS    int64
	audioDelayPCM          []byte
	audioDelaySampleRate   int
	audioDelayEpoch        uint64
	audioDelayLastFeedback time.Time
}

// NewDirectPeer creates a new P2P WebRTC peer for the given session.
// api should be created via NewWebRTCAPI (with interceptors); estimatorCh receives the GCC bandwidth estimator.
func NewDirectPeer(sessionID string, signalingFn SignalingFunc, iceServers []webrtc.ICEServer,
	api *webrtc.API, estimatorCh <-chan cc.BandwidthEstimator) *DirectPeer {
	return &DirectPeer{
		sessionID:   sessionID,
		signalingFn: signalingFn,
		iceServers:  iceServers,
		webrtcAPI:   api,
		estimatorCh: estimatorCh,
		userAudioCh: make(chan []byte, 64),
		connected:   make(chan struct{}),
	}
}

// Connect creates the PeerConnection and local tracks.
// It does NOT start negotiation — call StartNegotiation() after
// the browser signals readiness via "webrtc_ready".
func (p *DirectPeer) Connect(ctx context.Context) error {
	config := webrtc.Configuration{
		ICEServers: p.iceServers,
	}

	var pc *webrtc.PeerConnection
	var err error
	if p.webrtcAPI != nil {
		pc, err = p.webrtcAPI.NewPeerConnection(config)
	} else {
		pc, err = webrtc.NewPeerConnection(config)
	}
	if err != nil {
		return fmt.Errorf("create PeerConnection: %w", err)
	}

	// Create VP8 video track
	videoTrack, err := webrtc.NewTrackLocalStaticSample(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeVP8},
		"assistant-video",
		"cyberverse",
	)
	if err != nil {
		pc.Close()
		return fmt.Errorf("create video track: %w", err)
	}
	videoSender, err := pc.AddTrack(videoTrack)
	if err != nil {
		pc.Close()
		return fmt.Errorf("add video track: %w", err)
	}

	// Create Opus audio track
	audioTrack, err := webrtc.NewTrackLocalStaticSample(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeOpus},
		"assistant-audio",
		"cyberverse",
	)
	if err != nil {
		pc.Close()
		return fmt.Errorf("create audio track: %w", err)
	}
	audioSender, err := pc.AddTrack(audioTrack)
	if err != nil {
		pc.Close()
		return fmt.Errorf("add audio track: %w", err)
	}

	// RTCP reader goroutines — MUST read continuously so that
	// NACK/TWCC/GCC interceptors receive browser feedback and work correctly.
	go readRTCP(videoSender)
	go readRTCP(audioSender)

	// Add a recvonly audio transceiver so the SDP offer explicitly requests
	// the browser's microphone audio. Without this, pion's sendrecv transceiver
	// from AddTrack may not produce an OnTrack callback for the browser's mic.
	if _, err := pc.AddTransceiverFromKind(
		webrtc.RTPCodecTypeAudio,
		webrtc.RTPTransceiverInit{Direction: webrtc.RTPTransceiverDirectionRecvonly},
	); err != nil {
		pc.Close()
		return fmt.Errorf("add mic receive transceiver: %w", err)
	}

	// Handle incoming user audio track (mic)
	pc.OnTrack(func(track *webrtc.TrackRemote, receiver *webrtc.RTPReceiver) {
		if !p.isActivePeerConnection(pc) {
			return
		}
		if track.Kind() != webrtc.RTPCodecTypeAudio {
			return
		}
		log.Printf("[DirectPeer] session=%s subscribed to user audio track codec=%s", p.sessionID, track.Codec().MimeType)
		go p.readUserAudio(track)
	})

	// Forward ICE candidates to browser via signaling
	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if !p.isActivePeerConnection(pc) {
			return
		}
		if c == nil {
			log.Printf("[DirectPeer] session=%s ICE gathering complete", p.sessionID)
			return
		}
		init := c.ToJSON()
		log.Printf("[DirectPeer] session=%s local ICE candidate: %s | sdp: %s", p.sessionID, c.String(), init.Candidate)
		msg := map[string]any{
			"type":      "ice_candidate",
			"candidate": init.Candidate,
		}
		if init.SDPMid != nil {
			msg["sdp_mid"] = *init.SDPMid
		}
		if init.SDPMLineIndex != nil {
			msg["sdp_mline_index"] = *init.SDPMLineIndex
		}
		p.signalingFn(p.sessionID, msg)
	})

	// Track ICE connection state (more granular than PeerConnection state)
	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		if !p.isActivePeerConnection(pc) {
			return
		}
		log.Printf("[DirectPeer] session=%s ICE connection state: %s", p.sessionID, state.String())
	})

	// Track connection state
	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		if !p.isActivePeerConnection(pc) {
			return
		}
		log.Printf("[DirectPeer] session=%s connection state: %s", p.sessionID, state.String())
		if state == webrtc.PeerConnectionStateConnected {
			select {
			case <-p.connected:
			default:
				close(p.connected)
			}
		}
	})

	p.mu.Lock()
	p.pc = pc
	p.videoTrack = videoTrack
	p.audioTrack = audioTrack
	p.mu.Unlock()

	// Monitor GCC bandwidth estimation
	if p.estimatorCh != nil {
		go func() {
			select {
			case estimator, ok := <-p.estimatorCh:
				if !ok {
					return
				}
				estimator.OnTargetBitrateChange(func(bitrate int) {
					p.targetBitrateBps.Store(int64(bitrate))
					log.Printf("[DirectPeer] session=%s GCC target bitrate: %d kbps", p.sessionID, bitrate/1000)
				})
			case <-time.After(10 * time.Second):
				log.Printf("[DirectPeer] session=%s GCC estimator unavailable; using default VP8 bitrate", p.sessionID)
			}
		}()
	}

	return nil
}

func (p *DirectPeer) isActivePeerConnection(pc *webrtc.PeerConnection) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.pc == pc
}

func (p *DirectPeer) resetAudioDelayState() {
	p.audioDelayMu.Lock()
	defer p.audioDelayMu.Unlock()
	p.audioDelayTargetMS = 0
	p.audioDelayCurrentMS = 0
	p.audioDelayPCM = nil
	p.audioDelaySampleRate = 0
	p.audioDelayEpoch = 0
	p.audioDelayLastFeedback = time.Time{}
}

func (p *DirectPeer) prepareMediaPathReset() *webrtc.PeerConnection {
	p.mu.Lock()
	oldPC := p.pc
	p.pc = nil
	p.videoTrack = nil
	p.audioTrack = nil
	p.connected = make(chan struct{})
	p.lastVideoWriteTime = time.Time{}
	p.lastAudioWriteTime = time.Time{}
	p.lastPublishEpoch = 0
	p.mu.Unlock()

	p.targetBitrateBps.Store(0)
	p.opusMu.Lock()
	p.opusEncoder = nil
	p.opusEncoderSR = 0
	p.opusMu.Unlock()
	p.resetAudioDelayState()
	return oldPC
}

// ResetMediaPath rebuilds the Direct WebRTC PeerConnection without closing
// the user audio subscription channel owned by the session.
func (p *DirectPeer) ResetMediaPath(ctx context.Context) error {
	p.mediaMu.Lock()
	defer p.mediaMu.Unlock()

	log.Printf("[DirectPeer] session=%s Direct media path reset requested", p.sessionID)
	oldPC := p.prepareMediaPathReset()
	if oldPC != nil {
		if err := oldPC.Close(); err != nil {
			log.Printf("[DirectPeer] session=%s close old PeerConnection during media reset failed: %v", p.sessionID, err)
		}
	}

	if err := p.Connect(ctx); err != nil {
		return err
	}
	if err := p.StartNegotiation(); err != nil {
		return err
	}
	log.Printf("[DirectPeer] session=%s Direct media path reset negotiation started", p.sessionID)
	return nil
}

// SetAVCalibrationEnabled toggles explicit in-band AV marker injection for diagnostics.
func (p *DirectPeer) SetAVCalibrationEnabled(enabled bool) {
	p.avCalibrationEnabled.Store(enabled)
}

// HandleAVSyncFeedback updates the server-side audio delay target from browser diagnostics.
func (p *DirectPeer) HandleAVSyncFeedback(turnSeq uint64, excessVideoLagMS, jitterBufferDeltaMS float64, likely string) {
	if likely != "video_late_audio_leads" {
		return
	}
	currentEpoch := p.playbackEpoch.Load()
	if turnSeq > 0 && currentEpoch > 0 && turnSeq != currentEpoch {
		return
	}
	if math.IsNaN(excessVideoLagMS) || math.IsInf(excessVideoLagMS, 0) ||
		math.IsNaN(jitterBufferDeltaMS) || math.IsInf(jitterBufferDeltaMS, 0) {
		return
	}
	if jitterBufferDeltaMS <= 0 {
		return
	}

	wanted := int64(math.Round(math.Max(math.Max(excessVideoLagMS, 0), jitterBufferDeltaMS)))
	if wanted < 0 {
		wanted = 0
	}
	if wanted > maxAudioDelayMS {
		wanted = maxAudioDelayMS
	}

	p.audioDelayMu.Lock()
	p.audioDelayTargetMS = wanted
	p.audioDelayLastFeedback = time.Now()
	current := p.audioDelayCurrentMS
	p.audioDelayMu.Unlock()

	log.Printf(
		"[DirectPeer] session=%s AV sync feedback turn=%d excess_video_lag=%.1fms jb_delta=%.1fms audio_delay_target=%dms current=%dms",
		p.sessionID,
		turnSeq,
		excessVideoLagMS,
		jitterBufferDeltaMS,
		wanted,
		current,
	)
}

// readRTCP continuously reads RTCP packets from an RTPSender.
// This is required for NACK/TWCC/GCC interceptors to receive browser feedback.
func readRTCP(sender *webrtc.RTPSender) {
	rtcpBuf := make([]byte, 1500)
	for {
		if _, _, err := sender.Read(rtcpBuf); err != nil {
			return
		}
	}
}

// StartNegotiation creates an SDP offer and sends it to the browser.
// Call this after the browser sends "webrtc_ready" via WebSocket.
func (p *DirectPeer) StartNegotiation() error {
	p.mu.Lock()
	pc := p.pc
	p.mu.Unlock()
	if pc == nil {
		return fmt.Errorf("PeerConnection not created")
	}

	offer, err := pc.CreateOffer(nil)
	if err != nil {
		return fmt.Errorf("create offer: %w", err)
	}
	if err := pc.SetLocalDescription(offer); err != nil {
		return fmt.Errorf("set local description: %w", err)
	}

	// Send the SDP immediately. Local ICE candidates are trickled through the
	// OnICECandidate callback; waiting for full gathering can add seconds before
	// the browser can even answer.
	localOffer := pc.LocalDescription()
	if localOffer == nil {
		return fmt.Errorf("local description unavailable")
	}
	p.signalingFn(p.sessionID, map[string]any{
		"type": "webrtc_offer",
		"sdp":  localOffer.SDP,
	})
	log.Printf("[DirectPeer] session=%s SDP offer sent (trickle ICE enabled)", p.sessionID)
	return nil
}

// HandleSignaling processes incoming signaling messages from the browser.
func (p *DirectPeer) HandleSignaling(msgType, sdp, candidate string, sdpMid *string, sdpMLineIndex *uint16) {
	p.mu.Lock()
	pc := p.pc
	p.mu.Unlock()
	if pc == nil {
		return
	}

	switch msgType {
	case "webrtc_answer":
		if err := pc.SetRemoteDescription(webrtc.SessionDescription{
			Type: webrtc.SDPTypeAnswer,
			SDP:  sdp,
		}); err != nil {
			log.Printf("[DirectPeer] session=%s set remote description failed: %v", p.sessionID, err)
		} else {
			log.Printf("[DirectPeer] session=%s SDP answer set", p.sessionID)
		}

	case "ice_candidate":
		if candidate == "" {
			return
		}
		log.Printf("[DirectPeer] session=%s remote ICE candidate: %s", p.sessionID, candidate)
		init := webrtc.ICECandidateInit{
			Candidate: candidate,
		}
		if sdpMid != nil {
			init.SDPMid = sdpMid
		}
		if sdpMLineIndex != nil {
			init.SDPMLineIndex = sdpMLineIndex
		}
		if err := pc.AddICECandidate(init); err != nil {
			log.Printf("[DirectPeer] session=%s add ICE candidate failed: %v", p.sessionID, err)
		}
	}
}

// readUserAudio reads Opus RTP packets from the user's mic track,
// decodes to 16kHz mono PCM, and writes to userAudioCh.
func (p *DirectPeer) readUserAudio(track *webrtc.TrackRemote) {
	decoder, err := opus.NewDecoder(16000, 1)
	if err != nil {
		log.Printf("[DirectPeer] session=%s opus decoder creation failed: %v", p.sessionID, err)
		return
	}

	pcmBuf := make([]int16, 16000) // up to 1 second buffer

	for {
		pkt, _, err := track.ReadRTP()
		if err != nil {
			log.Printf("[DirectPeer] session=%s user audio track closed: %v", p.sessionID, err)
			return
		}

		n, err := decoder.Decode(pkt.Payload, pcmBuf)
		if err != nil {
			continue
		}
		if n == 0 {
			continue
		}

		// Convert int16 → little-endian bytes (matching VoiceLLM expected format)
		out := make([]byte, n*2)
		for i := 0; i < n; i++ {
			binary.LittleEndian.PutUint16(out[i*2:], uint16(pcmBuf[i]))
		}

		select {
		case p.userAudioCh <- out:
		default:
			// Drop if consumer is too slow (same backpressure as Bot)
		}
	}
}

// SubscribeUserAudio returns the channel receiving decoded user mic PCM.
func (p *DirectPeer) SubscribeUserAudio() <-chan []byte {
	return p.userAudioCh
}

// --- AV Pipeline (same pattern as Bot) ---

// StartAVPipeline launches encode and publish goroutines.
func (p *DirectPeer) StartAVPipeline(ctx context.Context) {
	p.avPipelineCtx, p.avPipelineCancel = context.WithCancel(ctx)
	p.encodeCh = make(chan *mediapeer.RawAVSegment, 1)
	p.publishCh = make(chan *mediapeer.AVSegment, 1)

	p.avPipelineWg.Add(2)
	go p.runEncoder()
	go p.runPublisher()
}

// SendAVSegment enqueues a raw segment for encoding and publishing.
func (p *DirectPeer) SendAVSegment(seg *mediapeer.RawAVSegment) error {
	seg.QueuedAt = time.Now()
	if !p.prepareRawAVSegment(seg) {
		return nil
	}
	directVoiceTrace(
		"direct_segment_enqueued",
		seg.TraceLabel,
		"",
		seg.UserFinalAt,
	)
	select {
	case p.encodeCh <- seg:
		return nil
	case <-p.avPipelineCtx.Done():
		return fmt.Errorf("av pipeline cancelled")
	}
}

func (p *DirectPeer) prepareRawAVSegment(seg *mediapeer.RawAVSegment) bool {
	if seg == nil || p.isPlaybackStale(seg.Epoch) {
		return false
	}
	if seg.Supersedable {
		seg.SpeechEpochAtQueue = p.latestSpeechEpoch.Load()
	}
	if seg.Epoch > 0 {
		p.advanceLatestSpeechEpoch(seg.Epoch)
	}
	return !p.isRawAVSegmentStale(seg)
}

func (p *DirectPeer) advanceLatestSpeechEpoch(epoch uint64) {
	if epoch == 0 {
		return
	}
	for {
		current := p.latestSpeechEpoch.Load()
		if epoch <= current {
			return
		}
		if p.latestSpeechEpoch.CompareAndSwap(current, epoch) {
			return
		}
	}
}

func (p *DirectPeer) AdvancePlaybackEpoch(epoch uint64) {
	if epoch == 0 {
		return
	}
	for {
		current := p.playbackEpoch.Load()
		if epoch <= current {
			return
		}
		if p.playbackEpoch.CompareAndSwap(current, epoch) {
			return
		}
	}
}

// WaitAVDrain blocks until all queued segments are published.
func (p *DirectPeer) WaitAVDrain(timeout time.Duration) {
	if p.encodeCh == nil {
		return
	}
	fence := make(chan struct{})
	select {
	case p.encodeCh <- &mediapeer.RawAVSegment{Fence: fence}:
	case <-p.avPipelineCtx.Done():
		return
	case <-time.After(timeout):
		return
	}
	select {
	case <-fence:
	case <-p.avPipelineCtx.Done():
	case <-time.After(timeout):
	}
}

func (p *DirectPeer) currentVideoBitrateKbps() int {
	targetBps := p.targetBitrateBps.Load()
	if targetBps <= 0 {
		return defaultDirectVideoBitrateKbps
	}
	kbps := int((targetBps * videoBitrateSafetyPercent) / 100 / 1000)
	if kbps < minDirectVideoBitrateKbps {
		return minDirectVideoBitrateKbps
	}
	if kbps > maxDirectVideoBitrateKbps {
		return maxDirectVideoBitrateKbps
	}
	return kbps
}

// StopAVPipeline shuts down the AV pipeline goroutines.
//
// encodeCh is intentionally NOT closed here: closing it concurrently with a
// SendAVSegment / WaitAVDrain send would panic ("send on closed channel").
// Both encoders and senders exit via avPipelineCtx cancellation, and the
// channel is garbage-collected with the peer.
func (p *DirectPeer) StopAVPipeline() {
	if p.avPipelineCancel != nil {
		p.avPipelineCancel()
	}
	p.avPipelineWg.Wait()
}

func (p *DirectPeer) runEncoder() {
	defer p.avPipelineWg.Done()
	defer close(p.publishCh)

	for {
		var raw *mediapeer.RawAVSegment
		var ok bool
		select {
		case raw, ok = <-p.encodeCh:
			if !ok {
				// encodeCh is not closed by StopAVPipeline by design; this
				// guard keeps the loop safe if a future caller closes it.
				return
			}
		case <-p.avPipelineCtx.Done():
			return
		}

		if p.avPipelineCtx.Err() != nil {
			return
		}

		// Fence marker: pass through
		if raw.Fence != nil && len(raw.RGB) == 0 {
			select {
			case p.publishCh <- &mediapeer.AVSegment{Fence: raw.Fence}:
			case <-p.avPipelineCtx.Done():
				return
			}
			continue
		}
		if p.isRawAVSegmentStale(raw) {
			continue
		}

		encodeStart := time.Now()
		videoBitrateKbps := p.currentVideoBitrateKbps()
		directVoiceTrace(
			"direct_vp8_encode_started",
			raw.TraceLabel,
			"queue_ms=%d bitrate_kbps=%d",
			raw.UserFinalAt,
			time.Since(raw.QueuedAt).Milliseconds(),
			videoBitrateKbps,
		)
		if p.avCalibrationEnabled.Load() {
			p.injectAVCalibrationMarker(raw)
		}

		vp8Samples, err := mediapeer.EncodeRGBChunkToVP8SamplesWithBitrate(
			raw.RGB,
			raw.Width,
			raw.Height,
			raw.NumFrames,
			raw.FPS,
			videoBitrateKbps,
		)
		if err != nil {
			log.Printf("[DirectPeer] encode failed: %v", err)
			continue
		}
		if len(vp8Samples) == 0 {
			continue
		}
		if p.isRawAVSegmentStale(raw) {
			continue
		}
		directVoiceTrace(
			"direct_vp8_encode_done",
			raw.TraceLabel,
			"encode_ms=%d",
			raw.UserFinalAt,
			time.Since(encodeStart).Milliseconds(),
		)

		seg := &mediapeer.AVSegment{
			TraceLabel:         raw.TraceLabel,
			Epoch:              raw.Epoch,
			SegmentSeq:         raw.SegmentSeq,
			MediaStartMS:       raw.MediaStartMS,
			DurationMS:         raw.DurationMS,
			MarkerID:           raw.MarkerID,
			MarkerMediaMS:      raw.MarkerMediaMS,
			MarkerDurationMS:   raw.MarkerDurationMS,
			MarkerFrequencyHz:  raw.MarkerFrequencyHz,
			VP8Samples:         vp8Samples,
			PCM:                raw.PCM,
			UserFinalAt:        raw.UserFinalAt,
			SampleRate:         raw.SampleRate,
			Width:              raw.Width,
			Height:             raw.Height,
			FPS:                raw.FPS,
			NumFrames:          raw.NumFrames,
			QueuedAt:           raw.QueuedAt,
			Supersedable:       raw.Supersedable,
			SpeechEpochAtQueue: raw.SpeechEpochAtQueue,
		}
		select {
		case p.publishCh <- seg:
		case <-p.avPipelineCtx.Done():
			return
		}
	}
}

func (p *DirectPeer) injectAVCalibrationMarker(raw *mediapeer.RawAVSegment) {
	if raw == nil || raw.NumFrames <= 0 || raw.Width <= 0 || raw.Height <= 0 || raw.FPS <= 0 {
		return
	}
	if len(raw.RGB) < raw.Width*raw.Height*3*raw.NumFrames || len(raw.PCM) == 0 || raw.SampleRate <= 0 {
		return
	}

	frameIndex := 0
	if raw.NumFrames > 4 {
		frameIndex = 2
	}
	markerFrames := 1
	if raw.NumFrames-frameIndex > 1 {
		markerFrames = 2
	}
	markerOffsetMS := int64(math.Round(float64(frameIndex) * 1000 / float64(raw.FPS)))
	markerDurationMS := int64(math.Round(float64(markerFrames) * 1000 / float64(raw.FPS)))
	if markerDurationMS < 60 {
		markerDurationMS = 60
	}

	raw.MarkerID = p.avCalibrationMarkerSeq.Add(1)
	raw.MarkerMediaMS = raw.MediaStartMS + markerOffsetMS
	raw.MarkerDurationMS = markerDurationMS
	raw.MarkerFrequencyHz = 1800

	paintAVCalibrationFlash(raw, frameIndex, markerFrames)
	mixAVCalibrationChirp(raw.PCM, raw.SampleRate, markerOffsetMS, markerDurationMS, raw.MarkerFrequencyHz)
}

func paintAVCalibrationFlash(raw *mediapeer.RawAVSegment, frameIndex, markerFrames int) {
	blockW := minInt(raw.Width, maxInt(48, raw.Width/5))
	blockH := minInt(raw.Height, maxInt(48, raw.Height/5))
	frameSize := raw.Width * raw.Height * 3
	for f := frameIndex; f < frameIndex+markerFrames && f < raw.NumFrames; f++ {
		base := f * frameSize
		for y := 0; y < blockH; y++ {
			row := base + y*raw.Width*3
			for x := 0; x < blockW; x++ {
				i := row + x*3
				raw.RGB[i] = 255
				raw.RGB[i+1] = 0
				raw.RGB[i+2] = 255
			}
		}
	}
}

func mixAVCalibrationChirp(pcm []byte, sampleRate int, offsetMS, durationMS int64, frequencyHz int) {
	start := int((offsetMS * int64(sampleRate)) / 1000)
	count := int((durationMS * int64(sampleRate)) / 1000)
	if count <= 0 || start < 0 || start >= len(pcm)/2 {
		return
	}
	if start+count > len(pcm)/2 {
		count = len(pcm)/2 - start
	}
	const amplitude = 22000
	fadeSamples := maxInt(1, sampleRate/200)
	for i := 0; i < count; i++ {
		t := float64(i) / float64(sampleRate)
		fade := 1.0
		if i < fadeSamples {
			fade = float64(i) / float64(fadeSamples)
		} else if remain := count - i; remain < fadeSamples {
			fade = float64(remain) / float64(fadeSamples)
		}
		add := int(math.Round(math.Sin(2*math.Pi*float64(frequencyHz)*t) * amplitude * fade))
		idx := (start + i) * 2
		current := int(int16(binary.LittleEndian.Uint16(pcm[idx:])))
		next := current + add
		if next > 32767 {
			next = 32767
		} else if next < -32768 {
			next = -32768
		}
		binary.LittleEndian.PutUint16(pcm[idx:], uint16(int16(next)))
	}
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func audioDelayPCMBytes(delayMS int64, sampleRate int) int {
	if delayMS <= 0 || sampleRate <= 0 {
		return 0
	}
	samples := int((delayMS * int64(sampleRate)) / 1000)
	return samples * 2
}

func (p *DirectPeer) applyAudioDelay(epoch uint64, pcm []byte, sampleRate int) []byte {
	if len(pcm) == 0 || sampleRate <= 0 {
		return pcm
	}

	p.audioDelayMu.Lock()
	defer p.audioDelayMu.Unlock()

	if p.audioDelayEpoch != epoch || p.audioDelaySampleRate != sampleRate {
		p.audioDelayEpoch = epoch
		p.audioDelaySampleRate = sampleRate
		p.audioDelayTargetMS = 0
		p.audioDelayCurrentMS = 0
		p.audioDelayPCM = nil
		p.audioDelayLastFeedback = time.Time{}
	}

	if p.audioDelayTargetMS > 0 &&
		!p.audioDelayLastFeedback.IsZero() &&
		time.Since(p.audioDelayLastFeedback) > audioDelayFeedbackMaxAge {
		p.audioDelayTargetMS -= audioDelayStepMS
		if p.audioDelayTargetMS < 0 {
			p.audioDelayTargetMS = 0
		}
		p.audioDelayLastFeedback = time.Now()
	}

	previousDelayMS := p.audioDelayCurrentMS
	if p.audioDelayTargetMS > p.audioDelayCurrentMS+audioDelayStepMS {
		p.audioDelayCurrentMS += audioDelayStepMS
	} else if p.audioDelayTargetMS < p.audioDelayCurrentMS-audioDelayStepMS {
		p.audioDelayCurrentMS -= audioDelayStepMS
	} else {
		p.audioDelayCurrentMS = p.audioDelayTargetMS
	}
	if p.audioDelayCurrentMS > 0 || p.audioDelayTargetMS > 0 || previousDelayMS > 0 {
		log.Printf(
			"[DirectPeer] session=%s audio delay apply epoch=%d current=%dms target=%dms",
			p.sessionID,
			epoch,
			p.audioDelayCurrentMS,
			p.audioDelayTargetMS,
		)
	}

	desiredBytes := audioDelayPCMBytes(p.audioDelayCurrentMS, sampleRate)
	if desiredBytes <= 0 {
		p.audioDelayPCM = nil
		return pcm
	}

	if len(p.audioDelayPCM) < desiredBytes {
		p.audioDelayPCM = append(p.audioDelayPCM, make([]byte, desiredBytes-len(p.audioDelayPCM))...)
	} else if len(p.audioDelayPCM) > desiredBytes {
		p.audioDelayPCM = p.audioDelayPCM[len(p.audioDelayPCM)-desiredBytes:]
	}

	combined := make([]byte, 0, len(p.audioDelayPCM)+len(pcm))
	combined = append(combined, p.audioDelayPCM...)
	combined = append(combined, pcm...)

	out := make([]byte, len(pcm))
	copy(out, combined)
	if len(combined) > len(pcm) {
		p.audioDelayPCM = append([]byte(nil), combined[len(pcm):]...)
	} else {
		p.audioDelayPCM = nil
	}
	return out
}

func (p *DirectPeer) runPublisher() {
	defer p.avPipelineWg.Done()

	for seg := range p.publishCh {
		if p.avPipelineCtx.Err() != nil {
			return
		}
		// Fence marker
		if seg.Fence != nil && len(seg.VP8Samples) == 0 {
			close(seg.Fence)
			continue
		}
		if p.isAVSegmentStale(seg) {
			continue
		}
		p.publishAVSegment(seg)
	}
}

func (p *DirectPeer) waitConnected(timeout time.Duration) bool {
	select {
	case <-p.connected:
		return true
	case <-p.avPipelineCtx.Done():
		return false
	case <-time.After(timeout):
		return false
	}
}

func (p *DirectPeer) publishAVSegment(seg *mediapeer.AVSegment) {
	p.mediaMu.Lock()
	defer p.mediaMu.Unlock()

	// Wait for connection to be established
	if !p.waitConnected(10 * time.Second) {
		if p.avPipelineCtx.Err() == nil {
			log.Printf("[DirectPeer] session=%s publish timeout waiting for connection", p.sessionID)
		}
		return
	}
	p.mu.Lock()
	videoTrack := p.videoTrack
	audioTrack := p.audioTrack
	p.mu.Unlock()
	if videoTrack == nil {
		log.Printf("[DirectPeer] session=%s publish skipped: video track is not ready", p.sessionID)
		return
	}
	publishStart := time.Now()
	if p.isAVSegmentStale(seg) {
		return
	}
	directVoiceTrace(
		"direct_publish_started",
		seg.TraceLabel,
		"queue_ms=%d",
		seg.UserFinalAt,
		time.Since(seg.QueuedAt).Milliseconds(),
	)

	fps := seg.FPS
	if fps <= 0 {
		fps = 25
	}
	frameDur := time.Second / time.Duration(fps)
	p.resetRTPGapClockForEpoch(seg.Epoch)

	// Encode entire PCM buffer into Opus frames up-front to avoid
	// the sample-loss caused by slicing PCM per video frame.
	var opusFrames []media.Sample
	if len(seg.PCM) > 0 && seg.SampleRate > 0 {
		if audioTrack == nil {
			log.Printf("[DirectPeer] session=%s publish skipped: audio track is not ready", p.sessionID)
			return
		}
		var err error
		pcm := p.applyAudioDelay(seg.Epoch, seg.PCM, seg.SampleRate)
		opusFrames, err = mediapeer.EncodePCMToOpusSamples(pcm, seg.SampleRate)
		if err != nil {
			log.Printf("[DirectPeer] audio encode error: %v", err)
			return
		}
	}

	p.sendAVSegmentDiagnostic(seg, publishStart)

	// --- RTP timestamp gap correction ---
	// Between segments WriteSample pauses; without advancing the RTP clock the
	// browser jitter buffer treats the next frame as very late. Pion advances
	// RTP timestamps after WriteSample, so the idle gap must be skipped with an
	// empty sample before the first real audio/video sample in this segment.
	now := time.Now()
	rtpGap := time.Duration(0)
	if !p.lastVideoWriteTime.IsZero() {
		wallGap := now.Sub(p.lastVideoWriteTime)
		rtpGap = rtpGapToSkip(wallGap, frameDur)
		if rtpGap > 0 {
			if rtpGap != wallGap {
				log.Printf("[DirectPeer] session=%s RTP timestamp gap correction: wall=%v skipped=%v", p.sessionID, wallGap, rtpGap)
			} else {
				log.Printf("[DirectPeer] session=%s RTP timestamp gap correction skipped=%v", p.sessionID, rtpGap)
			}
		}
	}
	if rtpGap > 0 {
		if len(opusFrames) > 0 {
			if err := audioTrack.WriteSample(media.Sample{Duration: rtpGap}); err != nil {
				log.Printf("[DirectPeer] audio RTP gap skip error: %v", err)
				return
			}
			p.lastAudioWriteTime = now
		}
		if len(seg.VP8Samples) > 0 {
			if err := videoTrack.WriteSample(media.Sample{Duration: rtpGap}); err != nil {
				log.Printf("[DirectPeer] video RTP gap skip error: %v", err)
				return
			}
			p.lastVideoWriteTime = now
		}
	}

	nVideo := len(seg.VP8Samples)
	segmentStartWall := time.Now()
	segmentDuration := avSegmentWallDuration(seg, frameDur, opusFrames)
	maxSlip := time.Duration(0)
	firstVideoWritten := false
	videoIndex := 0
	audioIndex := 0
	audioOffset := time.Duration(0)

	for videoIndex < nVideo || audioIndex < len(opusFrames) {
		if p.isAVSegmentStale(seg) {
			return
		}

		videoDeadline := segmentStartWall.Add(time.Duration(videoIndex) * frameDur)
		audioDeadline := segmentStartWall.Add(audioOffset)
		if videoIndex < nVideo && (audioIndex >= len(opusFrames) || !videoDeadline.After(audioDeadline)) {
			slip, err := p.sleepUntil(videoDeadline)
			if err != nil {
				log.Printf("[DirectPeer] video pacing error: %v", err)
				return
			}
			if slip > maxSlip {
				maxSlip = slip
			}
			if err := videoTrack.WriteSample(seg.VP8Samples[videoIndex]); err != nil {
				log.Printf("[DirectPeer] video write error: %v", err)
				return
			}
			p.lastVideoWriteTime = videoDeadline.Add(frameDur)
			if !firstVideoWritten {
				firstVideoWritten = true
				directVoiceTrace(
					"direct_first_video_sample_written",
					seg.TraceLabel,
					"publish_ms=%d",
					seg.UserFinalAt,
					time.Since(publishStart).Milliseconds(),
				)
			}
			videoIndex++
			continue
		}

		if audioIndex < len(opusFrames) {
			slip, err := p.sleepUntil(audioDeadline)
			if err != nil {
				log.Printf("[DirectPeer] audio pacing error: %v", err)
				return
			}
			if slip > maxSlip {
				maxSlip = slip
			}
			sample := opusFrames[audioIndex]
			if err := audioTrack.WriteSample(sample); err != nil {
				log.Printf("[DirectPeer] audio write error: %v", err)
				return
			}
			p.lastAudioWriteTime = audioDeadline.Add(mediaSampleDuration(sample, 20*time.Millisecond))
			audioOffset += mediaSampleDuration(sample, 20*time.Millisecond)
			audioIndex++
		}
	}
	if segmentDuration > 0 {
		slip, err := p.sleepUntil(segmentStartWall.Add(segmentDuration))
		if err != nil {
			log.Printf("[DirectPeer] segment pacing error: %v", err)
			return
		}
		if slip > maxSlip {
			maxSlip = slip
		}
	}
	if maxSlip >= 20*time.Millisecond {
		directVoiceTrace(
			"direct_publish_pacing_slip",
			seg.TraceLabel,
			"seg=%d max_slip_ms=%d publish_ms=%d",
			seg.UserFinalAt,
			seg.SegmentSeq,
			maxSlip.Milliseconds(),
			time.Since(publishStart).Milliseconds(),
		)
	}

	// Record the last write time for gap correction on the next segment.
	if segmentDuration > 0 {
		p.lastVideoWriteTime = segmentStartWall.Add(segmentDuration)
	} else {
		p.lastVideoWriteTime = time.Now()
	}
	p.lastAudioWriteTime = p.lastVideoWriteTime
}

func (p *DirectPeer) resetRTPGapClockForEpoch(epoch uint64) {
	if epoch == 0 {
		return
	}
	if p.lastPublishEpoch != 0 && p.lastPublishEpoch != epoch {
		p.lastVideoWriteTime = time.Time{}
		p.lastAudioWriteTime = time.Time{}
	}
	p.lastPublishEpoch = epoch
}

func mediaSampleDuration(sample media.Sample, fallback time.Duration) time.Duration {
	if sample.Duration > 0 {
		return sample.Duration
	}
	return fallback
}

func avSegmentWallDuration(seg *mediapeer.AVSegment, frameDur time.Duration, opusFrames []media.Sample) time.Duration {
	if seg.DurationMS > 0 {
		return time.Duration(seg.DurationMS) * time.Millisecond
	}
	videoDuration := time.Duration(len(seg.VP8Samples)) * frameDur
	audioDuration := time.Duration(0)
	for _, sample := range opusFrames {
		audioDuration += mediaSampleDuration(sample, 20*time.Millisecond)
	}
	if audioDuration > videoDuration {
		return audioDuration
	}
	return videoDuration
}

func (p *DirectPeer) sendAVSegmentDiagnostic(seg *mediapeer.AVSegment, publishStart time.Time) {
	if p.signalingFn == nil || seg == nil || seg.SegmentSeq <= 0 {
		return
	}
	fps := seg.FPS
	if fps <= 0 {
		fps = 25
	}
	durationMS := seg.DurationMS
	if durationMS <= 0 && seg.NumFrames > 0 && fps > 0 {
		durationMS = int64(math.Round(float64(seg.NumFrames) * 1000 / float64(fps)))
	}
	publishQueueMS := int64(0)
	queuedWallMS := int64(0)
	if !seg.QueuedAt.IsZero() {
		queuedWallMS = seg.QueuedAt.UnixMilli()
		publishQueueMS = publishStart.Sub(seg.QueuedAt).Milliseconds()
	}
	p.signalingFn(p.sessionID, map[string]any{
		"type":                 "av_segment_diagnostic",
		"turn_seq":             seg.Epoch,
		"segment_seq":          seg.SegmentSeq,
		"media_start_ms":       seg.MediaStartMS,
		"duration_ms":          durationMS,
		"video_frames":         seg.NumFrames,
		"fps":                  fps,
		"audio_samples":        len(seg.PCM) / 2,
		"sample_rate":          seg.SampleRate,
		"queued_wall_ms":       queuedWallMS,
		"publish_queue_ms":     publishQueueMS,
		"publish_wall_ms":      publishStart.UnixMilli(),
		"marker_id":            seg.MarkerID,
		"marker_media_time_ms": seg.MarkerMediaMS,
		"marker_duration_ms":   seg.MarkerDurationMS,
		"marker_frequency_hz":  seg.MarkerFrequencyHz,
	})
}

func (p *DirectPeer) isPlaybackStale(epoch uint64) bool {
	if epoch == 0 {
		return false
	}
	current := p.playbackEpoch.Load()
	return current > 0 && epoch < current
}

func (p *DirectPeer) isRawAVSegmentStale(seg *mediapeer.RawAVSegment) bool {
	if seg == nil {
		return true
	}
	if p.isPlaybackStale(seg.Epoch) {
		return true
	}
	return seg.Supersedable && p.latestSpeechEpoch.Load() > seg.SpeechEpochAtQueue
}

func (p *DirectPeer) isAVSegmentStale(seg *mediapeer.AVSegment) bool {
	if seg == nil {
		return true
	}
	if p.isPlaybackStale(seg.Epoch) {
		return true
	}
	return seg.Supersedable && p.latestSpeechEpoch.Load() > seg.SpeechEpochAtQueue
}

// PublishAudioFrame publishes raw PCM audio (for TTS in standard pipeline).
func (p *DirectPeer) PublishAudioFrame(pcm []byte, sampleRate int) error {
	if len(pcm) == 0 || sampleRate <= 0 {
		return nil
	}
	p.mediaMu.Lock()
	defer p.mediaMu.Unlock()

	if !p.waitConnected(10 * time.Second) {
		if p.avPipelineCtx.Err() != nil {
			return fmt.Errorf("audio publish cancelled")
		}
		return fmt.Errorf("audio publish timeout waiting for connection")
	}
	return p.writeOpus(pcm, sampleRate)
}

// writeOpus encodes PCM to Opus and writes to the audio track.
// Opus encodes in 20ms frames.
func (p *DirectPeer) writeOpus(pcm []byte, sampleRate int) error {
	p.opusMu.Lock()
	defer p.opusMu.Unlock()

	p.mu.Lock()
	audioTrack := p.audioTrack
	p.mu.Unlock()
	if audioTrack == nil {
		return fmt.Errorf("audio track is not ready")
	}

	// Lazily create or recreate encoder if sample rate changed
	if p.opusEncoder == nil || p.opusEncoderSR != sampleRate {
		enc, err := opus.NewEncoder(sampleRate, 1, opus.AppVoIP)
		if err != nil {
			return fmt.Errorf("create opus encoder: %w", err)
		}
		p.opusEncoder = enc
		p.opusEncoderSR = sampleRate
	}

	// Process PCM in 20ms frames
	samplesPerFrame := sampleRate / 50   // 20ms = 1/50 second
	bytesPerFrame := samplesPerFrame * 2 // 16-bit mono
	opusBuf := make([]byte, 4000)        // max opus frame size
	frameDuration := 20 * time.Millisecond

	for offset := 0; offset+bytesPerFrame <= len(pcm); offset += bytesPerFrame {
		// Convert bytes to int16 samples
		samples := make([]int16, samplesPerFrame)
		for i := 0; i < samplesPerFrame; i++ {
			samples[i] = int16(binary.LittleEndian.Uint16(pcm[offset+i*2:]))
		}

		n, err := p.opusEncoder.Encode(samples, opusBuf)
		if err != nil {
			return fmt.Errorf("opus encode: %w", err)
		}
		if n == 0 {
			continue
		}
		payload := append([]byte(nil), opusBuf[:n]...)

		if err := audioTrack.WriteSample(media.Sample{
			Data:     payload,
			Duration: frameDuration,
		}); err != nil {
			return fmt.Errorf("write audio sample: %w", err)
		}
		if err := p.sleepAudioFrame(frameDuration); err != nil {
			return err
		}
	}
	return nil
}

func (p *DirectPeer) sleepAudioFrame(d time.Duration) error {
	if d <= 0 {
		return nil
	}
	_, err := p.sleepUntil(time.Now().Add(d))
	return err
}

func (p *DirectPeer) sleepUntil(deadline time.Time) (time.Duration, error) {
	if deadline.IsZero() {
		return 0, nil
	}
	delay := time.Until(deadline)
	if delay <= 0 {
		return -delay, nil
	}
	ctx := p.avPipelineCtx
	if ctx == nil {
		time.Sleep(delay)
		if slip := time.Since(deadline); slip > 0 {
			return slip, nil
		}
		return 0, nil
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return 0, fmt.Errorf("media publish cancelled")
	case <-timer.C:
		if slip := time.Since(deadline); slip > 0 {
			return slip, nil
		}
		return 0, nil
	}
}

// Disconnect tears down the peer connection and releases resources.
func (p *DirectPeer) Disconnect() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.pc != nil {
		err := p.pc.Close()
		p.pc = nil
		// userAudioCh is intentionally NOT closed: readUserAudio may still be
		// sending concurrently (a send on a closed channel panics). It stops
		// writing once the track closes after pc.Close(), and readers drain
		// the channel via ok-checks / non-blocking receives.
		return err
	}
	return nil
}
