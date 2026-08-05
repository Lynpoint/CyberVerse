package api

import (
	"net/http"
	"net/url"
	"path/filepath"

	"github.com/cyberverse/server/internal/agenttask"
	"github.com/cyberverse/server/internal/character"
	"github.com/cyberverse/server/internal/config"
	"github.com/cyberverse/server/internal/livekit"
	"github.com/cyberverse/server/internal/orchestrator"
	ragstore "github.com/cyberverse/server/internal/rag"
	"github.com/cyberverse/server/internal/ws"
)

type Router struct {
	sessionMgr *orchestrator.SessionManager
	orch       *orchestrator.Orchestrator
	wsHub      *ws.Hub
	roomMgr    *livekit.RoomManager
	taskSvc    *agenttask.Service
	cfg        *config.Config
	charStore  *character.Store
	ragStore   *ragstore.Store
	envPath    string
	configPath string
	modelsDir  string
	mux        *http.ServeMux
}

func NewRouter(
	sessionMgr *orchestrator.SessionManager,
	orch *orchestrator.Orchestrator,
	wsHub *ws.Hub,
	roomMgr *livekit.RoomManager,
	cfg *config.Config,
	charStore *character.Store,
	envPath string,
	configPath string,
	taskServices ...*agenttask.Service,
) *Router {
	r := &Router{
		sessionMgr: sessionMgr,
		orch:       orch,
		wsHub:      wsHub,
		roomMgr:    roomMgr,
		cfg:        cfg,
		charStore:  charStore,
		ragStore:   ragstore.NewStore(charStore),
		envPath:    envPath,
		configPath: configPath,
		modelsDir:  filepath.Join(filepath.Dir(configPath), "models"),
		mux:        http.NewServeMux(),
	}
	if len(taskServices) > 0 {
		r.taskSvc = taskServices[0]
	}
	// WebSocket upgrades share the CORS origin allowlist enforced by
	// corsMiddleware so both HTTP and WS reject cross-origin clients.
	// Non-browser clients without an Origin header are always allowed.
	ws.SetCheckOrigin(func(req *http.Request) bool {
		origin := req.Header.Get("Origin")
		if origin == "" {
			return true
		}
		return r.originAllowed(origin)
	})
	r.registerRoutes()
	return r
}

