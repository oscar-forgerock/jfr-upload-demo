package api

import (
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/oscar-wu_pingcorp/profiler-sidecar/internal/logger"
)

const (
	profileDir = "/tmp/jfr"
	apiPort    = "8081"
)

type ProfileRequest struct {
	Duration string `json:"duration"` // e.g., "60s"
	Name     string `json:"name"`     // optional custom recording name (filename will be derived from this)
}

type StopRequest struct {
	Name string `json:"name"` // name of the JFR recording to stop
}

type Response struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

// Start initializes and runs the API server
func Start() {
	http.HandleFunc("/create", createProfileHandler)
	http.HandleFunc("/stop", stopProfileHandler)
	http.HandleFunc("/list", listProfilesHandler)
	http.HandleFunc("/running", listRunningJFRHandler)
	http.HandleFunc("/health", healthHandler)

	logger.Log.WithField("port", apiPort).Info("API server listening")
	if err := http.ListenAndServe(":"+apiPort, nil); err != nil {
		logger.Log.WithError(err).Fatal("Failed to start API server")
	}
}

// healthHandler returns API health status
func healthHandler(w http.ResponseWriter, r *http.Request) {
	sendJSON(w, http.StatusOK, Response{
		Success: true,
		Message: "API server is healthy",
	})
}

// createProfileHandler starts a JFR profiling session
func createProfileHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		sendJSON(w, http.StatusMethodNotAllowed, Response{
			Success: false,
			Message: "Method not allowed",
		})
		return
	}

	var req ProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendJSON(w, http.StatusBadRequest, Response{
			Success: false,
			Message: fmt.Sprintf("Invalid request body: %v", err),
		})
		return
	}

	// Default duration if not specified
	if req.Duration == "" {
		req.Duration = "60s"
	}

	// Generate timestamp suffix in RFC3339 format (filesystem-safe)
	now := time.Now()
	timestampSuffix := strings.ReplaceAll(now.Format(time.RFC3339), ":", "-")

	// Generate recording name with RFC3339 timestamp if not provided
	if req.Name == "" {
		req.Name = fmt.Sprintf("jfr_%s", timestampSuffix)
	}

	// Derive filename from recording name
	filename := fmt.Sprintf("%s.jfr", req.Name)

	// Get Java process PID
	pid, err := getJavaPID()
	if err != nil {
		sendJSON(w, http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to find Java process: %v", err),
		})
		return
	}

	// Start JFR recording with name
	outputPath := filepath.Join(profileDir, filename)
	logger.Log.WithField("path", outputPath).
		WithField("name", req.Name).
		WithField("duration", req.Duration).
		Debug("Creating profile file")

	cmd := exec.Command("jcmd", strconv.Itoa(pid), "JFR.start",
		fmt.Sprintf("name=%s", req.Name),
		fmt.Sprintf("duration=%s", req.Duration),
		fmt.Sprintf("filename=%s", outputPath))

	output, err := cmd.CombinedOutput()
	if err != nil {
		sendJSON(w, http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to start profiling: %v, output: %s", err, string(output)),
		})
		return
	}

	sendJSON(w, http.StatusOK, Response{
		Success: true,
		Message: "Profiling started successfully",
		Data: map[string]string{
			"pid":      strconv.Itoa(pid),
			"name":     req.Name,
			"duration": req.Duration,
			"filename": filename,
			"output":   string(output),
		},
	})
}

