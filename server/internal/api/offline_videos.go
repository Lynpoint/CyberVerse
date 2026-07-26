package api

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/cyberverse/server/internal/character"
	"github.com/cyberverse/server/internal/inference"
	"github.com/cyberverse/server/internal/orchestrator"
)

const offlineVideoRootName = "offline_videos"

var offlineVideoMu sync.Mutex

type offlineVideoJob struct {
	ID              string `json:"id"`
	CharacterID     string `json:"character_id"`
	Title           string `json:"title"`
	Provider        string `json:"provider,omitempty"`
	InputType       string `json:"input_type"`
	Text            string `json:"text,omitempty"`
	Status          string `json:"status"`
	Stage           string `json:"stage,omitempty"`
	Message         string `json:"message,omitempty"`
	Progress        int    `json:"progress"`
	Error           string `json:"error,omitempty"`
	AudioFilename   string `json:"audio_filename,omitempty"`
	VideoFilename   string `json:"video_filename,omitempty"`
	RemoteVideoURL  string `json:"remote_video_url,omitempty"`
	BaiduTaskID     string `json:"baidu_task_id,omitempty"`
	DurationMS      int    `json:"duration_ms,omitempty"`
	Width           int    `json:"width,omitempty"`
	Height          int    `json:"height,omitempty"`
	FPS             int    `json:"fps,omitempty"`
	FrameCount      int    `json:"frame_count,omitempty"`
	AudioSampleRate int    `json:"audio_sample_rate,omitempty"`
	CreatedAt       string `json:"created_at"`
	UpdatedAt       string `json:"updated_at"`
	FinishedAt      string `json:"finished_at,omitempty"`
}

type offlineVideoJobResponse struct {
	offlineVideoJob
	VideoURL string `json:"video_url,omitempty"`
}

type offlineVideoRunInput struct {
	JobID       string
	CharacterID string
	ImageData   []byte
	ImageFormat string
	Text        string
	Audio       *orchestrator.OfflineAudioInput
	TTSConfig   inference.TTSConfig
	OutputPath  string
}

type updateOfflineVideoRequest struct {
	Title string `json:"title"`
}

type baiduXilingOfflineVideoRunInput struct {
	JobID           string
	CharacterID     string
	FigureID        string
	TemplateID      string
	InputType       string
	Text            string
	Title           string
	OutputPath      string
	Width           int
	Height          int
	TTSConfig       inference.TTSConfig
	BaiduVideoInput baiduXilingAdvancedVideoSubmitInput
}

type baiduXilingOfflineVideoOptions struct {
	Width              int
	Height             int
	Transparent        bool
	TTSPerson          string
	TTSLan             string
	TTSSpeed           string
	TTSVolume          string
	TTSPitch           string
	BackgroundImageURL string
	AutoAnimoji        bool
}

type xunfeiOfflineVideoRunInput struct {
	JobID       string
	CharacterID string
	Text        string
	Audio       *orchestrator.OfflineAudioInput
	TTSConfig   inference.TTSConfig
	OutputPath  string
	CRF         int
}

func (r *Router) handleListOfflineVideos(w http.ResponseWriter, req *http.Request) {
	jobs, err := r.listOfflineVideoJobs(req.PathValue("id"))
	if err != nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"videos": jobs})
}

