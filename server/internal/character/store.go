package character

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// ImageInfo describes one image file inside a character's images/ directory.
type ImageInfo struct {
	Filename string `json:"filename"`
	OrigName string `json:"orig_name"`
	AddedAt  string `json:"added_at"`
}

type Character struct {
	ID              string           `json:"id"`
	Name            string           `json:"name"`
	Description     string           `json:"description"`
	AvatarImage     string           `json:"avatar_image"`
	AvatarBackend   string           `json:"avatar_backend"`
	BaiduXiling     *BaiduXiling     `json:"baidu_xiling,omitempty"`
	Xunfei          *XunfeiAvatar    `json:"xunfei,omitempty"`
	OfflineVideoTTS *OfflineVideoTTS `json:"offline_video_tts,omitempty"`
	UseFaceCrop     bool             `json:"use_face_crop"`
	Mode            string           `json:"mode"`
	VoiceProvider   string           `json:"voice_provider"`
	VoiceType       string           `json:"voice_type"`
	Components      Components       `json:"components"`
	SpeakingStyle   string           `json:"speaking_style"`
	Personality     string           `json:"personality"`
	WelcomeMessage  string           `json:"welcome_message"`
	SystemPrompt    string           `json:"system_prompt"`
	Tags            []string         `json:"tags"`
	Images          []ImageInfo      `json:"images"`
	AgentExtensions []AgentExtension `json:"agent_extensions,omitempty"`
	ActiveImage     string           `json:"active_image"`
	ImageMode       string           `json:"image_mode"`
	CreatedAt       string           `json:"created_at"`
	UpdatedAt       string           `json:"updated_at"`
}

type AgentExtension struct {
	Name    string `json:"name,omitempty"`
	URL     string `json:"url"`
	Enabled bool   `json:"enabled"`
}

type Components struct {
	LLM      string `json:"llm"`
	ASR      string `json:"asr"`
	TTS      string `json:"tts"`
	TTSModel string `json:"tts_model,omitempty"`
}

type OfflineVideoTTS struct {
	Provider string `json:"provider"`
	Model    string `json:"model,omitempty"`
	Voice    string `json:"voice"`
}

type BaiduXiling struct {
	FigureID        string `json:"figure_id"`
	FigureName      string `json:"figure_name"`
	CameraID        string `json:"camera_id,omitempty"`
	ThumbnailURL    string `json:"thumbnail_url"`
	PreviewVideoURL string `json:"preview_video_url"`
	SourceImageURL  string `json:"source_image_url"`
	Status          string `json:"status"`
	Width           int    `json:"width"`
	Height          int    `json:"height"`
}

type XunfeiAvatar struct {
	AvatarID        string `json:"avatar_id"`
	AvatarName      string `json:"avatar_name,omitempty"`
	SceneID         string `json:"scene_id,omitempty"`
	VCN             string `json:"vcn"`
	ThumbnailURL    string `json:"thumbnail_url,omitempty"`
	PreviewVideoURL string `json:"preview_video_url,omitempty"`
	SourceImageURL  string `json:"source_image_url,omitempty"`
	Status          string `json:"status,omitempty"`
	Protocol        string `json:"protocol,omitempty"`
	Width           int    `json:"width,omitempty"`
	Height          int    `json:"height,omitempty"`
	FPS             int    `json:"fps,omitempty"`
	Bitrate         int    `json:"bitrate,omitempty"`
	Speed           int    `json:"speed,omitempty"`
	Pitch           int    `json:"pitch,omitempty"`
	Volume          int    `json:"volume,omitempty"`
	Air             int    `json:"air,omitempty"`
}

const DefaultIdleVideoProfile = "breathing10s_v1"
const AvatarBackendLocalImage = "local_image"
const AvatarBackendBaiduXiling = "baidu_xiling"
const AvatarBackendXunfei = "xunfei"
const AvatarBackendVidu = "vidu"

func DefaultComponents() Components {
	return Components{LLM: "qwen", ASR: "qwen", TTS: "qwen"}
}

func normalizeMode(mode string, fallback string) string {
	switch strings.TrimSpace(mode) {
	case "omni", "voice_llm":
		return "omni"
	case "standard":
		return "standard"
	default:
		if fallback != "" {
			return fallback
		}
		return "standard"
	}
}

