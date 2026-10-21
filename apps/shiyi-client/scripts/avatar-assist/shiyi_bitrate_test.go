package direct

import "testing"

func TestShiyiVideoBitrateOverride(t *testing.T) {
    for _, tc := range []struct {
        raw string
        want int
        invalid bool
    }{
        {"", 0, false}, {"240", 240, false}, {"100", 100, false},
        {"4000", 4000, false}, {"99", 0, true},
        {"4001", 0, true}, {"bad", 0, true},
    } {
        t.Run(tc.raw, func(t *testing.T) {
            t.Setenv("CYBERVERSE_DIRECT_VIDEO_KBPS", tc.raw)
            got, err := configuredVideoBitrateKbps()
            if (err != nil) != tc.invalid || got != tc.want {
                t.Fatalf("got %d, %v; want %d, invalid=%v", got, err, tc.want, tc.invalid)
            }
        })
    }
}

func TestShiyiEncoderCapIncludesFallback(t *testing.T) {
    t.Setenv("CYBERVERSE_DIRECT_VIDEO_KBPS", "240")
    p := &DirectPeer{}
    if got := p.currentVideoBitrateKbps(); got != 240 {
        t.Fatalf("uncapped initial encoder bitrate: %d", got)
    }
    p.targetBitrateBps.Store(4_000_000)
    if got := p.currentVideoBitrateKbps(); got != 240 {
        t.Fatalf("uncapped adaptive encoder bitrate: %d", got)
    }
}

func TestShiyiInvalidBitrateFailsStartup(t *testing.T) {
    t.Setenv("CYBERVERSE_DIRECT_VIDEO_KBPS", "bad")
    if _, _, err := NewWebRTCAPI(WebRTCAPIConfig{}); err == nil {
        t.Fatal("invalid deployment bitrate must fail rather than silently overload a tunnel")
    }
}
