package api

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/cyberverse/server/internal/config"
)

func TestConfiguredComponentsUseResolvedModelDirs(t *testing.T) {
	root := t.TempDir()
	modelDir := filepath.Join(root, "infra", "config", "tts_models")
	if err := os.MkdirAll(modelDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(modelDir, "qwen.yaml"), []byte(`
qwen:
  plugin_class: pkg.QwenTTS
  model: qwen-tts-test
  voice: TestVoice
`), 0644); err != nil {
		t.Fatal(err)
	}
	configDir := filepath.Join(root, "config")
	if err := os.MkdirAll(configDir, 0755); err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(configDir, "cyberverse.yaml")
	if err := os.WriteFile(configPath, []byte("inference: {}\n"), 0644); err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(configPath)
	if err != nil {
		t.Fatal(err)
	}
	r := &Router{configPath: configPath, cfg: cfg}

	options, err := r.configuredComponentOptions("tts")
	if err != nil {
		t.Fatal(err)
	}
	if len(options) != 1 {
		t.Fatalf("expected one tts option, got %+v", options)
	}
	if options[0].ID != "qwen" || options[0].Model != "qwen-tts-test" || !options[0].Default {
		t.Fatalf("unexpected tts option: %+v", options[0])
	}
	if voice := r.configuredTTSVoice("qwen"); voice != "TestVoice" {
		t.Fatalf("expected TestVoice, got %q", voice)
	}
}

func TestDisplayComponentNameAtlas(t *testing.T) {
	if got := displayComponentName("atlas"); got != "Atlas Cloud" {
		t.Fatalf("expected Atlas Cloud, got %q", got)
	}
}