func (r *Router) registerRoutes() {
	r.mux.HandleFunc("GET /api/v1/health", r.handleHealth)
	r.mux.HandleFunc("GET /api/v1/components", r.handleListComponents)
	r.mux.HandleFunc("GET /api/v1/baidu-xiling/figures/{figure_id}", r.handleGetBaiduXilingFigure)
	r.mux.HandleFunc("GET /api/v1/xunfei/avatars/{avatar_id}", r.handleGetXunfeiAvatar)
	r.mux.HandleFunc("GET /api/v1/xunfei/sessions/{id}/stream.flv", r.handleXunfeiAvatarStream)
	r.mux.HandleFunc("POST /api/v1/sessions", r.handleCreateSession)
	r.mux.HandleFunc("DELETE /api/v1/sessions/{id}", r.handleDeleteSession)
	r.mux.HandleFunc("POST /api/v1/sessions/{id}/message", r.handleSendMessage)
	r.mux.HandleFunc("GET /api/v1/sessions/{id}/tasks", r.handleListSessionTasks)
	r.mux.HandleFunc("GET /api/v1/sessions", r.handleListSessions)
	r.mux.HandleFunc("GET /api/v1/tasks/{task_id}", r.handleGetTask)
	r.mux.HandleFunc("GET /api/v1/tasks/{task_id}/events", r.handleListTaskEvents)
	r.mux.HandleFunc("GET /api/v1/tasks/{task_id}/artifacts/{artifact_id}", r.handleGetTaskArtifact)
	r.mux.HandleFunc("POST /api/v1/internal/tasks/{task_id}/events", r.handleInternalTaskEvent)
	r.mux.HandleFunc("POST /api/v1/internal/tasks/{task_id}/artifacts", r.handleInternalTaskArtifact)
	r.mux.HandleFunc("POST /api/v1/internal/characters/{id}/knowledge/search", r.handleInternalKnowledgeSearch)
	r.mux.HandleFunc("GET /ws/chat/{id}", r.handleWebSocket)

	// Character CRUD
	r.mux.HandleFunc("GET /api/v1/characters", r.handleListCharacters)
	r.mux.HandleFunc("POST /api/v1/characters", r.handleCreateCharacter)
	r.mux.HandleFunc("POST /api/v1/characters/test-voice", r.handleTestCharacterVoice)
	r.mux.HandleFunc("GET /api/v1/characters/{id}", r.handleGetCharacter)
	r.mux.HandleFunc("PUT /api/v1/characters/{id}", r.handleUpdateCharacter)
	r.mux.HandleFunc("PUT /api/v1/characters/{id}/offline-video-tts", r.handleUpdateCharacterOfflineVideoTTS)
	r.mux.HandleFunc("DELETE /api/v1/characters/{id}", r.handleDeleteCharacter)
	r.mux.HandleFunc("POST /api/v1/characters/{id}/avatar", r.handleUploadAvatar)
	r.mux.HandleFunc("GET /api/v1/characters/{id}/images", r.handleListImages)
	r.mux.HandleFunc("GET /api/v1/characters/{id}/images/{filename}", r.handleGetCharacterImage)
	r.mux.HandleFunc("GET /api/v1/characters/{id}/offline-videos", r.handleListOfflineVideos)
	r.mux.HandleFunc("POST /api/v1/characters/{id}/offline-videos", r.handleCreateOfflineVideo)
	r.mux.HandleFunc("GET /api/v1/characters/{id}/offline-videos/{job_id}", r.handleGetOfflineVideo)
	r.mux.HandleFunc("PATCH /api/v1/characters/{id}/offline-videos/{job_id}", r.handleUpdateOfflineVideo)
	r.mux.HandleFunc("GET /api/v1/characters/{id}/offline-videos/{job_id}/video", r.handleGetOfflineVideoFile)
	r.mux.HandleFunc("DELETE /api/v1/characters/{id}/offline-videos/{job_id}", r.handleDeleteOfflineVideo)
	r.mux.HandleFunc("GET /api/v1/characters/{id}/knowledge", r.handleListKnowledgeSources)
	r.mux.HandleFunc("POST /api/v1/characters/{id}/knowledge/files", r.handleUploadKnowledgeFiles)
	r.mux.HandleFunc("DELETE /api/v1/characters/{id}/knowledge/{source_id}", r.handleDeleteKnowledgeSource)
	r.mux.HandleFunc("POST /api/v1/characters/{id}/knowledge/{source_id}/reindex", r.handleReindexKnowledgeSource)
	r.mux.HandleFunc("GET /api/v1/characters/{id}/idle-videos/{imgbase}/{variant}/{filename}", r.handleGetIdleVideo)
	r.mux.HandleFunc("GET /api/v1/characters/{id}/idle-videos/{imgbase}/{filename}", r.handleGetIdleVideo)
	r.mux.HandleFunc("DELETE /api/v1/characters/{id}/images/{filename}", r.handleDeleteImage)
	r.mux.HandleFunc("PUT /api/v1/characters/{id}/images/{filename}/activate", r.handleActivateImage)
	r.mux.HandleFunc("GET /api/v1/avatars/{filename}", r.handleGetAvatar)

	// Conversation history
	r.mux.HandleFunc("GET /api/v1/characters/{id}/conversations/messages", r.handleGetConversationMessages)

	// Settings
	r.mux.HandleFunc("GET /api/v1/settings", r.handleGetSettings)
	r.mux.HandleFunc("PUT /api/v1/settings", r.handleUpdateSettings)
	r.mux.HandleFunc("POST /api/v1/settings/test", r.handleTestConnection)

	// Launch config
	r.mux.HandleFunc("GET /api/v1/config/avatar-model", r.handleGetAvatarModelInfo)
	r.mux.HandleFunc("GET /api/v1/config/launch", r.handleGetLaunchConfig)
	r.mux.HandleFunc("PUT /api/v1/config/launch", r.handleUpdateLaunchConfig)
}

func (r *Router) Handler() http.Handler {
	return r.corsMiddleware(r.mux)
}

// corsMiddleware enforces an origin allowlist on cross-origin requests.
// Requests without an Origin header (curl, tests, same-origin) are unaffected.
func (r *Router) corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		origin := req.Header.Get("Origin")
		if origin == "" {
			// Non-browser client or same-origin request; keep the wildcard
			// behavior so plain HTTP clients are not affected.
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		} else if r.originAllowed(origin) {
			// Echo the exact origin instead of "*" so credentials could be
			// used later and only allowlisted origins receive the header.
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		}

		if req.Method == http.MethodOptions {
			// Preflight: reject explicitly when the origin is not allowed.
			if origin != "" && !r.originAllowed(origin) {
				writeJSON(w, http.StatusForbidden, ErrorResponse{Error: "origin not allowed"})
				return
			}
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, req)
	})
}

// originAllowed reports whether an Origin header value is trusted. Local
// development origins are always allowed; anything else must be listed in
// server.cors_origins (an explicit "*" entry keeps the legacy wildcard
// behavior for deployments that opt into it).
func (r *Router) originAllowed(origin string) bool {
	if isLocalhostOrigin(origin) {
		return true
	}
	for _, o := range r.cfg.Server.CORSOrigins {
		if o == "*" || o == origin {
			return true
		}
	}
	return false
}

// isLocalhostOrigin reports whether origin is a local development origin
// (Vite dev server, local preview, etc.) on any port.
func isLocalhostOrigin(origin string) bool {
	u, err := url.Parse(origin)
	if err != nil || u.Hostname() == "" {
		return false
	}
	switch u.Hostname() {
	case "localhost", "127.0.0.1", "::1":
		return true
	}
	return false
}