func NormalizeComponents(components Components, defaults Components) Components {
	if defaults.LLM == "" {
		defaults.LLM = "qwen"
	}
	if defaults.ASR == "" {
		defaults.ASR = "qwen"
	}
	if defaults.TTS == "" {
		defaults.TTS = "qwen"
	}
	if components.LLM == "" {
		components.LLM = defaults.LLM
	}
	if components.ASR == "" {
		components.ASR = defaults.ASR
	}
	if components.TTS == "" {
		components.TTS = defaults.TTS
	}
	components.TTSModel = strings.TrimSpace(components.TTSModel)
	if components.TTSModel == "" && components.TTS == defaults.TTS {
		components.TTSModel = strings.TrimSpace(defaults.TTSModel)
	}
	return components
}

func normalizeAvatarBackend(backend string) string {
	switch strings.TrimSpace(backend) {
	case AvatarBackendBaiduXiling:
		return AvatarBackendBaiduXiling
	case AvatarBackendXunfei:
		return AvatarBackendXunfei
	case AvatarBackendVidu:
		return AvatarBackendVidu
	default:
		return AvatarBackendLocalImage
	}
}

func normalizeBaiduXilingConfig(cfg *BaiduXiling) *BaiduXiling {
	if cfg == nil {
		return nil
	}
	out := *cfg
	out.FigureID = strings.TrimSpace(out.FigureID)
	out.FigureName = strings.TrimSpace(out.FigureName)
	out.CameraID = strings.TrimSpace(out.CameraID)
	out.ThumbnailURL = strings.TrimSpace(out.ThumbnailURL)
	out.PreviewVideoURL = strings.TrimSpace(out.PreviewVideoURL)
	out.SourceImageURL = strings.TrimSpace(out.SourceImageURL)
	out.Status = strings.TrimSpace(out.Status)
	if out.Width < 0 {
		out.Width = 0
	}
	if out.Height < 0 {
		out.Height = 0
	}
	return &out
}

func clampXunfeiRange(value, fallback, minValue, maxValue int) int {
	if value == 0 {
		return fallback
	}
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}

func normalizeXunfeiConfig(cfg *XunfeiAvatar) *XunfeiAvatar {
	if cfg == nil {
		return nil
	}
	out := *cfg
	out.AvatarID = strings.TrimSpace(out.AvatarID)
	out.AvatarName = strings.TrimSpace(out.AvatarName)
	out.SceneID = strings.TrimSpace(out.SceneID)
	out.VCN = strings.TrimSpace(out.VCN)
	out.ThumbnailURL = strings.TrimSpace(out.ThumbnailURL)
	out.PreviewVideoURL = strings.TrimSpace(out.PreviewVideoURL)
	out.SourceImageURL = strings.TrimSpace(out.SourceImageURL)
	out.Status = strings.TrimSpace(out.Status)
	switch strings.TrimSpace(strings.ToLower(out.Protocol)) {
	case "xrtc", "rtmp", "webrtc", "flv":
		out.Protocol = strings.TrimSpace(strings.ToLower(out.Protocol))
	default:
		out.Protocol = "flv"
	}
	if out.Width == 0 {
		out.Width = 720
	}
	if out.Height == 0 {
		out.Height = 1280
	}
	if out.Width < 300 {
		out.Width = 300
	}
	if out.Height < 300 {
		out.Height = 300
	}
	if out.Width > 4096 {
		out.Width = 4096
	}
	if out.Height > 4096 {
		out.Height = 4096
	}
	if rem := out.Width % 4; rem != 0 {
		out.Width -= rem
	}
	if rem := out.Height % 4; rem != 0 {
		out.Height -= rem
	}
	out.FPS = clampXunfeiRange(out.FPS, 25, 13, 25)
	out.Bitrate = clampXunfeiRange(out.Bitrate, 2000, 200, 20000)
	out.Speed = clampXunfeiRange(out.Speed, 50, 0, 100)
	out.Pitch = clampXunfeiRange(out.Pitch, 50, 0, 100)
	out.Volume = clampXunfeiRange(out.Volume, 50, 0, 100)
	if out.Air != 1 {
		out.Air = 0
	}
	return &out
}

func NormalizeXunfeiAvatarConfig(cfg *XunfeiAvatar) *XunfeiAvatar {
	return normalizeXunfeiConfig(cfg)
}