func (r *Router) handleCreateOfflineVideo(w http.ResponseWriter, req *http.Request) {
	if r.orch == nil {
		writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{Error: "orchestrator is not configured"})
		return
	}
	characterID := req.PathValue("id")
	ch, err := r.charStore.Get(characterID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		return
	}

	req.Body = http.MaxBytesReader(w, req.Body, 96<<20)
	if err := req.ParseMultipartForm(96 << 20); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid form data: " + err.Error()})
		return
	}

	inputType := strings.ToLower(strings.TrimSpace(req.FormValue("input_type")))
	text := strings.TrimSpace(req.FormValue("text"))
	if inputType == "" {
		if text != "" {
			inputType = "text"
		} else {
			inputType = "audio"
		}
	}
	if inputType != "text" && inputType != "audio" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "input_type must be text or audio"})
		return
	}
	if inputType == "text" && text == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "text input is required"})
		return
	}
	if ch.AvatarBackend == character.AvatarBackendVidu {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "Vidu S1 supports live streaming sessions only"})
		return
	}
	if ch.AvatarBackend == character.AvatarBackendBaiduXiling {
		r.handleCreateBaiduXilingOfflineVideo(w, req, ch, inputType, text)
		return
	}
	if ch.AvatarBackend == character.AvatarBackendXunfei {
		r.handleCreateXunfeiOfflineVideo(w, req, ch, inputType, text)
		return
	}

	imageData, imageFormat, err := r.offlineVideoAvatarImage(ch)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	root, err := r.offlineVideoRoot(characterID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		return
	}
	jobID := uuid.NewString()
	ttsConfig, err := r.offlineVideoTTSConfig(req, ch, inputType, "offline-"+jobID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}
	jobDir := filepath.Join(root, jobID)
	if err := os.MkdirAll(jobDir, 0755); err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	var audio *orchestrator.OfflineAudioInput
	if inputType == "audio" {
		audio, err = readOfflineVideoAudio(req, jobDir)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: err.Error()})
			return
		}
	}

	now := time.Now().UTC().Format(time.RFC3339)
	title := strings.TrimSpace(req.FormValue("title"))
	if title == "" {
		title = defaultOfflineVideoTitle()
	}
	job := &offlineVideoJob{
		ID:          jobID,
		CharacterID: characterID,
		Title:       title,
		Provider:    "local_avatar",
		InputType:   inputType,
		Text:        text,
		Status:      "queued",
		Stage:       "queued",
		Message:     "Queued for offline generation",
		Progress:    0,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if err := writeOfflineVideoJob(jobDir, job); err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	runInput := offlineVideoRunInput{
		JobID:       jobID,
		CharacterID: characterID,
		ImageData:   imageData,
		ImageFormat: imageFormat,
		Text:        text,
		Audio:       audio,
		TTSConfig:   ttsConfig,
		OutputPath:  filepath.Join(jobDir, "output.mp4"),
	}
	go r.runOfflineVideoJob(runInput)

	writeJSON(w, http.StatusCreated, r.offlineVideoResponse(job))
}

func (r *Router) handleCreateBaiduXilingOfflineVideo(w http.ResponseWriter, req *http.Request, ch *character.Character, inputType, text string) {
	if ch == nil || ch.BaiduXiling == nil || strings.TrimSpace(ch.BaiduXiling.FigureID) == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "Baidu Xiling figure_id is required"})
		return
	}
	appID := strings.TrimSpace(os.Getenv("BAIDU_XILING_APP_ID"))
	appKey := strings.TrimSpace(os.Getenv("BAIDU_XILING_APP_KEY"))
	if appID == "" || appKey == "" {
		writeJSON(w, http.StatusServiceUnavailable, ErrorResponse{Error: "Baidu Xiling credentials are not configured"})
		return
	}
	templateID := baiduXilingOfflineTemplateID()
	driveType := "TEXT"
	if inputType == "audio" {
		driveType = "VOICE"
	}

	root, err := r.offlineVideoRoot(ch.ID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		return
	}
	jobID := uuid.NewString()
	jobDir := filepath.Join(root, jobID)
	if err := os.MkdirAll(jobDir, 0755); err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	inputAudioURL := ""
	if inputType == "audio" {
		inputAudioURL, err = baiduXilingInputAudioURLFromRequest(req)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: err.Error()})
			return
		}
	}

	now := time.Now().UTC().Format(time.RFC3339)
	title := strings.TrimSpace(req.FormValue("title"))
	if title == "" {
		title = defaultOfflineVideoTitle()
	}
	videoOptions := baiduXilingOfflineVideoOptionsFromRequest(req, ch)
	job := &offlineVideoJob{
		ID:          jobID,
		CharacterID: ch.ID,
		Title:       title,
		Provider:    character.AvatarBackendBaiduXiling,
		InputType:   inputType,
		Text:        text,
		Status:      "queued",
		Stage:       "queued",
		Message:     "Queued for Baidu Xiling cloud synthesis",
		Progress:    0,
		Width:       videoOptions.Width,
		Height:      videoOptions.Height,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if err := writeOfflineVideoJob(jobDir, job); err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	runInput := baiduXilingOfflineVideoRunInput{
		JobID:       jobID,
		CharacterID: ch.ID,
		FigureID:    strings.TrimSpace(ch.BaiduXiling.FigureID),
		TemplateID:  templateID,
		InputType:   inputType,
		Text:        text,
		Title:       title,
		OutputPath:  filepath.Join(jobDir, baiduXilingOfflineOutputFilename(videoOptions.Transparent)),
		Width:       videoOptions.Width,
		Height:      videoOptions.Height,
		BaiduVideoInput: baiduXilingAdvancedVideoSubmitInput{
			FigureID:           strings.TrimSpace(ch.BaiduXiling.FigureID),
			TemplateID:         templateID,
			DriveType:          driveType,
			InputAudioURL:      inputAudioURL,
			Text:               text,
			Title:              title,
			Width:              videoOptions.Width,
			Height:             videoOptions.Height,
			Model:              strings.TrimSpace(os.Getenv("BAIDU_XILING_OFFLINE_MODEL")),
			TTSPerson:          videoOptions.TTSPerson,
			TTSLan:             videoOptions.TTSLan,
			TTSSpeed:           videoOptions.TTSSpeed,
			TTSVolume:          videoOptions.TTSVolume,
			TTSPitch:           videoOptions.TTSPitch,
			RiskTip:            strings.TrimSpace(os.Getenv("BAIDU_XILING_OFFLINE_RISK_TIP")),
			Transparent:        videoOptions.Transparent,
			BackgroundImageURL: videoOptions.BackgroundImageURL,
			AutoAnimoji:        videoOptions.AutoAnimoji,
		},
	}
	go r.runBaiduXilingOfflineVideoJob(runInput)

	writeJSON(w, http.StatusCreated, r.offlineVideoResponse(job))
}

