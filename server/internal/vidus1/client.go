package vidus1

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	defaultAPIBase = "https://api.vidu.cn"
	defaultVoice   = "Tina"
	createTimeout  = 120 * time.Second
	controlTimeout = 20 * time.Second
)

var readyRetryDelays = []time.Duration{0, 2 * time.Second, 4 * time.Second, 8 * time.Second}

// FrontendConfig contains the short-lived AliRTC credentials returned by Vidu.
type FrontendConfig struct {
	LiveID        string `json:"live_id"`
	AppID         string `json:"app_id"`
	ChannelID     string `json:"channel_id"`
	UserID        string `json:"user_id"`
	Token         string `json:"token"`
	TokenExpireAt int64  `json:"token_expire_at"`
	LiveDuration  int    `json:"live_duration"`
}

type Client struct {
	apiBase    string
	apiKey     string
	httpClient *http.Client
	dialer     *websocket.Dialer
}

type Session struct {
	client    *Client
	config    FrontendConfig
	mu        sync.RWMutex
	connectMu sync.Mutex
	writeMu   sync.Mutex
	conn      *websocket.Conn
	ready     bool
	closed    bool
	seqID     int64
	onLost    func(string)
	lostOnce  sync.Once
}

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type createResponse struct {
	Data *createResponse `json:"data,omitempty"`
	Live struct {
		ID           string `json:"id"`
		Status       string `json:"status"`
		LiveDuration int    `json:"live_duration"`
	} `json:"live"`
	RTC struct {
		AppID         string      `json:"app_id"`
		ChannelID     string      `json:"channel_id"`
		UserID        string      `json:"user_id"`
		Token         string      `json:"token"`
		TokenExpireAt interface{} `json:"token_expire_at"`
	} `json:"rtc"`
	Error   apiError `json:"error"`
	Code    string   `json:"code"`
	Message string   `json:"message"`
}