func NormalizeOfflineVideoTTS(cfg *OfflineVideoTTS) *OfflineVideoTTS {
	if cfg == nil {
		return nil
	}
	out := *cfg
	out.Provider = strings.TrimSpace(out.Provider)
	out.Model = strings.TrimSpace(out.Model)
	out.Voice = strings.TrimSpace(out.Voice)
	if out.Provider == "" && out.Model == "" && out.Voice == "" {
		return nil
	}
	return &out
}

func NormalizeAgentExtensions(extensions []AgentExtension) []AgentExtension {
	if extensions == nil {
		return nil
	}
	out := make([]AgentExtension, 0, len(extensions))
	for _, ext := range extensions {
		normalized := AgentExtension{
			Name:    strings.TrimSpace(ext.Name),
			URL:     strings.TrimSpace(ext.URL),
			Enabled: ext.Enabled,
		}
		if normalized.URL == "" {
			continue
		}
		out = append(out, normalized)
	}
	if out == nil {
		return []AgentExtension{}
	}
	return out
}

func defaultVoiceTypeForComponents(components Components) string {
	if components.TTS == "doubao" {
		return "zh_female_xiaohe_uranus_bigtts"
	}
	if components.TTS != "qwen" {
		return ""
	}
	model := strings.ToLower(strings.TrimSpace(components.TTSModel))
	switch {
	case strings.HasPrefix(model, "cosyvoice-v3.5-"):
		return ""
	case strings.HasPrefix(model, "cosyvoice-v3-"):
		return "longanyang"
	default:
		return "Momo"
	}
}

func normalizeAvatarFields(c *Character, fallback *Character) {
	c.AvatarBackend = normalizeAvatarBackend(c.AvatarBackend)
	if c.AvatarBackend == AvatarBackendBaiduXiling {
		c.BaiduXiling = normalizeBaiduXilingConfig(c.BaiduXiling)
		if c.BaiduXiling == nil && fallback != nil && fallback.AvatarBackend == AvatarBackendBaiduXiling {
			c.BaiduXiling = normalizeBaiduXilingConfig(fallback.BaiduXiling)
		}
		c.Xunfei = nil
		return
	}
	if c.AvatarBackend == AvatarBackendXunfei {
		c.Xunfei = normalizeXunfeiConfig(c.Xunfei)
		if c.Xunfei == nil && fallback != nil && fallback.AvatarBackend == AvatarBackendXunfei {
			c.Xunfei = normalizeXunfeiConfig(fallback.Xunfei)
		}
		c.BaiduXiling = nil
		return
	}
	if c.AvatarBackend == AvatarBackendVidu {
		c.BaiduXiling = nil
		c.Xunfei = nil
		return
	}
	c.BaiduXiling = nil
	c.Xunfei = nil
}

type Store struct {
	mu      sync.RWMutex
	baseDir string
	chars   map[string]*Character
	// dirNames caches id to directory name, for example "char_8981e0a1".
	dirNames map[string]string
}

// NewStore creates a store backed by per-character directories under baseDir.
func NewStore(baseDir string) (*Store, error) {
	s := &Store{
		baseDir:  baseDir,
		chars:    make(map[string]*Character),
		dirNames: make(map[string]string),
	}
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("create characters dir: %w", err)
	}
	if err := s.load(); err != nil {
		return nil, fmt.Errorf("load characters: %w", err)
	}
	return s, nil
}

func (s *Store) BaseDir() string {
	return s.baseDir
}

func (s *Store) List() []*Character {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]*Character, 0, len(s.chars))
	for _, c := range s.chars {
		result = append(result, c)
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].CreatedAt < result[j].CreatedAt
	})
	return result
}

func (s *Store) Get(id string) (*Character, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	c, ok := s.chars[id]
	if !ok {
		return nil, fmt.Errorf("character not found: %s", id)
	}
	return c, nil
}