func (r *Router) handleGetOfflineVideo(w http.ResponseWriter, req *http.Request) {
	job, jobDir, err := r.readOfflineVideoJob(req.PathValue("id"), req.PathValue("job_id"))
	if err != nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, r.offlineVideoResponseWithDir(job, jobDir))
}

func (r *Router) handleUpdateOfflineVideo(w http.ResponseWriter, req *http.Request) {
	var input updateOfflineVideoRequest
	if err := json.NewDecoder(req.Body).Decode(&input); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "invalid request body"})
		return
	}
	title := strings.TrimSpace(input.Title)
	if title == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "title is required"})
		return
	}
	if len([]rune(title)) > 120 {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "title must be 120 characters or fewer"})
		return
	}

	var updated *offlineVideoJob
	if err := r.updateOfflineVideoJob(req.PathValue("id"), req.PathValue("job_id"), func(job *offlineVideoJob) {
		job.Title = title
		updated = job
	}); err != nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, r.offlineVideoResponse(updated))
}

func (r *Router) handleGetOfflineVideoFile(w http.ResponseWriter, req *http.Request) {
	job, jobDir, err := r.readOfflineVideoJob(req.PathValue("id"), req.PathValue("job_id"))
	if err != nil || job.VideoFilename == "" || job.Status != "completed" {
		http.NotFound(w, req)
		return
	}
	videoPath := filepath.Join(jobDir, filepath.Base(job.VideoFilename))
	if _, err := os.Stat(videoPath); err != nil {
		http.NotFound(w, req)
		return
	}
	if contentType := mime.TypeByExtension(filepath.Ext(videoPath)); contentType != "" {
		w.Header().Set("Content-Type", contentType)
	} else {
		w.Header().Set("Content-Type", "application/octet-stream")
	}
	http.ServeFile(w, req, videoPath)
}

