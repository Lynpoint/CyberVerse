package api

import (
	"net/http"
	"strconv"
	"strings"
)

func (r *Router) handleGetConversationMessages(w http.ResponseWriter, req *http.Request) {
	characterID := req.PathValue("id")
	if characterID == "" {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "character id is required"})
		return
	}

	// Parse query params
	limitStr := req.URL.Query().Get("limit")
	limit := 50
	if limitStr != "" {
		if v, err := strconv.Atoi(limitStr); err == nil && v > 0 && v <= 200 {
			limit = v
		}
	}
	before := req.URL.Query().Get("before")

	var messages []map[string]any
	var nextCursor string
	var hasMore bool
	var err error
	if isKanshanCharacter(characterID) {
		ownerID, ownerErr := r.ensureAnonymousOwner(w, req)
		if ownerErr != nil {
			writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: ownerErr.Error()})
			return
		}
		messages, nextCursor, hasMore, err = r.charStore.LoadRecentMessagesForOwner(characterID, ownerID, before, limit)
	} else {
		messages, nextCursor, hasMore, err = r.charStore.LoadRecentMessages(characterID, before, limit)
	}
	if err != nil {
		if strings.Contains(err.Error(), "not found") {
			writeJSON(w, http.StatusNotFound, ErrorResponse{Error: err.Error()})
		} else {
			writeJSON(w, http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}
	if messages == nil {
		messages = []map[string]any{}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"messages":    messages,
		"next_cursor": nextCursor,
		"has_more":    hasMore,
	})
}