func (s *Store) Create(c *Character) (*Character, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	c.ID = uuid.New().String()
	now := time.Now().UTC().Format(time.RFC3339)
	c.CreatedAt = now
	c.UpdatedAt = now
	if c.Tags == nil {
		c.Tags = []string{}
	}
	if c.Images == nil {
		c.Images = []ImageInfo{}
	}
	c.AgentExtensions = NormalizeAgentExtensions(c.AgentExtensions)
	c.Mode = normalizeMode(c.Mode, "standard")
	c.Components = NormalizeComponents(c.Components, DefaultComponents())
	c.OfflineVideoTTS = NormalizeOfflineVideoTTS(c.OfflineVideoTTS)
	normalizeAvatarFields(c, nil)
	if c.VoiceProvider == "" {
		c.VoiceProvider = c.Components.TTS
	}
	if c.VoiceType == "" {
		c.VoiceType = defaultVoiceTypeForComponents(c.Components)
	}

	dirName := charDirName(c.Name, c.ID)
	charDir := filepath.Join(s.baseDir, dirName)

	// Create directory structure
	for _, sub := range []string{"", "images", "sessions"} {
		if err := os.MkdirAll(filepath.Join(charDir, sub), 0755); err != nil {
			return nil, fmt.Errorf("create character dir: %w", err)
		}
	}

	s.chars[c.ID] = c
	s.dirNames[c.ID] = dirName

	if err := s.saveOne(c); err != nil {
		// Cleanup on failure
		os.RemoveAll(charDir)
		delete(s.chars, c.ID)
		delete(s.dirNames, c.ID)
		return nil, err
	}
	return c, nil
}

func (s *Store) Update(id string, c *Character) (*Character, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	existing, ok := s.chars[id]
	if !ok {
		return nil, fmt.Errorf("character not found: %s", id)
	}

	oldDirName := s.dirNames[id]

	c.ID = id
	c.CreatedAt = existing.CreatedAt
	c.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	if c.Tags == nil {
		c.Tags = []string{}
	}
	// Preserve images/active_image from existing if not provided
	if c.Images == nil {
		c.Images = existing.Images
	}
	if c.ActiveImage == "" {
		c.ActiveImage = existing.ActiveImage
	}
	if c.ImageMode == "" {
		c.ImageMode = existing.ImageMode
	}
	if c.AgentExtensions == nil {
		c.AgentExtensions = NormalizeAgentExtensions(existing.AgentExtensions)
	} else {
		c.AgentExtensions = NormalizeAgentExtensions(c.AgentExtensions)
	}
	normalizeAvatarFields(c, existing)
	if c.OfflineVideoTTS == nil {
		c.OfflineVideoTTS = NormalizeOfflineVideoTTS(existing.OfflineVideoTTS)
	} else {
		c.OfflineVideoTTS = NormalizeOfflineVideoTTS(c.OfflineVideoTTS)
	}
	c.Mode = normalizeMode(c.Mode, normalizeMode(existing.Mode, "standard"))
	c.Components = NormalizeComponents(c.Components, existing.Components)
	if c.VoiceProvider == "" {
		c.VoiceProvider = c.Components.TTS
	}
	if c.VoiceType == "" {
		c.VoiceType = defaultVoiceTypeForComponents(c.Components)
	}
	// Preserve avatar_image if caller sent empty (e.g. frontend strips blob: URLs)
	if c.AvatarImage == "" && existing.AvatarImage != "" {
		c.AvatarImage = existing.AvatarImage
	}

	newDirName := charDirName(c.Name, c.ID)

	// Rename directory if name changed
	if oldDirName != newDirName {
		oldPath := filepath.Join(s.baseDir, oldDirName)
		newPath := filepath.Join(s.baseDir, newDirName)
		if err := os.Rename(oldPath, newPath); err != nil {
			return nil, fmt.Errorf("rename character dir: %w", err)
		}
		s.dirNames[id] = newDirName
	}

	s.chars[id] = c
	if err := s.saveOne(c); err != nil {
		return nil, err
	}
	return c, nil
}

func (s *Store) UpdateOfflineVideoTTS(id string, cfg *OfflineVideoTTS) (*Character, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	c, ok := s.chars[id]
	if !ok {
		return nil, fmt.Errorf("character not found: %s", id)
	}
	c.OfflineVideoTTS = NormalizeOfflineVideoTTS(cfg)
	c.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	if err := s.saveOne(c); err != nil {
		return nil, err
	}
	return c, nil
}

func (s *Store) Delete(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.chars[id]; !ok {
		return fmt.Errorf("character not found: %s", id)
	}

	dirName := s.dirNames[id]
	if dirName != "" {
		os.RemoveAll(filepath.Join(s.baseDir, dirName))
	}

	delete(s.chars, id)
	delete(s.dirNames, id)
	return nil
}

