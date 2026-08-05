package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestCORSAllowsAllowlistedOrigin(t *testing.T) {
	r := newTestRouter() // CORSOrigins includes https://app.example.com

	req := httptest.NewRequest("GET", "/api/v1/health", nil)
	req.Header.Set("Origin", "https://app.example.com")
	w := httptest.NewRecorder()
	r.Handler().ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "https://app.example.com" {
		t.Errorf("expected allowlisted origin echoed, got %q", got)
	}
}

func TestCORSAllowsLocalhostOrigin(t *testing.T) {
	r := newTestRouter()

	for _, origin := range []string{"http://localhost:5173", "http://127.0.0.1:8080"} {
		req := httptest.NewRequest("GET", "/api/v1/health", nil)
		req.Header.Set("Origin", origin)
		w := httptest.NewRecorder()
		r.Handler().ServeHTTP(w, req)

		if got := w.Header().Get("Access-Control-Allow-Origin"); got != origin {
			t.Errorf("origin %s: expected echoed, got %q", origin, got)
		}
	}
}

func TestCORSRejectsUnknownOrigin(t *testing.T) {
	r := newTestRouter()

	req := httptest.NewRequest("GET", "/api/v1/health", nil)
	req.Header.Set("Origin", "https://evil.example.com")
	w := httptest.NewRecorder()
	r.Handler().ServeHTTP(w, req)

	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("unexpected ACAO header for disallowed origin: %q", got)
	}
}

func TestCORSRejectsPreflightFromUnknownOrigin(t *testing.T) {
	r := newTestRouter()

	req := httptest.NewRequest("OPTIONS", "/api/v1/health", nil)
	req.Header.Set("Origin", "https://evil.example.com")
	w := httptest.NewRecorder()
	r.Handler().ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403 for disallowed preflight, got %d", w.Code)
	}
}

func TestCORSKeepsWildcardForNoOrigin(t *testing.T) {
	r := newTestRouter()

	req := httptest.NewRequest("GET", "/api/v1/health", nil)
	w := httptest.NewRecorder()
	r.Handler().ServeHTTP(w, req)

	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Errorf("expected wildcard for non-browser request, got %q", got)
	}
}

func TestOriginAllowed(t *testing.T) {
	r := newTestRouter()

	allowed := []string{
		"http://localhost:3000",
		"https://127.0.0.1:9443",
		"https://app.example.com",
	}
	for _, origin := range allowed {
		if !r.originAllowed(origin) {
			t.Errorf("origin %q should be allowed", origin)
		}
	}

	denied := []string{
		"https://evil.example.com",
		"https://localhost.evil.com",
		"http://notlocalhost",
		"file:///etc/passwd",
	}
	for _, origin := range denied {
		if r.originAllowed(origin) {
			t.Errorf("origin %q should be denied", origin)
		}
	}
}
