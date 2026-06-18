package api

import (
	"net/http"
	"strings"

	"github.com/cyberverse/server/internal/agenttask"
	"github.com/cyberverse/server/internal/kanshan"
	"github.com/cyberverse/server/internal/orchestrator"
)

func isKanshanCharacter(characterID string) bool {
	return strings.TrimSpace(characterID) == kanshan.CharacterID
}

func writeNotFound(w http.ResponseWriter, message string) {
	if strings.TrimSpace(message) == "" {
		message = "not found"
	}
	writeJSON(w, http.StatusNotFound, ErrorResponse{Error: message})
}

func (r *Router) authorizeKanshanSessionAccess(w http.ResponseWriter, req *http.Request, session *orchestrator.Session) bool {
	if session == nil || !isKanshanCharacter(session.CharacterID) {
		return true
	}
	ownerID, err := r.ensureAnonymousOwner(w, req)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return false
	}
	if session.OwnerIDSnapshot() != ownerID {
		writeNotFound(w, orchestrator.ErrSessionNotFound.Error())
		return false
	}
	return true
}

func (r *Router) authorizeTaskAccess(w http.ResponseWriter, req *http.Request, task *agenttask.Task) bool {
	if task == nil || strings.TrimSpace(task.OwnerID) == "" {
		return true
	}
	ownerID, err := r.ensureAnonymousOwner(w, req)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return false
	}
	if task.OwnerID != ownerID {
		writeNotFound(w, agenttask.ErrNotFound.Error())
		return false
	}
	return true
}

func (r *Router) filterVisibleTasks(w http.ResponseWriter, req *http.Request, tasks []agenttask.Task) ([]agenttask.Task, bool) {
	ownerID, hasOwner := anonymousOwnerFromRequest(req)
	visible := tasks[:0]
	privateDenied := false
	for _, task := range tasks {
		if strings.TrimSpace(task.OwnerID) == "" {
			visible = append(visible, task)
			continue
		}
		if hasOwner && task.OwnerID == ownerID {
			visible = append(visible, task)
			continue
		}
		privateDenied = true
	}
	if len(visible) == 0 && privateDenied {
		if !hasOwner {
			if _, err := r.ensureAnonymousOwner(w, req); err != nil {
				writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
				return nil, false
			}
		}
		writeNotFound(w, agenttask.ErrNotFound.Error())
		return nil, false
	}
	return visible, true
}
