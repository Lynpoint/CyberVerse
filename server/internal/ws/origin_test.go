package ws

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
)

// testUpgradeResult performs a real WebSocket handshake against the package
// handler and reports whether it was accepted. This exercises the same
// package-level upgrader used by HandleWebSocket, whose CheckOrigin delegates
// to checkOrigin.
func testUpgradeResult(t *testing.T, origin string) bool {
	t.Helper()

	hub := NewHub()
	srv := httptest.NewServer(HandleWebSocket(hub, "sess-1", nil, nil))
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws/chat/sess-1"
	headers := http.Header{}
	if origin != "" {
		headers.Set("Origin", origin)
	}
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, headers)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func TestDefaultCheckOriginAllowsAll(t *testing.T) {
	SetCheckOrigin(nil) // restore default
	defer SetCheckOrigin(nil)

	if !testUpgradeResult(t, "https://anything.example.com") {
		t.Error("default checker should allow any origin")
	}
}

func TestSetCheckOriginRestrictsUpgrade(t *testing.T) {
	// Same semantics as the API layer installs: allow an explicit allowlist,
	// always allow non-browser clients without an Origin header.
	SetCheckOrigin(func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true
		}
		return origin == "https://app.example.com"
	})
	defer SetCheckOrigin(nil)

	if !testUpgradeResult(t, "https://app.example.com") {
		t.Error("allowed origin should upgrade")
	}
	if testUpgradeResult(t, "https://evil.example.com") {
		t.Error("disallowed origin should not upgrade")
	}
	// Non-browser client without an Origin header is allowed.
	if !testUpgradeResult(t, "") {
		t.Error("missing origin should upgrade")
	}
}
