package api

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/cyberverse/server/internal/character"
	"github.com/cyberverse/server/internal/vidus1"
)

const viduBase64ImageMaxBytes = 20 * 1024 * 1024

type viduSessionConfig = vidus1.FrontendConfig

func viduPersona(c *character.Character) string {
	if c == nil {
		return ""
	}
	if prompt := strings.TrimSpace(c.SystemPrompt); prompt != "" {
		return prompt
	}
	parts := []string{fmt.Sprintf("你是%s。", strings.TrimSpace(c.Name))}
	if value := strings.TrimSpace(c.Description); value != "" {
		parts = append(parts, value)
	}
	if value := strings.TrimSpace(c.Personality); value != "" {
		parts = append(parts, "你的性格是："+value+"。")
	}
	if value := strings.TrimSpace(c.SpeakingStyle); value != "" {
		parts = append(parts, "你的表达风格是："+value+"。")
	}
	parts = append(parts, "请自然地与用户实时互动。")
	return strings.Join(parts, "\n")
}

func viduVoice(c *character.Character) string {
	if c == nil || !strings.EqualFold(strings.TrimSpace(c.VoiceProvider), "qwen_omni") {
		return ""
	}
	return strings.TrimSpace(c.VoiceType)
}

func (r *Router) viduImageURI(c *character.Character) (string, error) {
	if c == nil {
		return "", errors.New("Vidu S1 character is required")
	}
	avatarImage := strings.TrimSpace(c.AvatarImage)
	if strings.HasPrefix(avatarImage, "data:image/") || strings.HasPrefix(avatarImage, "https://") || strings.HasPrefix(avatarImage, "http://") {
		return avatarImage, nil
	}
	filename := filepath.Base(strings.TrimSpace(c.ActiveImage))
	if filename == "." || filename == "" {
		return "", errors.New("Vidu S1 requires an uploaded character image")
	}
	imagePath := filepath.Join(r.charStore.ImagesDir(c.ID), filename)
	info, err := os.Stat(imagePath)
	if err != nil {
		return "", fmt.Errorf("read Vidu S1 character image: %w", err)
	}
	if info.Size() > viduBase64ImageMaxBytes {
		return "", fmt.Errorf("Vidu S1 base64 character image must be at most %d MB", viduBase64ImageMaxBytes/(1024*1024))
	}
	data, err := os.ReadFile(imagePath)
	if err != nil {
		return "", fmt.Errorf("read Vidu S1 character image: %w", err)
	}
	contentType := http.DetectContentType(data)
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".png":
		contentType = "image/png"
	case ".jpg", ".jpeg":
		contentType = "image/jpeg"
	case ".webp":
		contentType = "image/webp"
	}
	switch contentType {
	case "image/png", "image/jpeg", "image/webp":
	default:
		return "", fmt.Errorf("Vidu S1 does not support character image type %q", contentType)
	}
	return "data:" + contentType + ";base64," + base64.StdEncoding.EncodeToString(data), nil
}

func (r *Router) startViduSession(ctx context.Context, c *character.Character) (*vidus1.Session, *viduSessionConfig, error) {
	if c == nil || c.AvatarBackend != character.AvatarBackendVidu {
		return nil, nil, errors.New("Vidu S1 character is required")
	}
	imageURI, err := r.viduImageURI(c)
	if err != nil {
		return nil, nil, err
	}
	client, err := vidus1.NewClientFromEnv()
	if err != nil {
		return nil, nil, err
	}
	runtime, err := client.Start(ctx, c.Name, viduPersona(c), imageURI, viduVoice(c))
	if err != nil {
		return nil, nil, err
	}
	config := runtime.FrontendConfig()
	return runtime, &config, nil
}
