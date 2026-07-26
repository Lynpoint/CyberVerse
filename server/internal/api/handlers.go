package api

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/cyberverse/server/internal/character"
	"github.com/cyberverse/server/internal/config"
	"github.com/cyberverse/server/internal/livekit"
	"github.com/cyberverse/server/internal/orchestrator"
	"github.com/cyberverse/server/internal/ws"
)

type CreateSessionRequest struct {
	Mode        string `json:"mode"`         // "omni" or "standard" ("voice_llm" accepted as a legacy alias)
	CharacterID string `json:"character_id"` // which character this session is for
}

type CreateSessionResponse struct {
	SessionID     string                     `json:"session_id"`
	Mode          string                     `json:"mode"`
	StreamingMode string                     `json:"streaming_mode"`
	AvatarEnabled bool                       `json:"avatar_enabled"`
	IdleStrategy  string                     `json:"idle_strategy"`
	AudioInput    *AudioInputResponse        `json:"audio_input,omitempty"`
	BaiduXiling   *baiduXilingSessionConfig  `json:"baidu_xiling,omitempty"`
	Xunfei        *xunfeiAvatarSessionConfig `json:"xunfei,omitempty"`
	Vidu          *viduSessionConfig         `json:"vidu,omitempty"`
	LiveKitURL    string                     `json:"livekit_url,omitempty"`
	Token         string                     `json:"livekit_token,omitempty"`
	IdleVideoURL  string                     `json:"idle_video_url,omitempty"`
	IdleVideoURLs []string                   `json:"idle_video_urls,omitempty"`
	IdleImageURL  string                     `json:"idle_image_url,omitempty"`
	Warnings      []string                   `json:"warnings,omitempty"`
	VisualInput   *VisualInputResponse       `json:"visual_input,omitempty"`
}

type AudioInputResponse struct {
	Enabled bool `json:"enabled"`
}

type VisualInputResponse struct {
	Enabled           bool    `json:"enabled"`
	FrameIntervalMS   int     `json:"frame_interval_ms"`
	MaxWidth          int     `json:"max_width"`
	MaxHeight         int     `json:"max_height"`
	JPEGQuality       float64 `json:"jpeg_quality"`
	MaxFrameBytes     int     `json:"max_frame_bytes"`
	WSMaxMessageBytes int64   `json:"ws_max_message_bytes"`
	MaxRecentFrames   int     `json:"max_recent_frames"`
	FrameTTLMS        int     `json:"frame_ttl_ms"`
}

