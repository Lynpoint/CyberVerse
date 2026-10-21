package direct

import (
    "fmt"
    "os"
    "strconv"
)

// A deployment-only cap keeps slow TCP tunnels from queueing many seconds of video.
func configuredVideoBitrateKbps() (int, error) {
    raw := os.Getenv("CYBERVERSE_DIRECT_VIDEO_KBPS")
    if raw == "" {
        return 0, nil
    }
    value, err := strconv.Atoi(raw)
    if err != nil || value < 100 || value > 4000 {
        return 0, fmt.Errorf("CYBERVERSE_DIRECT_VIDEO_KBPS must be an integer from 100 to 4000")
    }
    return value, nil
}