type controlMessage struct {
	Type    int             `json:"type"`
	LiveID  string          `json:"live_id,omitempty"`
	SeqID   int64           `json:"seq_id,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type controlAckPayload struct {
	ConnInitAck struct {
		Success   bool   `json:"success"`
		ErrorCode string `json:"error_code"`
	} `json:"conn_init_ack"`
	Hangup struct {
		Reason string `json:"hangup_reason"`
	} `json:"hangup"`
}

type notReadyError struct{}

func (notReadyError) Error() string { return "Vidu S1 is not ready" }

func NewClientFromEnv() (*Client, error) {
	apiKey := strings.TrimSpace(os.Getenv("VIDU_API_KEY"))
	if apiKey == "" {
		return nil, errors.New("VIDU_API_KEY is required for Vidu S1")
	}
	apiBase := strings.TrimRight(strings.TrimSpace(os.Getenv("VIDU_API_BASE")), "/")
	if apiBase == "" {
		apiBase = defaultAPIBase
	}
	parsed, err := url.Parse(apiBase)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return nil, fmt.Errorf("invalid VIDU_API_BASE %q", apiBase)
	}
	return &Client{
		apiBase:    apiBase,
		apiKey:     apiKey,
		httpClient: &http.Client{Timeout: createTimeout},
		dialer:     websocket.DefaultDialer,
	}, nil
}

func (c *Client) authorization() string {
	if strings.HasPrefix(strings.ToLower(c.apiKey), "token ") {
		return c.apiKey
	}
	return "Token " + c.apiKey
}

func (c *Client) apiURL(path string) string {
	return c.apiBase + path
}

func (c *Client) websocketURL(liveID string) (string, error) {
	u, err := url.Parse(c.apiURL("/live/ws/live/connect"))
	if err != nil {
		return "", err
	}
	if u.Scheme == "https" {
		u.Scheme = "wss"
	} else {
		u.Scheme = "ws"
	}
	query := u.Query()
	query.Set("live_id", liveID)
	u.RawQuery = query.Encode()
	return u.String(), nil
}

func parseUnixTimestamp(value interface{}) (int64, error) {
	switch typed := value.(type) {
	case float64:
		return int64(typed), nil
	case json.Number:
		return typed.Int64()
	case string:
		return strconv.ParseInt(strings.TrimSpace(typed), 10, 64)
	default:
		return 0, fmt.Errorf("unsupported timestamp type %T", value)
	}
}

func (c *Client) Start(ctx context.Context, name, persona, imageURI, voice string) (*Session, error) {
	name = strings.TrimSpace(name)
	persona = strings.TrimSpace(persona)
	imageURI = strings.TrimSpace(imageURI)
	voice = strings.TrimSpace(voice)
	if name == "" || persona == "" || imageURI == "" {
		return nil, errors.New("Vidu S1 requires character name, persona, and image")
	}
	if voice == "" {
		voice = strings.TrimSpace(os.Getenv("VIDU_VOICE"))
	}
	if voice == "" {
		voice = defaultVoice
	}

	body, err := json.Marshal(map[string]interface{}{
		"call_mode": "video",
		"avatar": map[string]string{
			"persona":   persona,
			"image_uri": imageURI,
			"name":      name,
			"voice":     voice,
		},
	})
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.apiURL("/live/v1/lives"), bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", c.authorization())
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Vidu S1 create session request failed: %w", err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("read Vidu S1 create response: %w", err)
	}
	var decoded createResponse
	if err := json.Unmarshal(raw, &decoded); err != nil {
		return nil, fmt.Errorf("Vidu S1 create session returned invalid JSON (HTTP %d)", resp.StatusCode)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		message := strings.TrimSpace(decoded.Error.Message)
		if message == "" {
			message = strings.TrimSpace(decoded.Message)
		}
		code := strings.TrimSpace(decoded.Error.Code)
		if code == "" {
			code = strings.TrimSpace(decoded.Code)
		}
		if message == "" {
			message = http.StatusText(resp.StatusCode)
		}
		if code != "" {
			return nil, fmt.Errorf("Vidu S1 API failed (%s): %s", code, message)
		}
		return nil, fmt.Errorf("Vidu S1 API returned HTTP %d: %s", resp.StatusCode, message)
	}
	payload := &decoded
	if decoded.Data != nil {
		payload = decoded.Data
	}
	expiresAt, err := parseUnixTimestamp(payload.RTC.TokenExpireAt)
	if err != nil {
		return nil, fmt.Errorf("Vidu S1 create session returned invalid RTC token expiry: %w", err)
	}
	config := FrontendConfig{
		LiveID:        strings.TrimSpace(payload.Live.ID),
		AppID:         strings.TrimSpace(payload.RTC.AppID),
		ChannelID:     strings.TrimSpace(payload.RTC.ChannelID),
		UserID:        strings.TrimSpace(payload.RTC.UserID),
		Token:         strings.TrimSpace(payload.RTC.Token),
		TokenExpireAt: expiresAt,
		LiveDuration:  payload.Live.LiveDuration,
	}
	if config.LiveDuration <= 0 {
		config.LiveDuration = 600
	}
	if config.LiveID == "" || config.AppID == "" || config.ChannelID == "" || config.UserID == "" || config.Token == "" {
		return nil, errors.New("Vidu S1 create session returned incomplete live/RTC data")
	}
	return &Session{client: c, config: config, seqID: 1}, nil
}

func (s *Session) FrontendConfig() FrontendConfig {
	return s.config
}

func (s *Session) SetOnLost(fn func(string)) {
	s.mu.Lock()
	s.onLost = fn
	s.mu.Unlock()
}

func (s *Session) Ready() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.ready && !s.closed && s.conn != nil
}

func (s *Session) nextSeqID() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	seqID := s.seqID
	s.seqID++
	return seqID
}

func (s *Session) dial(ctx context.Context) (*websocket.Conn, error) {
	wsURL, err := s.client.websocketURL(s.config.LiveID)
	if err != nil {
		return nil, err
	}
	headers := http.Header{}
	headers.Set("Authorization", s.client.authorization())
	headers.Set("Content-Type", "application/json")
	conn, resp, err := s.client.dialer.DialContext(ctx, wsURL, headers)
	if resp != nil && resp.Body != nil {
		resp.Body.Close()
	}
	if err != nil {
		return nil, fmt.Errorf("Vidu S1 WebSocket connection failed: %w", err)
	}
	return conn, nil
}

func (s *Session) writeJSON(conn *websocket.Conn, value interface{}) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	_ = conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	return conn.WriteJSON(value)
}

func (s *Session) connectOnce(ctx context.Context) (*websocket.Conn, error) {
	conn, err := s.dial(ctx)
	if err != nil {
		return nil, err
	}
	deadline := time.Now().Add(controlTimeout)
	if contextDeadline, ok := ctx.Deadline(); ok && contextDeadline.Before(deadline) {
		deadline = contextDeadline
	}
	_ = conn.SetReadDeadline(deadline)
	if err := s.writeJSON(conn, map[string]interface{}{
		"type":    1,
		"live_id": s.config.LiveID,
		"seq_id":  s.nextSeqID(),
		"payload": map[string]interface{}{"conn_init": map[string]int{"version": 1}},
	}); err != nil {
		conn.Close()
		return nil, fmt.Errorf("send Vidu S1 connection initialization: %w", err)
	}

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			conn.Close()
			return nil, fmt.Errorf("wait for Vidu S1 readiness: %w", err)
		}
		var message controlMessage
		if err := json.Unmarshal(raw, &message); err != nil {
			continue
		}
		var payload controlAckPayload
		if len(message.Payload) > 0 {
			_ = json.Unmarshal(message.Payload, &payload)
		}
		switch message.Type {
		case 2:
			if payload.ConnInitAck.Success {
				_ = conn.SetReadDeadline(time.Time{})
				return conn, nil
			}
			conn.Close()
			if strings.EqualFold(strings.TrimSpace(payload.ConnInitAck.ErrorCode), "NOT_READY") {
				return nil, notReadyError{}
			}
			code := strings.TrimSpace(payload.ConnInitAck.ErrorCode)
			if code == "" {
				code = "UNKNOWN"
			}
			return nil, fmt.Errorf("Vidu S1 initialization failed: %s", code)
		case 6:
			conn.Close()
			reason := strings.TrimSpace(payload.Hangup.Reason)
			if reason == "" {
				reason = "provider_hangup"
			}
			return nil, fmt.Errorf("Vidu S1 hung up during initialization: %s", reason)
		}
	}
}

func (s *Session) Connect(ctx context.Context) error {
	s.connectMu.Lock()
	defer s.connectMu.Unlock()
	if s.Ready() {
		return nil
	}
	s.mu.RLock()
	closed := s.closed
	s.mu.RUnlock()
	if closed {
		return errors.New("Vidu S1 session is closed")
	}
	var lastErr error
	for _, delay := range readyRetryDelays {
		if delay > 0 {
			timer := time.NewTimer(delay)
			select {
			case <-ctx.Done():
				timer.Stop()
				return ctx.Err()
			case <-timer.C:
			}
		}
		conn, err := s.connectOnce(ctx)
		if err == nil {
			s.mu.Lock()
			if s.closed {
				s.mu.Unlock()
				conn.Close()
				return errors.New("Vidu S1 session is closed")
			}
			s.conn = conn
			s.ready = true
			s.mu.Unlock()
			go s.readLoop(conn)
			return nil
		}
		lastErr = err
		var notReady notReadyError
		if !errors.As(err, &notReady) {
			return err
		}
	}
	return fmt.Errorf("Vidu S1 did not become ready: %w", lastErr)
}

func (s *Session) readLoop(conn *websocket.Conn) {
	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			s.handleConnectionLoss(conn, "websocket_closed")
			return
		}
		var message controlMessage
		if err := json.Unmarshal(raw, &message); err != nil {
			continue
		}
		if message.Type != 6 {
			continue
		}
		var payload controlAckPayload
		_ = json.Unmarshal(message.Payload, &payload)
		reason := strings.TrimSpace(payload.Hangup.Reason)
		if reason == "" {
			reason = "provider_hangup"
		}
		s.handleConnectionLoss(conn, reason)
		return
	}
}

func (s *Session) handleConnectionLoss(conn *websocket.Conn, reason string) {
	s.mu.Lock()
	if s.closed || s.conn != conn {
		s.mu.Unlock()
		return
	}
	s.conn = nil
	s.ready = false
	onLost := s.onLost
	s.mu.Unlock()
	s.lostOnce.Do(func() {
		if onLost != nil {
			onLost(reason)
		}
	})
}

func (s *Session) SendText(text string) error {
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}
	s.mu.RLock()
	conn := s.conn
	ready := s.ready && !s.closed
	s.mu.RUnlock()
	if !ready || conn == nil {
		return errors.New("Vidu S1 is waiting for the browser RTC connection")
	}
	if err := s.writeJSON(conn, map[string]interface{}{
		"type": 99,
		"payload": map[string]interface{}{
			"text_msg": map[string]string{"content": text},
		},
	}); err != nil {
		return fmt.Errorf("send Vidu S1 text input: %w", err)
	}
	return nil
}

func (s *Session) Close(ctx context.Context) error {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return nil
	}
	s.closed = true
	s.ready = false
	conn := s.conn
	s.conn = nil
	s.mu.Unlock()

	if conn == nil {
		var err error
		conn, err = s.dial(ctx)
		if err != nil {
			return err
		}
	}
	defer conn.Close()
	message := map[string]interface{}{
		"type":    5,
		"live_id": s.config.LiveID,
		"seq_id":  s.nextSeqID(),
		"payload": map[string]interface{}{
			"hangup": map[string]string{"hangup_reason": "user_end"},
		},
	}
	if err := s.writeJSON(conn, message); err != nil {
		return fmt.Errorf("send Vidu S1 hangup: %w", err)
	}
	_ = conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""), time.Now().Add(time.Second))
	return nil
}
