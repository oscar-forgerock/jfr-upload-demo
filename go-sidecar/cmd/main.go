package main

import (
	"fmt"
	"os"

	"github.com/oscar-wu_pingcorp/profiler-sidecar/internal/api"
	"github.com/oscar-wu_pingcorp/profiler-sidecar/internal/daemon"
	"github.com/oscar-wu_pingcorp/profiler-sidecar/internal/logger"
)

func main() {
	// Initialize logger
	logger.Init()

	if len(os.Args) < 2 {
		fmt.Println("Usage: profiler-sidecar [sidecar|daemon]")
		os.Exit(1)
	}

	mode := os.Args[1]

	switch mode {
	case "sidecar":
		logger.Log.WithField("mode", "sidecar").Info("Starting in Sidecar mode (API server)")
		api.Start()
	case "daemon":
		logger.Log.WithField("mode", "daemon").Info("Starting in DaemonSet mode (File scanner)")
		daemon.Start()
	default:
		logger.Log.WithField("mode", mode).Error("Unknown mode. Use 'sidecar' or 'daemon'")
		os.Exit(1)
	}
}