func (r *Router) handleDeleteOfflineVideo(w http.ResponseWriter, req *http.Request) {
	job, jobDir, err := r.readOfflineVideoJob(req.PathValue("id"), req.PathValue("job_id"))
	if err != nil {
		writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		return
	}
	if job.Status == "queued" || job.Status == "running" {
		writeJSON(w, http.StatusConflict, ErrorResponse{Error: "cannot delete an active offline video job"})
		return
	}
	if err := os.RemoveAll(jobDir); err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (r *Router) runOfflineVideoJob(in offlineVideoRunInput) {
	update := func(stage string, progress int, message string) {
		_ = r.updateOfflineVideoJob(in.CharacterID, in.JobID, func(job *offlineVideoJob) {
			job.Status = "running"
			job.Stage = stage
			job.Progress = progress
			job.Message = message
		})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Minute)
	defer cancel()
	crf := 23
	if r.cfg != nil {
		crf = r.cfg.Recording.CRF
	}

	update("starting", 3, "Starting offline generation")
	result, err := r.orch.GenerateOfflineVideo(ctx, orchestrator.OfflineVideoGenerateInput{
		JobID:       in.JobID,
		CharacterID: in.CharacterID,
		ImageData:   in.ImageData,
		ImageFormat: in.ImageFormat,
		Text:        in.Text,
		Audio:       in.Audio,
		TTSConfig:   in.TTSConfig,
		OutputPath:  in.OutputPath,
		CRF:         crf,
		OnProgress:  update,
	})
	if err != nil {
		_ = r.updateOfflineVideoJob(in.CharacterID, in.JobID, func(job *offlineVideoJob) {
			job.Status = "failed"
			job.Stage = "failed"
			job.Message = "Offline generation failed"
			job.Error = err.Error()
			job.FinishedAt = time.Now().UTC().Format(time.RFC3339)
		})
		return
	}
	_ = r.updateOfflineVideoJob(in.CharacterID, in.JobID, func(job *offlineVideoJob) {
		job.Status = "completed"
		job.Stage = "completed"
		job.Message = "Offline video is ready"
		job.Progress = 100
		job.VideoFilename = filepath.Base(result.VideoPath)
		job.Width = result.Width
		job.Height = result.Height
		job.FPS = result.FPS
		job.FrameCount = result.FrameCount
		job.AudioSampleRate = result.AudioSampleRate
		job.FinishedAt = time.Now().UTC().Format(time.RFC3339)
	})
}

func (r *Router) runBaiduXilingOfflineVideoJob(in baiduXilingOfflineVideoRunInput) {
	update := func(stage string, progress int, message string) {
		_ = r.updateOfflineVideoJob(in.CharacterID, in.JobID, func(job *offlineVideoJob) {
			job.Status = "running"
			job.Stage = stage
			job.Progress = progress
			job.Message = message
		})
	}
	fail := func(stage string, err error) {
		_ = r.updateOfflineVideoJob(in.CharacterID, in.JobID, func(job *offlineVideoJob) {
			job.Status = "failed"
			job.Stage = stage
			job.Message = "Baidu Xiling offline video generation failed"
			job.Error = err.Error()
			job.FinishedAt = time.Now().UTC().Format(time.RFC3339)
		})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Minute)
	defer cancel()

	client := baiduXilingAdvancedVideoClient{
		APIBase: strings.TrimSpace(os.Getenv("BAIDU_XILING_API_BASE")),
		AppID:   strings.TrimSpace(os.Getenv("BAIDU_XILING_APP_ID")),
		AppKey:  strings.TrimSpace(os.Getenv("BAIDU_XILING_APP_KEY")),
	}
	update("submit", 28, "Submitting Baidu Xiling synthesis task")
	submission, err := client.submit(ctx, in.BaiduVideoInput)
	if err != nil {
		fail("submit", err)
		return
	}
	_ = r.updateOfflineVideoJob(in.CharacterID, in.JobID, func(job *offlineVideoJob) {
		job.BaiduTaskID = submission.TaskID
		job.Message = "Baidu Xiling task submitted"
		job.Progress = 35
	})

	var task baiduXilingAdvancedVideoTask
	pollCount := 0
	for {
		task, err = client.queryTask(ctx, submission.TaskID, submission.Advanced)
		if err != nil {
			fail("polling", err)
			return
		}
		switch strings.ToUpper(task.Status) {
		case "SUCCESS":
			if task.VideoURL == "" {
				fail("download", errors.New("Baidu Xiling task completed without videoUrl"))
				return
			}
			update("download", 92, "Downloading Baidu Xiling video")
			if err := downloadOfflineVideo(ctx, task.VideoURL, in.OutputPath); err != nil {
				fail("download", err)
				return
			}
			_ = r.updateOfflineVideoJob(in.CharacterID, in.JobID, func(job *offlineVideoJob) {
				job.Status = "completed"
				job.Stage = "completed"
				job.Message = "Offline video is ready"
				job.Progress = 100
				job.VideoFilename = filepath.Base(in.OutputPath)
				job.RemoteVideoURL = task.VideoURL
				job.DurationMS = task.DurationMS
				job.Width = in.Width
				job.Height = in.Height
				job.FinishedAt = time.Now().UTC().Format(time.RFC3339)
			})
			return
		case "FAILED":
			message := task.FailedMessage
			if message == "" {
				message = fmt.Sprintf("Baidu Xiling task failed with code %d", task.FailedCode)
			}
			fail("failed", errors.New(message))
			return
		default:
			pollCount++
			progress := minInt(88, 35+pollCount*3)
			update("polling", progress, "Waiting for Baidu Xiling synthesis")
		}

		timer := time.NewTimer(5 * time.Second)
		select {
		case <-ctx.Done():
			timer.Stop()
			fail("timeout", ctx.Err())
			return
		case <-timer.C:
		}
	}
}

func (r *Router) offlineVideoRoot(characterID string) (string, error) {
	if r.charStore == nil {
		return "", errors.New("character store is disabled")
	}
	dir := r.charStore.CharDir(characterID)
	if dir == "" {
		return "", fmt.Errorf("character not found: %s", characterID)
	}
	root := filepath.Join(dir, offlineVideoRootName)
	if err := os.MkdirAll(root, 0755); err != nil {
		return "", err
	}
	return root, nil
}

func (r *Router) offlineVideoAvatarImage(ch *character.Character) ([]byte, string, error) {
	if ch == nil {
		return nil, "", errors.New("character is required")
	}
	filename := strings.TrimSpace(ch.ActiveImage)
	if filename == "" && len(ch.Images) > 0 {
		filename = ch.Images[0].Filename
	}
	if filename == "" || filename != filepath.Base(filename) || strings.Contains(filename, "..") {
		return nil, "", errors.New("local character has no active avatar image")
	}
	imagePath := filepath.Join(r.charStore.ImagesDir(ch.ID), filename)
	data, err := os.ReadFile(imagePath)
	if err != nil {
		return nil, "", fmt.Errorf("read avatar image: %w", err)
	}
	format := strings.TrimPrefix(strings.ToLower(filepath.Ext(filename)), ".")
	if format == "jpeg" {
		format = "jpg"
	}
	if format == "" {
		format = "png"
	}
	return data, format, nil
}

func (r *Router) offlineVideoTTSConfig(req *http.Request, ch *character.Character, inputType string, sessionID string) (inference.TTSConfig, error) {
	if inputType != "text" {
		return inference.TTSConfig{SessionID: sessionID}, nil
	}
	provider := ""
	model := ""
	voice := ""
	provider = strings.TrimSpace(req.FormValue("tts_provider"))
	model = strings.TrimSpace(req.FormValue("tts_model"))
	voice = strings.TrimSpace(req.FormValue("tts_voice"))
	if provider == "" && model == "" && voice == "" && ch != nil && ch.OfflineVideoTTS != nil {
		provider = strings.TrimSpace(ch.OfflineVideoTTS.Provider)
		model = strings.TrimSpace(ch.OfflineVideoTTS.Model)
		voice = strings.TrimSpace(ch.OfflineVideoTTS.Voice)
	}
	if provider == "" {
		provider = r.pipelineDefault("tts")
	}
	if !r.configuredTTSProvider(provider) {
		return inference.TTSConfig{}, fmt.Errorf("unsupported tts provider: %s", provider)
	}
	if voice == "" {
		voice = r.configuredTTSVoice(provider)
	}
	return inference.TTSConfig{
		Provider:  provider,
		Model:     model,
		Voice:     voice,
		SessionID: sessionID,
	}, nil
}

func baiduXilingOfflineTemplateID() string {
	if value := strings.TrimSpace(os.Getenv("BAIDU_XILING_OFFLINE_TEMPLATE_ID")); value != "" {
		return value
	}
	return strings.TrimSpace(os.Getenv("BAIDU_XILING_TEMPLATE_ID"))
}

func baiduXilingOfflineResolution(ch *character.Character) (int, int) {
	width := parsePositiveInt(os.Getenv("BAIDU_XILING_OFFLINE_WIDTH"), 0, 1920)
	height := parsePositiveInt(os.Getenv("BAIDU_XILING_OFFLINE_HEIGHT"), 0, 1920)
	if width > 0 && height > 0 {
		return width, height
	}
	if ch != nil && ch.BaiduXiling != nil && ch.BaiduXiling.Width > 0 && ch.BaiduXiling.Height > 0 {
		return ch.BaiduXiling.Width, ch.BaiduXiling.Height
	}
	return 1080, 1920
}

func baiduXilingOfflineVideoOptionsFromRequest(req *http.Request, ch *character.Character) baiduXilingOfflineVideoOptions {
	defaultWidth, defaultHeight := baiduXilingOfflineResolution(ch)
	width := parsePositiveInt(strings.TrimSpace(req.FormValue("width")), defaultWidth, 3840)
	height := parsePositiveInt(strings.TrimSpace(req.FormValue("height")), defaultHeight, 3840)
	transparentDefault := parseOfflineVideoBool(os.Getenv("BAIDU_XILING_OFFLINE_TRANSPARENT"), false)
	options := baiduXilingOfflineVideoOptions{
		Width:              width,
		Height:             height,
		Transparent:        parseOfflineVideoBool(req.FormValue("transparent"), transparentDefault),
		TTSPerson:          defaultString(req.FormValue("tts_person"), os.Getenv("BAIDU_XILING_OFFLINE_TTS_PERSON")),
		TTSLan:             defaultString(defaultString(req.FormValue("tts_lan"), os.Getenv("BAIDU_XILING_OFFLINE_TTS_LAN")), "auto"),
		TTSSpeed:           offlineVideoTTSNumber(req.FormValue("tts_speed"), os.Getenv("BAIDU_XILING_OFFLINE_TTS_SPEED")),
		TTSVolume:          offlineVideoTTSNumber(req.FormValue("tts_volume"), os.Getenv("BAIDU_XILING_OFFLINE_TTS_VOLUME")),
		TTSPitch:           offlineVideoTTSNumber(req.FormValue("tts_pitch"), os.Getenv("BAIDU_XILING_OFFLINE_TTS_PITCH")),
		BackgroundImageURL: defaultString(req.FormValue("background_image_url"), os.Getenv("BAIDU_XILING_OFFLINE_BACKGROUND_IMAGE_URL")),
		AutoAnimoji: parseOfflineVideoBool(
			req.FormValue("auto_animoji"),
			parseOfflineVideoBool(os.Getenv("BAIDU_XILING_OFFLINE_AUTO_ANIMOJI"), false),
		),
	}
	return options
}

func baiduXilingOfflineOutputFilename(transparent bool) string {
	if transparent {
		return "output.webm"
	}
	return "output.mp4"
}

func parseOfflineVideoBool(raw string, fallback bool) bool {
	value := strings.TrimSpace(strings.ToLower(raw))
	if value == "" {
		return fallback
	}
	switch value {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}

func offlineVideoTTSNumber(raw, envRaw string) string {
	value := strings.TrimSpace(raw)
	if value == "" {
		value = strings.TrimSpace(envRaw)
	}
	n, err := strconv.Atoi(value)
	if err != nil {
		n = 5
	}
	if n < 0 {
		n = 0
	}
	if n > 15 {
		n = 15
	}
	return strconv.Itoa(n)
}

func baiduXilingInputAudioURLFromRequest(req *http.Request) (string, error) {
	if req == nil {
		return "", errors.New("Baidu Xiling inputAudioUrl is required for VOICE driveType")
	}
	inputAudioURL := strings.TrimSpace(req.FormValue("input_audio_url"))
	if inputAudioURL == "" {
		inputAudioURL = strings.TrimSpace(req.FormValue("inputAudioUrl"))
	}
	if inputAudioURL == "" {
		return "", errors.New("Baidu Xiling inputAudioUrl is required for VOICE driveType")
	}
	parsed, err := url.Parse(inputAudioURL)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" || strings.ContainsAny(inputAudioURL, " \t\r\n") {
		return "", errors.New("Baidu Xiling inputAudioUrl must be a valid absolute URL")
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", errors.New("Baidu Xiling inputAudioUrl must use http or https")
	}
	return inputAudioURL, nil
}

func (r *Router) readOfflineVideoJob(characterID, jobID string) (*offlineVideoJob, string, error) {
	if jobID == "" || jobID != filepath.Base(jobID) || strings.Contains(jobID, "..") {
		return nil, "", errors.New("invalid offline video job id")
	}
	root, err := r.offlineVideoRoot(characterID)
	if err != nil {
		return nil, "", err
	}
	jobDir := filepath.Join(root, jobID)
	job, err := readOfflineVideoJobFile(jobDir)
	if err != nil {
		return nil, "", err
	}
	if job.CharacterID != characterID {
		return nil, "", errors.New("offline video job does not belong to this character")
	}
	return job, jobDir, nil
}

func (r *Router) listOfflineVideoJobs(characterID string) ([]offlineVideoJobResponse, error) {
	root, err := r.offlineVideoRoot(characterID)
	if err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}
	jobs := make([]offlineVideoJobResponse, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		jobDir := filepath.Join(root, entry.Name())
		job, err := readOfflineVideoJobFile(jobDir)
		if err != nil || job.CharacterID != characterID {
			continue
		}
		jobs = append(jobs, r.offlineVideoResponseWithDir(job, jobDir))
	}
	sort.Slice(jobs, func(i, j int) bool {
		return jobs[i].CreatedAt > jobs[j].CreatedAt
	})
	return jobs, nil
}