// CharDir returns the full path to a character's directory.
func (s *Store) CharDir(id string) string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	dirName, ok := s.dirNames[id]
	if !ok {
		return ""
	}
	return filepath.Join(s.baseDir, dirName)
}

// ImagesDir returns the full path to a character's images directory.
func (s *Store) ImagesDir(id string) string {
	d := s.CharDir(id)
	if d == "" {
		return ""
	}
	return filepath.Join(d, "images")
}

// SessionsDir returns the full path to a character's sessions directory.
func (s *Store) SessionsDir(id string) string {
	d := s.CharDir(id)
	if d == "" {
		return ""
	}
	return filepath.Join(d, "sessions")
}

func (s *Store) UserSessionsDir(id, ownerID string) string {
	return s.sessionsDirForOwner(id, ownerID)
}

func (s *Store) sessionsDirForOwner(id, ownerID string) string {
	ownerID = strings.TrimSpace(ownerID)
	if ownerID == "" {
		return s.SessionsDir(id)
	}
	d := s.CharDir(id)
	if d == "" {
		return ""
	}
	return filepath.Join(d, "users", ownerDirName(ownerID), "sessions")
}

// IdleVideosDir returns the full path to a character's idle video cache directory.
func (s *Store) IdleVideosDir(id string) string {
	d := s.CharDir(id)
	if d == "" {
		return ""
	}
	return filepath.Join(d, "idle_videos")
}

// IdleVideosForImageDir returns the per-image subdirectory under idle_videos/.
// e.g. {charDir}/idle_videos/img_003/
func (s *Store) IdleVideosForImageDir(id, imageFilename string) string {
	dir := s.IdleVideosDir(id)
	if dir == "" {
		return ""
	}
	base := strings.TrimSuffix(filepath.Base(imageFilename), filepath.Ext(imageFilename))
	if base == "" {
		base = "avatar"
	}
	return filepath.Join(dir, base)
}

func idleVideoBaseName(imageFilename string) string {
	base := strings.TrimSuffix(filepath.Base(imageFilename), filepath.Ext(imageFilename))
	if base == "" {
		base = "avatar"
	}
	return base
}

func idleVideoProfileName(profile string) string {
	if profile == "" {
		return DefaultIdleVideoProfile
	}
	return profile
}

func idleVideoSizeDirName(width, height int) string {
	if width <= 0 || height <= 0 {
		return ""
	}
	return fmt.Sprintf("%dx%d", width, height)
}

// IdleVideosForSizeDir returns the per-image, per-resolution cache directory.
// e.g. {charDir}/idle_videos/img_003/320x480/
func (s *Store) IdleVideosForSizeDir(id, imageFilename string, width, height int) string {
	dir := s.IdleVideosForImageDir(id, imageFilename)
	sizeDir := idleVideoSizeDirName(width, height)
	if dir == "" || sizeDir == "" {
		return ""
	}
	return filepath.Join(dir, sizeDir)
}

// IdleVideoFilename returns a stable MP4 filename for one source image + profile.
func (s *Store) IdleVideoFilename(imageFilename, profile string) string {
	return fmt.Sprintf("%s__%s.mp4", idleVideoBaseName(imageFilename), idleVideoProfileName(profile))
}

// IdleVideoPath returns the absolute path for a cached idle video inside the
// per-image, per-resolution subdirectory.
func (s *Store) IdleVideoPath(id, imageFilename, profile string, width, height int) string {
	dir := s.IdleVideosForSizeDir(id, imageFilename, width, height)
	if dir == "" {
		return ""
	}
	return filepath.Join(dir, s.IdleVideoFilename(imageFilename, profile))
}

// ListIdleVideos returns all .mp4 filenames in the target resolution directory, sorted.
func (s *Store) ListIdleVideos(id, imageFilename string, width, height int) ([]string, error) {
	dir := s.IdleVideosForSizeDir(id, imageFilename, width, height)
	if dir == "" {
		return nil, fmt.Errorf("idle video dir unavailable for character %s", id)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(strings.ToLower(e.Name()), ".mp4") {
			files = append(files, e.Name())
		}
	}
	sort.Strings(files)
	return files, nil
}

