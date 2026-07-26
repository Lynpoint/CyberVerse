package api

import (
	"testing"

	"github.com/cyberverse/server/internal/character"
)

func TestViduVoice(t *testing.T) {
	tests := []struct {
		name      string
		character *character.Character
		want      string
	}{
		{name: "nil character", want: ""},
		{name: "legacy provider", character: &character.Character{VoiceProvider: "doubao", VoiceType: "温柔文雅"}, want: ""},
		{name: "qwen omni", character: &character.Character{VoiceProvider: " qwen_omni ", VoiceType: " Cindy "}, want: "Cindy"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := viduVoice(tt.character); got != tt.want {
				t.Fatalf("viduVoice() = %q, want %q", got, tt.want)
			}
		})
	}
}