func (r *Router) updateOfflineVideoJob(characterID, jobID string, mutate func(*offlineVideoJob)) error {
	offlineVideoMu.Lock()
	defer offlineVideoMu.Unlock()
	job, jobDir, err := r.readOfflineVideoJob(characterID, jobID)
	if err != nil {
		return err
	}
	mutate(job)
	job.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	return writeOfflineVideoJob(jobDir, job)
}

func (r *Router) offlineVideoResponse(job *offlineVideoJob) offlineVideoJobResponse {
	root, err := r.offlineVideoRoot(job.CharacterID)
	if err != nil {
		return offlineVideoJobResponse{offlineVideoJob: *job}
	}
	return r.offlineVideoResponseWithDir(job, filepath.Join(root, job.ID))
}

func (r *Router) offlineVideoResponseWithDir(job *offlineVideoJob, jobDir string) offlineVideoJobResponse {
	resp := offlineVideoJobResponse{offlineVideoJob: *job}
	if job.Status == "completed" && job.VideoFilename != "" {
		if _, err := os.Stat(filepath.Join(jobDir, filepath.Base(job.VideoFilename))); err == nil {
			resp.VideoURL = fmt.Sprintf("/api/v1/characters/%s/offline-videos/%s/video", job.CharacterID, job.ID)
		}
	}
	return resp
}

