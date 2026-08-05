package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestGetSettingsMasksSecrets(t *testing.T) {
	const dashScopeKey = "sk-dashscope-super-secret-123456"
	const openAIKey = "sk-openai-super-secret-123456"
	const liveKitSecret = "livekit-secret-value-123456"
	t.Setenv("DASHSCOPE_API_KEY", dashScopeKey)
	t.Setenv("OPENAI_API_KEY", openAIKey)
	t.Setenv("LIVEKIT_API_SECRET", liveKitSecret)

	r := newTestRouter()
	req := httptest.NewRequest("GET", "/api/v1/settings", nil)
	w := httptest.NewRecorder()
	r.Handler().ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp SettingsResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}

	// Full secrets must never reach the browser.
	if strings.Contains(w.Body.String(), dashScopeKey) {
		t.Error("GET /settings leaked DASHSCOPE_API_KEY in full")
	}
	if strings.Contains(w.Body.String(), openAIKey) {
		t.Error("GET /settings leaked OPENAI_API_KEY in full")
	}
	if strings.Contains(w.Body.String(), liveKitSecret) {
		t.Error("GET /settings leaked LIVEKIT_API_SECRET in full")
	}

	// Masked values must still be present so the UI knows the key is set.
	for name, got := range map[string]string{
		"dashscope_api_key":  resp.ModelProviders.DashScopeAPIKey,
		"openai_api_key":     resp.ModelProviders.OpenAIAPIKey,
		"llm.api_key":        resp.LLM.APIKey,
		"livekit.api_secret": resp.LiveKit.APISecret,
	} {
		if !strings.Contains(got, "****") {
			t.Errorf("%s not masked: %q", name, got)
		}
	}
}

func TestUpdateSettingsIgnoresMaskedSecrets(t *testing.T) {
	envFile, err := os.CreateTemp("", "cyberverse-env-*")
	if err != nil {
		t.Fatal(err)
	}
	envPath := envFile.Name()
	t.Cleanup(func() { os.Remove(envPath) })

	t.Setenv("DOUBAO_ACCESS_TOKEN", "real-token-value")
	r := newTestRouter()
	r.envPath = envPath

	// The browser echoes the masked value back unchanged.
	body := `{"doubao":{"access_token":"real****value"}}`
	req := httptest.NewRequest("PUT", "/api/v1/settings", strings.NewReader(body))
	w := httptest.NewRecorder()
	r.Handler().ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	// The masked value must not overwrite the real secret.
	if got := os.Getenv("DOUBAO_ACCESS_TOKEN"); got != "real-token-value" {
		t.Errorf("masked value overwrote secret: got %q", got)
	}
	envContent, _ := os.ReadFile(envPath)
	if strings.Contains(string(envContent), "real****value") {
		t.Error("masked value was persisted to .env")
	}
}

func TestUpdateSettingsWritesNewSecret(t *testing.T) {
	envFile, err := os.CreateTemp("", "cyberverse-env-*")
	if err != nil {
		t.Fatal(err)
	}
	envPath := envFile.Name()
	t.Cleanup(func() { os.Remove(envPath) })

	r := newTestRouter()
	r.envPath = envPath

	body := `{"doubao":{"access_token":"brand-new-token"}}`
	req := httptest.NewRequest("PUT", "/api/v1/settings", strings.NewReader(body))
	w := httptest.NewRecorder()
	r.Handler().ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if got := os.Getenv("DOUBAO_ACCESS_TOKEN"); got != "brand-new-token" {
		t.Errorf("new secret not applied: got %q", got)
	}
}