// NextImageFilename scans the images/ directory and returns the next sequential filename
// (without extension), e.g. "img_003".
func (s *Store) NextImageFilename(id string) string {
	imgDir := s.ImagesDir(id)
	if imgDir == "" {
		return "img_001"
	}

	entries, err := os.ReadDir(imgDir)
	if err != nil {
		return "img_001"
	}

	maxNum := 0
	re := regexp.MustCompile(`^img_(\d+)`)
	for _, e := range entries {
		if m := re.FindStringSubmatch(e.Name()); m != nil {
			if n, err := strconv.Atoi(m[1]); err == nil && n > maxNum {
				maxNum = n
			}
		}
	}
	return fmt.Sprintf("img_%03d", maxNum+1)
}

// SaveConversation persists a session's data (messages + metadata) into the character's sessions dir.
func (s *Store) SaveConversation(characterID, sessionID string, startedAt, endedAt time.Time, messages []map[string]any) error {
	return s.SaveConversationForOwner(characterID, "", sessionID, startedAt, endedAt, messages)
}

func (s *Store) SaveConversationForOwner(characterID, ownerID, sessionID string, startedAt, endedAt time.Time, messages []map[string]any) error {
	sessDir := s.sessionsDirForOwner(characterID, ownerID)
	if sessDir == "" {
		return fmt.Errorf("character not found: %s", characterID)
	}

	dirName := startedAt.Format("20060102-150405") + "_" + shortID(sessionID)
	fullDir := filepath.Join(sessDir, dirName)
	if err := os.MkdirAll(fullDir, 0755); err != nil {
		return err
	}

	record := map[string]any{
		"session_id":   sessionID,
		"character_id": characterID,
		"started_at":   startedAt.UTC().Format(time.RFC3339),
		"ended_at":     endedAt.UTC().Format(time.RFC3339),
		"messages":     messages,
	}

	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(fullDir, "session.json"), data, 0644)
}

// LoadRecentMessages loads recent conversation messages for a character, paginated by cursor.
// before: cursor (session directory name) — empty string means start from newest.
// limit: max number of messages to return.
// Returns: messages (chronological order), next cursor, hasMore.
func (s *Store) LoadRecentMessages(characterID string, before string, limit int) ([]map[string]any, string, bool, error) {
	return s.LoadRecentMessagesForOwner(characterID, "", before, limit)
}

func (s *Store) LoadRecentMessagesForOwner(characterID, ownerID string, before string, limit int) ([]map[string]any, string, bool, error) {
	sessDir := s.sessionsDirForOwner(characterID, ownerID)
	if sessDir == "" {
		return nil, "", false, fmt.Errorf("character not found: %s", characterID)
	}

	entries, err := os.ReadDir(sessDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, "", false, nil
		}
		return nil, "", false, err
	}

	// Sort descending by name (timestamp prefix ensures chronological order)
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Name() > entries[j].Name()
	})

	// Apply cursor: skip entries >= before
	if before != "" {
		idx := 0
		for idx < len(entries) && entries[idx].Name() >= before {
			idx++
		}
		entries = entries[idx:]
	}

	var allMessages []map[string]any
	var nextCursor string
	collected := 0

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		sessionFile := filepath.Join(sessDir, entry.Name(), "session.json")
		data, err := os.ReadFile(sessionFile)
		if err != nil {
			continue // skip sessions without session.json
		}

		var record struct {
			SessionID string           `json:"session_id"`
			StartedAt string           `json:"started_at"`
			Messages  []map[string]any `json:"messages"`
		}
		if err := json.Unmarshal(data, &record); err != nil {
			continue
		}
		if strings.TrimSpace(record.SessionID) == "" {
			record.SessionID = entry.Name()
		}
		if len(record.Messages) == 0 {
			continue
		}

		// Annotate messages with session metadata
		for _, msg := range record.Messages {
			msg["session_id"] = record.SessionID
			if msg["timestamp"] == nil {
				msg["timestamp"] = record.StartedAt
			} else if ts, ok := msg["timestamp"].(string); ok && strings.TrimSpace(ts) == "" {
				msg["timestamp"] = record.StartedAt
			}
		}

		// These messages are in chronological order within the session,
		// but we're iterating sessions newest-first, so prepend
		allMessages = append(record.Messages, allMessages...)
		collected += len(record.Messages)
		nextCursor = entry.Name()

		if collected >= limit {
			break
		}
	}

	// Trim to limit (keep the most recent messages)
	if len(allMessages) > limit {
		allMessages = allMessages[len(allMessages)-limit:]
	}

	// Check if there are more sessions after the cursor
	hasMore := false
	if nextCursor != "" {
		for _, entry := range entries {
			if entry.IsDir() && entry.Name() < nextCursor {
				// Check if this directory has a session.json
				sessionFile := filepath.Join(sessDir, entry.Name(), "session.json")
				if _, err := os.Stat(sessionFile); err == nil {
					hasMore = true
					break
				}
			}
		}
	}

	return allMessages, nextCursor, hasMore, nil
}