func readOfflineVideoJobFile(jobDir string) (*offlineVideoJob, error) {
	data, err := os.ReadFile(filepath.Join(jobDir, "job.json"))
	if err != nil {
		return nil, err
	}
	var job offlineVideoJob
	if err := json.Unmarshal(data, &job); err != nil {
		return nil, err
	}
	return &job, nil
}

func writeOfflineVideoJob(jobDir string, job *offlineVideoJob) error {
	if err := os.MkdirAll(jobDir, 0755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(job, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(jobDir, "job.json"), data, 0644)
}

func defaultOfflineVideoTitle() string {
	return time.Now().Format("2006-01-02 15:04:05")
}

func downloadOfflineVideo(ctx context.Context, remoteURL, outputPath string) error {
	if strings.TrimSpace(remoteURL) == "" {
		return errors.New("remote video URL is required")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, remoteURL, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("download offline video failed: HTTP %d", resp.StatusCode)
	}
	if err := os.MkdirAll(filepath.Dir(outputPath), 0755); err != nil {
		return err
	}
	tmpPath := outputPath + ".tmp"
	out, err := os.Create(tmpPath)
	if err != nil {
		return err
	}
	const maxVideoBytes = int64(2 << 30)
	written, copyErr := io.Copy(out, io.LimitReader(resp.Body, maxVideoBytes+1))
	closeErr := out.Close()
	if copyErr != nil {
		_ = os.Remove(tmpPath)
		return copyErr
	}
	if closeErr != nil {
		_ = os.Remove(tmpPath)
		return closeErr
	}
	if written > maxVideoBytes {
		_ = os.Remove(tmpPath)
		return errors.New("downloaded video exceeds 2GB")
	}
	return os.Rename(tmpPath, outputPath)
}

func readOfflineVideoAudio(req *http.Request, jobDir string) (*orchestrator.OfflineAudioInput, error) {
	file, header, err := req.FormFile("audio")
	if err != nil {
		return nil, errors.New("audio file is required")
	}
	defer file.Close()

	data, err := io.ReadAll(file)
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, errors.New("audio file is empty")
	}
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext == "" {
		ext = ".wav"
	}
	_ = os.WriteFile(filepath.Join(jobDir, "input"+ext), data, 0644)

	if isWAV(data) || ext == ".wav" {
		pcm, sampleRate, err := decodePCM16WAV(data)
		if err != nil {
			return nil, err
		}
		return &orchestrator.OfflineAudioInput{PCM16: pcm, SampleRate: sampleRate}, nil
	}
	if ext == ".pcm" || ext == ".s16le" {
		sampleRate := parsePositiveInt(req.FormValue("audio_sample_rate"), 16000, 192000)
		if len(data)%2 != 0 {
			data = data[:len(data)-1]
		}
		return &orchestrator.OfflineAudioInput{PCM16: append([]byte(nil), data...), SampleRate: sampleRate}, nil
	}
	return nil, errors.New("only 16-bit PCM WAV, .pcm, or .s16le audio is supported for offline generation")
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func isWAV(data []byte) bool {
	return len(data) >= 12 && string(data[:4]) == "RIFF" && string(data[8:12]) == "WAVE"
}

func decodePCM16WAV(data []byte) ([]byte, int, error) {
	if !isWAV(data) {
		return nil, 0, errors.New("audio is not a WAV file")
	}
	var channels uint16
	var bitsPerSample uint16
	var audioFormat uint16
	sampleRate := 0
	var pcm []byte

	for off := 12; off+8 <= len(data); {
		chunkID := string(data[off : off+4])
		chunkSize := int(binary.LittleEndian.Uint32(data[off+4 : off+8]))
		chunkStart := off + 8
		chunkEnd := chunkStart + chunkSize
		if chunkSize < 0 || chunkEnd > len(data) {
			return nil, 0, errors.New("invalid WAV chunk size")
		}
		switch chunkID {
		case "fmt ":
			if chunkSize < 16 {
				return nil, 0, errors.New("invalid WAV fmt chunk")
			}
			audioFormat = binary.LittleEndian.Uint16(data[chunkStart : chunkStart+2])
			channels = binary.LittleEndian.Uint16(data[chunkStart+2 : chunkStart+4])
			sampleRate = int(binary.LittleEndian.Uint32(data[chunkStart+4 : chunkStart+8]))
			bitsPerSample = binary.LittleEndian.Uint16(data[chunkStart+14 : chunkStart+16])
		case "data":
			pcm = append([]byte(nil), data[chunkStart:chunkEnd]...)
		}
		off = chunkEnd
		if off%2 == 1 {
			off++
		}
	}
	if audioFormat != 1 {
		return nil, 0, fmt.Errorf("unsupported WAV encoding %d; only PCM is supported", audioFormat)
	}
	if bitsPerSample != 16 {
		return nil, 0, fmt.Errorf("unsupported WAV bit depth %d; only 16-bit PCM is supported", bitsPerSample)
	}
	if sampleRate <= 0 {
		return nil, 0, errors.New("missing WAV sample rate")
	}
	if len(pcm) == 0 {
		return nil, 0, errors.New("missing WAV data chunk")
	}
	if channels == 1 {
		if len(pcm)%2 != 0 {
			pcm = pcm[:len(pcm)-1]
		}
		return pcm, sampleRate, nil
	}
	if channels != 2 {
		return nil, 0, fmt.Errorf("unsupported WAV channel count %d", channels)
	}
	if len(pcm)%4 != 0 {
		pcm = pcm[:len(pcm)-(len(pcm)%4)]
	}
	mono := make([]byte, len(pcm)/2)
	for i, j := 0, 0; i+4 <= len(pcm); i, j = i+4, j+2 {
		l := int16(binary.LittleEndian.Uint16(pcm[i : i+2]))
		r := int16(binary.LittleEndian.Uint16(pcm[i+2 : i+4]))
		m := int16((int(l) + int(r)) / 2)
		binary.LittleEndian.PutUint16(mono[j:j+2], uint16(m))
	}
	return mono, sampleRate, nil
}
