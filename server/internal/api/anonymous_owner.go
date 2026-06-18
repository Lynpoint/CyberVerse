package api

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"net/http"
	"strings"
	"time"
)

const (
	anonymousOwnerCookieName = "cyberverse_anonymous_owner"
	anonymousOwnerTTL        = 180 * 24 * time.Hour
	anonymousOwnerPrefix     = "anon:"
)

func (r *Router) ensureAnonymousOwner(w http.ResponseWriter, req *http.Request) (string, error) {
	if ownerID, ok := anonymousOwnerFromRequest(req); ok {
		return ownerID, nil
	}
	token, err := randomOwnerToken()
	if err != nil {
		return "", err
	}
	http.SetCookie(w, anonymousOwnerCookie(req, token))
	return anonymousOwnerPrefix + token, nil
}

func anonymousOwnerFromRequest(req *http.Request) (string, bool) {
	cookie, err := req.Cookie(anonymousOwnerCookieName)
	if err != nil || cookie.Value == "" {
		return "", false
	}
	token := strings.TrimSpace(cookie.Value)
	if !validOwnerToken(token) {
		return "", false
	}
	return anonymousOwnerPrefix + token, true
}

func randomOwnerToken() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", errors.New("failed to generate anonymous owner")
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func validOwnerToken(token string) bool {
	raw, err := base64.RawURLEncoding.DecodeString(token)
	return err == nil && len(raw) == 32
}

func anonymousOwnerCookie(req *http.Request, token string) *http.Cookie {
	return &http.Cookie{
		Name:     anonymousOwnerCookieName,
		Value:    token,
		Path:     "/",
		Expires:  time.Now().Add(anonymousOwnerTTL),
		MaxAge:   int(anonymousOwnerTTL.Seconds()),
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Secure:   requestIsHTTPS(req),
	}
}

func requestIsHTTPS(req *http.Request) bool {
	if req.TLS != nil {
		return true
	}
	return strings.EqualFold(req.Header.Get("X-Forwarded-Proto"), "https")
}