// SessionRecordingDir returns the full path for a session's recording directory,
// creating it if needed. Format: {charDir}/sessions/{timestamp}_{sessionID8}/
// Uses createdAt so that recordings land in the same directory as SaveConversation.
func (s *Store) SessionRecordingDir(characterID, sessionID string, createdAt time.Time) string {
	return s.SessionRecordingDirForOwner(characterID, "", sessionID, createdAt)
}

func (s *Store) SessionRecordingDirForOwner(characterID, ownerID, sessionID string, createdAt time.Time) string {
	sessDir := s.sessionsDirForOwner(characterID, ownerID)
	if sessDir == "" {
		return ""
	}
	dirName := createdAt.Format("20060102-150405") + "_" + shortID(sessionID)
	fullDir := filepath.Join(sessDir, dirName)
	// Resolve to absolute path so that recording functions (BeginTurn/SaveRawAudio)
	// don't prepend cfg.OutputDir when they see a relative path.
	if abs, err := filepath.Abs(fullDir); err == nil {
		fullDir = abs
	}
	os.MkdirAll(fullDir, 0755)
	return fullDir
}

// ── internal helpers ──

func (s *Store) load() error {
	entries, err := os.ReadDir(s.baseDir)
	if err != nil {
		return err
	}

	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		jsonPath := filepath.Join(s.baseDir, e.Name(), "character.json")
		data, err := os.ReadFile(jsonPath)
		if err != nil {
			log.Printf("skip character dir %s: %v", e.Name(), err)
			continue
		}
		var c Character
		if err := json.Unmarshal(data, &c); err != nil {
			log.Printf("skip character dir %s: bad JSON: %v", e.Name(), err)
			continue
		}
		if c.ID == "" {
			log.Printf("skip character dir %s: no id", e.Name())
			continue
		}
		if c.Tags == nil {
			c.Tags = []string{}
		}
		if c.Images == nil {
			c.Images = []ImageInfo{}
		}
		c.AgentExtensions = NormalizeAgentExtensions(c.AgentExtensions)
		if c.ImageMode == "" {
			c.ImageMode = "fixed"
		}
		normalizeAvatarFields(&c, nil)
		c.OfflineVideoTTS = NormalizeOfflineVideoTTS(c.OfflineVideoTTS)
		// Legacy character.json files had no mode field; default to omni (prior voice_llm behavior).
		c.Mode = normalizeMode(c.Mode, "omni")
		c.Components = NormalizeComponents(c.Components, DefaultComponents())
		if c.VoiceProvider == "" {
			c.VoiceProvider = c.Components.TTS
		}
		if c.VoiceType == "" {
			c.VoiceType = defaultVoiceTypeForComponents(c.Components)
		}
		s.chars[c.ID] = &c
		s.dirNames[c.ID] = e.Name()
	}
	return nil
}

func (s *Store) saveOne(c *Character) error {
	dirName, ok := s.dirNames[c.ID]
	if !ok {
		return fmt.Errorf("no directory mapping for character %s", c.ID)
	}
	jsonPath := filepath.Join(s.baseDir, dirName, "character.json")
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(jsonPath, data, 0644)
}

// sanitizeName replaces filesystem-unsafe characters and truncates to 50 chars.
func sanitizeName(name string) string {
	unsafe := regexp.MustCompile(`[/\\:*?"<>|]`)
	s := unsafe.ReplaceAllString(name, "_")
	s = strings.TrimSpace(s)
	// Truncate by rune to avoid breaking multi-byte chars
	runes := []rune(s)
	if len(runes) > 50 {
		runes = runes[:50]
	}
	s = string(runes)
	if s == "" {
		s = "unnamed"
	}
	return s
}