// stopProfileHandler stops a specific JFR profiling session by name
func stopProfileHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		sendJSON(w, http.StatusMethodNotAllowed, Response{
			Success: false,
			Message: "Method not allowed",
		})
		return
	}

	var req StopRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendJSON(w, http.StatusBadRequest, Response{
			Success: false,
			Message: fmt.Sprintf("Invalid request body: %v", err),
		})
		return
	}

	if req.Name == "" {
		sendJSON(w, http.StatusBadRequest, Response{
			Success: false,
			Message: "Recording name is required",
		})
		return
	}

	// Get Java process PID
	pid, err := getJavaPID()
	if err != nil {
		sendJSON(w, http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to find Java process: %v", err),
		})
		return
	}

	// Stop specific JFR recording by name
	cmd := exec.Command("jcmd", strconv.Itoa(pid), "JFR.stop", fmt.Sprintf("name=%s", req.Name))
	output, err := cmd.CombinedOutput()
	if err != nil {
		sendJSON(w, http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to stop profiling: %v, output: %s", err, string(output)),
		})
		return
	}

	sendJSON(w, http.StatusOK, Response{
		Success: true,
		Message: fmt.Sprintf("JFR recording '%s' stopped successfully", req.Name),
		Data: map[string]string{
			"pid":    strconv.Itoa(pid),
			"name":   req.Name,
			"output": string(output),
		},
	})
}

// listRunningJFRHandler lists all running JFR recording sessions
func listRunningJFRHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		sendJSON(w, http.StatusMethodNotAllowed, Response{
			Success: false,
			Message: "Method not allowed",
		})
		return
	}

	// Get Java process PID
	pid, err := getJavaPID()
	if err != nil {
		sendJSON(w, http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to find Java process: %v", err),
		})
		return
	}

	// Check running JFR recordings
	cmd := exec.Command("jcmd", strconv.Itoa(pid), "JFR.check")
	output, err := cmd.CombinedOutput()
	if err != nil {
		sendJSON(w, http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to check JFR recordings: %v, output: %s", err, string(output)),
		})
		return
	}

	sendJSON(w, http.StatusOK, Response{
		Success: true,
		Message: "JFR recordings retrieved successfully",
		Data: map[string]string{
			"pid":    strconv.Itoa(pid),
			"output": string(output),
		},
	})
}

// listProfilesHandler lists all profile files in the directory
func listProfilesHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		sendJSON(w, http.StatusMethodNotAllowed, Response{
			Success: false,
			Message: "Method not allowed",
		})
		return
	}

	files := []map[string]interface{}{}

	err := filepath.WalkDir(profileDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if !d.IsDir() && strings.HasSuffix(d.Name(), ".jfr") {
			info, err := d.Info()
			if err != nil {
				return err
			}
			files = append(files, map[string]interface{}{
				"name":     d.Name(),
				"path":     path,
				"size":     info.Size(),
				"modified": info.ModTime().Format(time.RFC3339),
			})
		}
		return nil
	})

	if err != nil {
		sendJSON(w, http.StatusInternalServerError, Response{
			Success: false,
			Message: fmt.Sprintf("Failed to list files: %v", err),
		})
		return
	}

	sendJSON(w, http.StatusOK, Response{
		Success: true,
		Message: fmt.Sprintf("Found %d profile files", len(files)),
		Data:    files,
	})
}

// getJavaPID finds the PID of the running Java process
func getJavaPID() (int, error) {
	// Use pgrep -x to match exact process name "java" only
	// This excludes shell wrappers like "sh -c java ..."
	cmd := exec.Command("pgrep", "-x", "java")
	output, err := cmd.CombinedOutput()

	logger.Log.WithFields(map[string]interface{}{
		"output": string(output),
		"error":  err,
	}).Debug("pgrep command result")

	if err != nil {
		logger.Log.Error("Failed to find Java process")
		return 0, fmt.Errorf("no Java process found: %v", err)
	}

	pidStr := strings.TrimSpace(string(output))
	logger.Log.WithField("pidString", pidStr).Debug("PID string after trim")

	if pidStr == "" {
		return 0, fmt.Errorf("no Java process found")
	}

	// Parse the PID
	pid, err := strconv.Atoi(pidStr)
	if err != nil {
		logger.Log.WithFields(map[string]interface{}{
			"pidString": pidStr,
			"error":     err,
		}).Error("Failed to parse PID")
		return 0, fmt.Errorf("invalid PID: %v", err)
	}

	logger.Log.WithField("pid", pid).Debug("Successfully found Java PID")
	return pid, nil
}

// sendJSON sends a JSON response
func sendJSON(w http.ResponseWriter, status int, data Response) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