type SendMessageRequest struct {
	Text string `json:"text"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

func modeString(mode orchestrator.PipelineMode) string {
	if mode == orchestrator.ModeStandard {
		return "standard"
	}
	return "omni"
}

func parsePipelineMode(modeName string) orchestrator.PipelineMode {
	switch strings.TrimSpace(modeName) {
	case "omni", "voice_llm":
		return orchestrator.ModeOmni
	case "standard":
		return orchestrator.ModeStandard
	default:
		return orchestrator.ModeStandard
	}
}

func normalizedVisualInputResponse(cfg config.VisualInputConfig) VisualInputResponse {
	if cfg.FrameIntervalMS == 0 {
		cfg.FrameIntervalMS = 1000
	}
	if cfg.MaxWidth == 0 {
		cfg.MaxWidth = 1280
	}
	if cfg.MaxHeight == 0 {
		cfg.MaxHeight = 720
	}
	if cfg.JPEGQuality == 0 {
		cfg.JPEGQuality = 0.78
	}
	if cfg.MaxFrameBytes == 0 {
		cfg.MaxFrameBytes = 512 * 1024
	}
	if cfg.WSMaxMessageBytes == 0 {
		cfg.WSMaxMessageBytes = 1024 * 1024
	}
	if cfg.MaxRecentFrames == 0 {
		cfg.MaxRecentFrames = 2
	}
	if cfg.FrameTTLMS == 0 {
		cfg.FrameTTLMS = 10000
	}
	return VisualInputResponse{
		Enabled:           cfg.IsEnabled(),
		FrameIntervalMS:   cfg.FrameIntervalMS,
		MaxWidth:          cfg.MaxWidth,
		MaxHeight:         cfg.MaxHeight,
		JPEGQuality:       cfg.JPEGQuality,
		MaxFrameBytes:     cfg.MaxFrameBytes,
		WSMaxMessageBytes: cfg.WSMaxMessageBytes,
		MaxRecentFrames:   cfg.MaxRecentFrames,
		FrameTTLMS:        cfg.FrameTTLMS,
	}
}

func (r *Router) audioInputResponseForSession(session *orchestrator.Session) *AudioInputResponse {
	if session == nil {
		return nil
	}
	return &AudioInputResponse{Enabled: r.orch != nil}
}

func (r *Router) visualInputResponseForSession(session *orchestrator.Session) *VisualInputResponse {
	if session == nil {
		return nil
	}
	if r.orch != nil {
		cfg, supported := r.orch.VisualInputConfigForSession(session)
		if !supported {
			return nil
		}
		resp := normalizedVisualInputResponse(cfg)
		return &resp
	}
	if session.Mode == orchestrator.ModeStandard {
		visualCfg := config.VisualInputConfig{}
		if r.cfg != nil {
			visualCfg = r.cfg.Pipeline.VisualInput
		}
		resp := normalizedVisualInputResponse(visualCfg)
		return &resp
	}
	return nil
}

func (r *Router) handleHealth(w http.ResponseWriter, req *http.Request) {
	inferenceErr := r.inferenceHealthError(req.Context())
	connected := inferenceErr == nil
	status := "ok"
	errorMessage := ""
	if !connected {
		status = "error"
		errorMessage = inferenceErr.Error()
	}

	payload := map[string]any{
		"status":              status,
		"sessions":            r.sessionMgr.Count(),
		"inference_connected": connected,
		"error":               errorMessage,
	}
	if body, err := json.Marshal(payload); err == nil {
		log.Printf("[health] GET /api/v1/health response: %s", body)
	}

	writeJSON(w, http.StatusOK, payload)
}

func (r *Router) handleCreateSession(w http.ResponseWriter, req *http.Request) {
	var body CreateSessionRequest
	if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON: " + err.Error()})
		return
	}

	modeName := body.Mode
	if modeName == "" && r.cfg != nil {
		modeName = r.cfg.Pipeline.DefaultMode
	}
	mode := parsePipelineMode(modeName)

	ownerID := ""
	if isKanshanCharacter(body.CharacterID) {
		var ownerErr error
		ownerID, ownerErr = r.ensureAnonymousOwner(w, req)
		if ownerErr != nil {
			writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: ownerErr.Error()})
			return
		}
	}

	var sessionCharacter *character.Character
	if r.charStore != nil && body.CharacterID != "" {
		if ch, err := r.charStore.Get(body.CharacterID); err == nil {
			sessionCharacter = ch
		}
	}

	if sessionCharacter != nil && sessionCharacter.AvatarBackend == character.AvatarBackendBaiduXiling {
		if sessionCharacter.BaiduXiling == nil || strings.TrimSpace(sessionCharacter.BaiduXiling.FigureID) == "" {
			writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "Baidu Xiling figure_id is required"})
			return
		}
	}
	if sessionCharacter != nil && sessionCharacter.AvatarBackend == character.AvatarBackendXunfei {
		if sessionCharacter.Xunfei == nil || strings.TrimSpace(sessionCharacter.Xunfei.AvatarID) == "" {
			writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "Xunfei avatar_id is required"})
			return
		}
	}
	if sessionCharacter != nil && sessionCharacter.AvatarBackend == character.AvatarBackendVidu {
		if strings.TrimSpace(sessionCharacter.ActiveImage) == "" && strings.TrimSpace(sessionCharacter.AvatarImage) == "" {
			writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "Vidu S1 requires an uploaded character image"})
			return
		}
	}

	isBaiduXilingCharacter := sessionCharacter != nil && sessionCharacter.AvatarBackend == character.AvatarBackendBaiduXiling
	isXunfeiCharacter := sessionCharacter != nil && sessionCharacter.AvatarBackend == character.AvatarBackendXunfei
	isViduCharacter := sessionCharacter != nil && sessionCharacter.AvatarBackend == character.AvatarBackendVidu

	if r.orch != nil && body.CharacterID != "" && r.orch.AvatarEnabled() && !isBaiduXilingCharacter && !isXunfeiCharacter && !isViduCharacter {
		activeModel, err := r.activeAvatarModel(req.Context())
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{Error: err.Error()})
			return
		}
		if sessionCharacter != nil && sessionCharacter.AvatarBackend == character.AvatarBackendLocalImage && activeModel == character.AvatarBackendBaiduXiling {
			writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{Error: "Local image characters require the active avatar model to be flash_head or live_act"})
			return
		}
	}

	sessionID := uuid.New().String()
	session, err := r.sessionMgr.Create(sessionID, mode, body.CharacterID)
	if err != nil {
		status := http.StatusInternalServerError
		if err == orchestrator.ErrMaxSessions {
			status = http.StatusServiceUnavailable
		}
		writeJSON(w, status, ErrorResponse{Error: err.Error()})
		return
	}
	if ownerID != "" {
		session.SetOwnerID(ownerID)
	}
	if r.orch != nil {
		if err := r.orch.HydrateVoiceDialogContext(session); err != nil {
			log.Printf("Failed to load dialog context for session %s character %s: %v", sessionID, body.CharacterID, err)
		}
	}

	// If character uses random image mode, pick a random image
	if body.CharacterID != "" {
		if ch := sessionCharacter; ch != nil {
			if ch.AvatarBackend == character.AvatarBackendLocalImage && ch.ImageMode == "random" && len(ch.Images) > 1 {
				if rErr := r.charStore.RandomizeImage(body.CharacterID); rErr != nil {
					log.Printf("Failed to randomize image for character %s: %v", body.CharacterID, rErr)
				}
			}
		}
	}

	resp := CreateSessionResponse{
		SessionID:    sessionID,
		Mode:         modeString(mode),
		IdleStrategy: config.AvatarIdleStrategyCachedVideo,
	}
	if r.orch != nil {
		resp.IdleStrategy = r.orch.AvatarIdleStrategy()
		if !r.orch.AvatarEnabled() {
			resp.IdleStrategy = config.AvatarIdleStrategyCachedVideo
		}
	} else if r.cfg != nil {
		resp.IdleStrategy = r.cfg.AvatarIdleStrategy()
		if !r.cfg.AvatarEnabled() {
			resp.IdleStrategy = config.AvatarIdleStrategyCachedVideo
		}
	}
	resp.VisualInput = r.visualInputResponseForSession(session)
	resp.AudioInput = r.audioInputResponseForSession(session)
	if isViduCharacter {
		resp.VisualInput = nil
		resp.AudioInput = &AudioInputResponse{Enabled: false}
	}

	useCachedIdleVideo := resp.IdleStrategy != config.AvatarIdleStrategySilentInference
	if isBaiduXilingCharacter {
		baiduConfig, err := buildBaiduXilingSessionConfig(sessionCharacter)
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{Error: err.Error()})
			return
		}
		resp.BaiduXiling = baiduConfig
		resp.IdleImageURL = characterStandbyImageURL(sessionCharacter)
		if useCachedIdleVideo {
			resp.IdleVideoURLs = baiduXilingPreviewVideoURLs(sessionCharacter)
			if len(resp.IdleVideoURLs) > 0 {
				resp.IdleVideoURL = resp.IdleVideoURLs[0]
			}
		}
	} else if isXunfeiCharacter {
		if r.orch == nil {
			r.sessionMgr.Delete(sessionID)
			writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{Error: "Xunfei avatar sessions require the orchestrator"})
			return
		}
		startCtx, cancel := context.WithTimeout(req.Context(), 30*time.Second)
		defer cancel()
		xunfeiRuntime, xunfeiConfig, err := startXunfeiAvatarSession(startCtx, sessionCharacter)
		if err != nil {
			r.sessionMgr.Delete(sessionID)
			writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{Error: err.Error()})
			return
		}
		r.orch.RegisterXunfeiAvatarSession(sessionID, xunfeiRuntime)
		if detectXunfeiStreamTransport(xunfeiConfig.StreamURL) != xunfeiStreamTransportUnknown {
			xunfeiConfig.PlaybackURL = "/api/v1/xunfei/sessions/" + sessionID + "/stream.flv"
		}
		resp.Xunfei = xunfeiConfig
		resp.IdleImageURL = characterStandbyImageURL(sessionCharacter)
	} else if isViduCharacter {
		if r.orch == nil {
			r.sessionMgr.Delete(sessionID)
			writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{Error: "Vidu S1 sessions require the orchestrator"})
			return
		}
		startCtx, cancel := context.WithTimeout(req.Context(), 2*time.Minute)
		defer cancel()
		viduRuntime, viduConfig, err := r.startViduSession(startCtx, sessionCharacter)
		if err != nil {
			r.sessionMgr.Delete(sessionID)
			writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{Error: err.Error()})
			return
		}
		viduRuntime.SetOnLost(func(reason string) {
			log.Printf("Vidu S1 session lost session=%s reason=%s", sessionID, reason)
			r.sessionMgr.Delete(sessionID)
		})
		r.orch.RegisterViduSession(sessionID, viduRuntime)
		resp.Vidu = viduConfig
		resp.IdleImageURL = characterStandbyImageURL(sessionCharacter)
		go func() {
			timer := time.NewTimer(45 * time.Second)
			defer timer.Stop()
			<-timer.C
			if !r.orch.ViduSessionReady(sessionID) {
				log.Printf("Vidu S1 client RTC readiness timeout session=%s", sessionID)
				r.sessionMgr.Delete(sessionID)
			}
		}()
	} else if r.orch != nil && body.CharacterID != "" && useCachedIdleVideo && (sessionCharacter == nil || sessionCharacter.AvatarBackend == character.AvatarBackendLocalImage) {
		target := r.currentIdleVideoTarget(req.Context())
		// Return any already-cached idle video URLs immediately; generation happens in background.
		if char, err := r.charStore.Get(body.CharacterID); err == nil {
			resp.IdleImageURL = characterStandbyImageURL(char)
			resp.IdleVideoURLs = r.idleVideoURLs(char.ID, char.ActiveImage, target)
			if len(resp.IdleVideoURLs) > 0 {
				resp.IdleVideoURL = resp.IdleVideoURLs[0]
			}
		}
		// Trigger background generation only if the current-resolution idle video does not exist yet.
		// Once ready, push the URLs to the frontend via WebSocket so the idle
		// videos can start playing without a page reload.
		if len(resp.IdleVideoURLs) == 0 && r.orch.AvatarEnabled() {
			char, _ := r.charStore.Get(body.CharacterID)
			activeImage := ""
			if char != nil {
				activeImage = char.ActiveImage
			}
			go func(charID, sessID, img string) {
				bgCtx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
				defer cancel()
				if _, err := r.orch.EnsureIdleVideo(bgCtx, charID); err != nil {
					if warning, ok := orchestrator.AvatarImageTooLargeWarning(err); ok {
						log.Printf("Idle video background generation failed for character %s: %s details=%v", charID, warning, err)
						if r.wsHub != nil {
							r.wsHub.BroadcastJSON(sessID, map[string]any{
								"type":    "avatar_warning",
								"message": warning,
							})
						}
					} else {
						log.Printf("Idle video background generation failed for character %s: %v", charID, err)
					}
					return
				}
				urls := r.idleVideoURLs(charID, img, r.currentIdleVideoTarget(bgCtx))
				if len(urls) > 0 {
					r.wsHub.BroadcastJSON(sessID, map[string]any{
						"type": "idle_video_ready",
						"url":  urls[0],
						"urls": urls,
					})
				}
			}(body.CharacterID, sessionID, activeImage)
		}
	}

	// Set up media peer (DirectPeer or LiveKit Bot) if orchestrator is available
	if r.orch != nil {
		streamingMode := r.orch.StreamingMode()
		resp.StreamingMode = streamingMode
		resp.AvatarEnabled = r.orch.AvatarEnabled()
		if isViduCharacter {
			resp.AvatarEnabled = true
		}
		setupMediaPeer := !isViduCharacter && resp.AudioInput != nil && resp.AudioInput.Enabled
		if setupMediaPeer {
			// Generate LiveKit token only in livekit mode.
			if streamingMode == "livekit" && r.roomMgr != nil && r.cfg != nil {
				roomName := livekit.RoomName(sessionID)
				token, err := livekit.GenerateToken(
					r.cfg.LiveKit.APIKey,
					r.cfg.LiveKit.APISecret,
					roomName,
					"user-"+sessionID,
					true,
				)
				if err != nil {
					log.Printf("Failed to generate LiveKit token: %v", err)
				} else {
					resp.LiveKitURL = r.cfg.LiveKit.URL
					resp.Token = token
				}
			}

			// Setup session with media peer.
			// Important: don't tie this lifecycle to req.Context(), because the browser client
			// may abort/cancel the HTTP request (navigation, rapid reconnect, etc.).
			setupCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()

			peer, warnings, err := r.orch.SetupSession(setupCtx, session, r.roomMgr)
			resp.Warnings = append(resp.Warnings, warnings...)
			if err != nil {
				log.Printf("Failed to setup session %s: %v", sessionID, err)
			} else {
				// Both omni and standard sessions consume mic audio. The
				// orchestrator dispatches to the correct pipeline by session mode.
				go func() {
					if err := r.orch.HandleAudioStream(context.Background(), sessionID, peer.SubscribeUserAudio()); err != nil {
						log.Printf("Failed to start audio stream for session %s: %v", sessionID, err)
					}
				}()
			}
		}
	}

	writeJSON(w, http.StatusCreated, resp)
}

func baiduXilingPreviewVideoURLs(c *character.Character) []string {
	if c == nil || c.BaiduXiling == nil {
		return nil
	}
	url := strings.TrimSpace(c.BaiduXiling.PreviewVideoURL)
	if url == "" {
		return nil
	}
	return []string{url}
}

func baiduXilingPreviewImageURL(c *character.Character) string {
	if c == nil || c.BaiduXiling == nil {
		return ""
	}
	if url := strings.TrimSpace(c.BaiduXiling.ThumbnailURL); url != "" {
		return url
	}
	return strings.TrimSpace(c.BaiduXiling.SourceImageURL)
}

func xunfeiPreviewImageURL(c *character.Character) string {
	if c == nil || c.Xunfei == nil {
		return ""
	}
	if url := strings.TrimSpace(c.Xunfei.ThumbnailURL); url != "" {
		return url
	}
	return strings.TrimSpace(c.Xunfei.SourceImageURL)
}

func characterStandbyImageURL(c *character.Character) string {
	if c == nil {
		return ""
	}
	if url := strings.TrimSpace(c.AvatarImage); url != "" {
		return url
	}
	switch c.AvatarBackend {
	case character.AvatarBackendBaiduXiling:
		return baiduXilingPreviewImageURL(c)
	case character.AvatarBackendXunfei:
		return xunfeiPreviewImageURL(c)
	default:
		return ""
	}
}

func (r *Router) handleDeleteSession(w http.ResponseWriter, req *http.Request) {
	id := req.PathValue("id")
	session, err := r.sessionMgr.Get(id)
	if err != nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		return
	}
	if !r.authorizeKanshanSessionAccess(w, req, session) {
		return
	}

	// Teardown orchestrator resources
	if r.orch != nil {
		if err := r.orch.TeardownSession(id); err != nil {
			log.Printf("Failed to teardown session %s: %v", id, err)
		}
	}

	r.sessionMgr.Delete(id)
	w.WriteHeader(http.StatusNoContent)
}

func (r *Router) handleSendMessage(w http.ResponseWriter, req *http.Request) {
	id := req.PathValue("id")
	session, err := r.sessionMgr.Get(id)
	if err != nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		return
	}
	if !r.authorizeKanshanSessionAccess(w, req, session) {
		return
	}

	var body SendMessageRequest
	if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid JSON: " + err.Error()})
		return
	}
	if body.Text == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "text is required"})
		return
	}

	// Note: HandleTextInput already calls session.AddMessage for user role,
	// so we do NOT add it here to avoid duplicate messages.

	// Trigger the standard pipeline via orchestrator
	if r.orch != nil {
		if handled, err := r.orch.SendViduTextInput(id, body.Text); handled {
			if err != nil {
				log.Printf("Failed to handle Vidu S1 text input for session %s: %v", id, err)
				writeJSON(w, http.StatusConflict, ErrorResponse{Error: err.Error()})
				return
			}
			writeJSON(w, http.StatusAccepted, map[string]string{"status": "queued"})
			return
		}
		if err := r.orch.HandleTextInput(context.Background(), id, body.Text); err != nil {
			log.Printf("Failed to handle text input for session %s: %v", id, err)
			writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: "failed to process message"})
			return
		}
	}

	writeJSON(w, http.StatusAccepted, map[string]string{"status": "queued"})
}

func (r *Router) handleListSessions(w http.ResponseWriter, req *http.Request) {
	sessions := r.sessionMgr.List()
	type sessionInfo struct {
		ID    string `json:"id"`
		State string `json:"state"`
	}
	result := make([]sessionInfo, len(sessions))
	ownerID, hasOwner := anonymousOwnerFromRequest(req)
	result = result[:0]
	for _, s := range sessions {
		if isKanshanCharacter(s.CharacterID) {
			if !hasOwner || s.OwnerIDSnapshot() != ownerID {
				continue
			}
		}
		result = append(result, sessionInfo{ID: s.ID, State: s.GetState().String()})
	}
	writeJSON(w, http.StatusOK, result)
}

func (r *Router) handleWebSocket(w http.ResponseWriter, req *http.Request) {
	id := req.PathValue("id")
	session, err := r.sessionMgr.Get(id)
	if err != nil {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}
	if isKanshanCharacter(session.CharacterID) {
		ownerID, ownerErr := r.ensureAnonymousOwner(w, req)
		if ownerErr != nil {
			http.Error(w, ownerErr.Error(), http.StatusInternalServerError)
			return
		}
		if session.OwnerIDSnapshot() != ownerID {
			http.Error(w, "session not found", http.StatusNotFound)
			return
		}
	}

	maxMessageSize := int64(0)
	if r.cfg != nil {
		visualCfg := normalizedVisualInputResponse(r.cfg.Pipeline.VisualInput)
		maxMessageSize = visualCfg.WSMaxMessageBytes
	}

	handler := ws.HandleWebSocketWithReadLimit(
		r.wsHub,
		id,
		maxMessageSize,
		func(sessionID string, msg ws.WSMessage) {
			switch msg.Type {
			case "text_input":
				if r.orch != nil && msg.Text != "" {
					go func() {
						if handled, err := r.orch.SendViduTextInput(sessionID, msg.Text); handled {
							if err != nil {
								log.Printf("Failed to handle Vidu S1 WS text input for session %s: %v", sessionID, err)
								r.wsHub.BroadcastJSON(sessionID, map[string]any{"type": "vidu_error", "message": err.Error()})
							}
							return
						}
						// Detach from request context to avoid cancelling an in-flight text turn.
						if err := r.orch.HandleTextInput(context.Background(), sessionID, msg.Text); err != nil {
							log.Printf("Failed to handle WS text input for session %s: %v", sessionID, err)
						}
					}()
				}
			case "vidu_rtc_ready":
				if r.orch != nil {
					go func() {
						ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
						defer cancel()
						handled, err := r.orch.ConnectViduSession(ctx, sessionID)
						if !handled {
							return
						}
						if err != nil {
							log.Printf("Vidu S1 control connection failed session=%s: %v", sessionID, err)
							r.wsHub.BroadcastJSON(sessionID, map[string]any{"type": "vidu_error", "message": err.Error()})
							r.sessionMgr.Delete(sessionID)
							return
						}
						r.wsHub.BroadcastJSON(sessionID, map[string]any{"type": "vidu_ready"})
					}()
				}
			case "vidu_rtc_failed":
				if r.orch != nil {
					r.wsHub.BroadcastJSON(sessionID, map[string]any{"type": "vidu_error", "message": "Vidu S1 RTC connection failed"})
					r.sessionMgr.Delete(sessionID)
				}
			case "interrupt":
				if r.orch != nil {
					if err := r.orch.Interrupt(sessionID); err != nil {
						log.Printf("Failed to interrupt session %s: %v", sessionID, err)
					}
				}
			case "client_media_ready":
				if r.orch != nil {
					go func() {
						log.Printf("client_media_ready received for session %s", sessionID)
						if err := r.orch.HandleClientMediaReady(context.Background(), sessionID); err != nil {
							log.Printf("Failed to start proactive greeting for session %s: %v", sessionID, err)
						}
					}()
				}
			case "webrtc_ready", "webrtc_answer", "ice_candidate", "av_calibration_config", "av_sync_feedback", "direct_media_reset_request":
				if r.orch != nil {
					r.orch.HandleSignaling(sessionID, msg)
				}
			case "visual_input_start":
				r.handleVisualInputMessage(sessionID, msg, func() error {
					return r.orch.HandleVisualInputStart(sessionID, msg.Source)
				})
			case "visual_frame":
				r.handleVisualInputMessage(sessionID, msg, func() error {
					return r.orch.HandleVisualFrame(sessionID, msg)
				})
			case "visual_input_stop":
				r.handleVisualInputMessage(sessionID, msg, func() error {
					return r.orch.HandleVisualInputStop(sessionID, msg.Source)
				})
			}
		},
		func(sessionID string) {
			_ = r.sessionMgr.Touch(sessionID)
		},
	)
	handler(w, req)
}

func (r *Router) handleVisualInputMessage(sessionID string, _ ws.WSMessage, fn func() error) {
	if r.orch == nil {
		return
	}
	if err := fn(); err != nil {
		msgType := "visual_input_error"
		if errors.Is(err, orchestrator.ErrVisualInputUnsupported) || errors.Is(err, orchestrator.ErrVisualInputDisabled) {
			msgType = "visual_input_unsupported"
		}
		log.Printf("visual input message failed for session %s: %v", sessionID, err)
		if r.wsHub != nil {
			r.wsHub.BroadcastJSON(sessionID, map[string]any{
				"type":    msgType,
				"message": err.Error(),
			})
		}
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("writeJSON encode error: %v", err)
	}
}

func (r *Router) inferenceHealthError(ctx context.Context) error {
	if r.orch == nil {
		return errInferenceUnavailable
	}
	return r.orch.HealthCheck(ctx)
}