func ownerDirName(ownerID string) string {
	ownerID = strings.TrimSpace(ownerID)
	if ownerID == "" {
		return "anonymous"
	}
	var b strings.Builder
	for _, r := range ownerID {
		switch {
		case r >= 'a' && r <= 'z':
			b.WriteRune(r)
		case r >= 'A' && r <= 'Z':
			b.WriteRune(r)
		case r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == '.' || r == '_' || r == '-':
			b.WriteRune(r)
		default:
			b.WriteByte('_')
		}
	}
	if b.Len() == 0 {
		return "anonymous"
	}
	return b.String()
}

// charDirName returns the directory name for a character: "{sanitizedName}_{id[:8]}"
func charDirName(name, id string) string {
	return sanitizeName(name) + "_" + shortID(id)
}

func shortID(id string) string {
	clean := strings.ReplaceAll(id, "-", "")
	if len(clean) > 8 {
		clean = clean[:8]
	}
	return clean
}

// ListImages returns images with the active image first, then by filename.
func (s *Store) ListImages(id string) ([]ImageInfo, error) {
	s.mu.RLock()
	c, ok := s.chars[id]
	s.mu.RUnlock()
	if !ok {
		return nil, fmt.Errorf("character not found: %s", id)
	}
	imgs := make([]ImageInfo, len(c.Images))
	copy(imgs, c.Images)
	sort.Slice(imgs, func(i, j int) bool {
		if imgs[i].Filename == c.ActiveImage {
			return true
		}
		if imgs[j].Filename == c.ActiveImage {
			return false
		}
		return imgs[i].Filename < imgs[j].Filename
	})
	return imgs, nil
}

// AddImage adds an image entry to the character and persists.
func (s *Store) AddImage(id string, info ImageInfo) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	c, ok := s.chars[id]
	if !ok {
		return fmt.Errorf("character not found: %s", id)
	}

	c.Images = append(c.Images, info)

	// Auto-activate first image
	if c.ActiveImage == "" {
		c.ActiveImage = info.Filename
		c.AvatarImage = fmt.Sprintf("/api/v1/characters/%s/images/%s", id, info.Filename)
	}

	c.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	return s.saveOne(c)
}

// RemoveImage removes an image entry. If it was active, switches to the first remaining.
func (s *Store) RemoveImage(id, filename string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	c, ok := s.chars[id]
	if !ok {
		return fmt.Errorf("character not found: %s", id)
	}

	found := false
	newImages := make([]ImageInfo, 0, len(c.Images))
	for _, img := range c.Images {
		if img.Filename == filename {
			found = true
			continue
		}
		newImages = append(newImages, img)
	}
	if !found {
		return fmt.Errorf("image not found: %s", filename)
	}

	c.Images = newImages

	if c.ActiveImage == filename {
		if len(c.Images) > 0 {
			c.ActiveImage = c.Images[0].Filename
			c.AvatarImage = fmt.Sprintf("/api/v1/characters/%s/images/%s", id, c.ActiveImage)
		} else {
			c.ActiveImage = ""
			c.AvatarImage = ""
		}
	}

	c.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	return s.saveOne(c)
}

// ActivateImage sets a specific image as the active avatar.
func (s *Store) ActivateImage(id, filename string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	c, ok := s.chars[id]
	if !ok {
		return fmt.Errorf("character not found: %s", id)
	}

	found := false
	activeIndex := -1
	for i, img := range c.Images {
		if img.Filename == filename {
			found = true
			activeIndex = i
			break
		}
	}
	if !found {
		return fmt.Errorf("image not found: %s", filename)
	}

	if activeIndex > 0 {
		active := c.Images[activeIndex]
		copy(c.Images[1:activeIndex+1], c.Images[0:activeIndex])
		c.Images[0] = active
	}
	c.ActiveImage = filename
	c.AvatarImage = fmt.Sprintf("/api/v1/characters/%s/images/%s", id, filename)
	c.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	return s.saveOne(c)
}

// RandomizeImage picks a random image and sets it as the active avatar.
func (s *Store) RandomizeImage(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	c, ok := s.chars[id]
	if !ok {
		return fmt.Errorf("character not found: %s", id)
	}
	if len(c.Images) == 0 {
		return nil
	}

	idx := rand.Intn(len(c.Images))
	c.ActiveImage = c.Images[idx].Filename
	c.AvatarImage = fmt.Sprintf("/api/v1/characters/%s/images/%s", id, c.ActiveImage)
	c.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	return s.saveOne(c)
}
