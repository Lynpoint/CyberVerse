package vidus1

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestSessionProtocolRetriesNotReadyAndHangsUp(t *testing.T) {
	var connections atomic.Int32
	var createBody map[string]interface{}
	controlMessages := make(chan controlMessage, 4)
	upgrader := websocket.Upgrader{CheckOrigin: func(*http.Request) bool { return true }}

	mux := http.NewServeMux()
	mux.HandleFunc("/live/v1/lives", func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Token test-api-key" {
			t.Errorf("Authorization = %q", got)
		}
		if err := json.NewDecoder(r.Body).Decode(&createBody); err != nil {
			t.Fatalf("decode create body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"live":{"id":"live-1","status":"created","live_duration":600},"rtc":{"app_id":"app-1","channel_id":"channel-1","user_id":"user-1","token":"rtc-token","token_expire_at":"4102444800"}}`))
	})
	mux.HandleFunc("/live/ws/live/connect", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("live_id") != "live-1" {
			t.Errorf("live_id = %q", r.URL.Query().Get("live_id"))
		}
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			t.Errorf("upgrade: %v", err)
			return
		}
		defer conn.Close()

		var initMessage controlMessage
		if err := conn.ReadJSON(&initMessage); err != nil {
			t.Errorf("read init: %v", err)
			return
		}
		attempt := connections.Add(1)
		success := attempt > 1
		errorCode := ""
		if !success {
			errorCode = "NOT_READY"
		}
		if err := conn.WriteJSON(map[string]interface{}{
			"type": 2,
			"payload": map[string]interface{}{
				"conn_init_ack": map[string]interface{}{"success": success, "error_code": errorCode},
			},
		}); err != nil {
			t.Errorf("write init ack: %v", err)
			return
		}
		if !success {
			return
		}
		for {
			var message controlMessage
			if err := conn.ReadJSON(&message); err != nil {
				return
			}
			controlMessages <- message
			if message.Type == 5 {
				return
			}
		}
	})

	server := httptest.NewServer(mux)
	defer server.Close()
	t.Setenv("VIDU_API_KEY", "test-api-key")
	t.Setenv("VIDU_API_BASE", server.URL)
	oldDelays := readyRetryDelays
	readyRetryDelays = []time.Duration{0, time.Millisecond}
	defer func() { readyRetryDelays = oldDelays }()

	client, err := NewClientFromEnv()
	if err != nil {
		t.Fatal(err)
	}
	session, err := client.Start(context.Background(), "Avatar", "Be helpful", "data:image/png;base64,AA==", "Cindy")
	if err != nil {
		t.Fatal(err)
	}
	avatar := createBody["avatar"].(map[string]interface{})
	if avatar["persona"] != "Be helpful" || avatar["image_uri"] != "data:image/png;base64,AA==" || avatar["voice"] != "Cindy" {
		t.Fatalf("unexpected avatar body: %#v", avatar)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := session.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	if connections.Load() != 2 || !session.Ready() {
		t.Fatalf("connections=%d ready=%v", connections.Load(), session.Ready())
	}
	if err := session.SendText("hello"); err != nil {
		t.Fatal(err)
	}
	textMessage := <-controlMessages
	if textMessage.Type != 99 || !strings.Contains(string(textMessage.Payload), `"content":"hello"`) {
		t.Fatalf("unexpected text message: %#v", textMessage)
	}
	if err := session.Close(ctx); err != nil {
		t.Fatal(err)
	}
	hangupMessage := <-controlMessages
	if hangupMessage.Type != 5 || !strings.Contains(string(hangupMessage.Payload), `"hangup_reason":"user_end"`) {
		t.Fatalf("unexpected hangup message: %#v", hangupMessage)
	}
}

func TestNewClientFromEnvRequiresAPIKey(t *testing.T) {
	t.Setenv("VIDU_API_KEY", "")
	if _, err := NewClientFromEnv(); err == nil {
		t.Fatal("expected missing API key error")
	}
}
