package daemon

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/oscar-wu_pingcorp/profiler-sidecar/internal/logger"
	"github.com/oscar-wu_pingcorp/profiler-sidecar/internal/uploader"
)

const (
	rootProfileDir = "/tmp/jfr"       // Root HostPath directory
	scanInterval   = 30 * time.Second // Fallback periodic scan
)

// Start begins the daemon scanner
func Start() {
	bucketName := os.Getenv("GCS_BUCKET")
	if bucketName == "" {
		logger.Log.Fatal("GCS_BUCKET environment variable is required")
	}

	ctx := context.Background()

	// Initialize GCS uploader
	gcsUploader, err := uploader.NewGCSUploader(ctx, bucketName)
	if err != nil {
		logger.Log.Fatalf("Failed to initialize GCS uploader: %v", err)
	}
	defer gcsUploader.Close()

	logger.Log.Infof("Daemon scanner started. Watching %s for .jfr files", rootProfileDir)
	logger.Log.Infof("GCS bucket: %s", bucketName)

	// Create file system watcher
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		logger.Log.Fatalf("Failed to create file watcher: %v", err)
	}
	defer watcher.Close()

	// Watch the root profile directory recursively
	if err := watchDirectoryRecursive(watcher, rootProfileDir); err != nil {
		logger.Log.Fatalf("Failed to watch directory: %v", err)
	}

	// Perform initial scan of existing files
	if err := scanAndUploadExisting(ctx, gcsUploader, rootProfileDir); err != nil {
		logger.Log.Infof("Initial scan failed: %v", err)
	}

	// Start periodic scanner as fallback
	ticker := time.NewTicker(scanInterval)
	defer ticker.Stop()

	// Event loop
	for {
		select {
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			handleFileEvent(ctx, gcsUploader, event)

		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			logger.Log.Infof("Watcher error: %v", err)

		case <-ticker.C:
			// Periodic scan as fallback
			if err := scanAndUploadExisting(ctx, gcsUploader, rootProfileDir); err != nil {
				logger.Log.Infof("Periodic scan failed: %v", err)
			}
		}
	}
}

// handleFileEvent processes file system events
func handleFileEvent(ctx context.Context, uploader *uploader.GCSUploader, event fsnotify.Event) {
	// Only care about Create and Write events for .jfr files
	if !strings.HasSuffix(event.Name, ".jfr") {
		return
	}

	if event.Op&fsnotify.Remove == fsnotify.Remove {
		logger.Log.Infof("Detected file Removed: %s", event.Name)
		return
	}

	if event.Op&fsnotify.Create == fsnotify.Create || event.Op&fsnotify.Write == fsnotify.Write {
		logger.Log.Infof("Detected new/modified file: %s", event.Name)

		// Wait a bit to ensure file write is complete
		time.Sleep(5 * time.Second)

		// Process the file
		if err := processFile(ctx, uploader, event.Name); err != nil {
			logger.Log.Infof("Failed to process file %s: %v", event.Name, err)
		}
	}
}

// processFile uploads a file to GCS and deletes it locally on success
func processFile(ctx context.Context, gcsUploader *uploader.GCSUploader, filePath string) error {
	// Extract pod name from path: /tmp/jfr/{POD_NAME}/file.jfr
	relativePath, err := filepath.Rel(rootProfileDir, filePath)
	if err != nil {
		return fmt.Errorf("failed to get relative path: %w", err)
	}

	parts := strings.Split(relativePath, string(os.PathSeparator))
	if len(parts) < 2 {
		return fmt.Errorf("invalid file path structure: %s", filePath)
	}

	podName := parts[0]

	// Check if file exists and is readable
	fileInfo, err := os.Stat(filePath)
	if err != nil {
		return fmt.Errorf("file not accessible: %w", err)
	}

	if fileInfo.Size() == 0 {
		logger.Log.Infof("Skipping empty file: %s", filePath)
		return nil
	}

	// Upload to GCS
	logger.Log.Infof("Uploading file: %s (pod: %s, size: %d bytes)", filePath, podName, fileInfo.Size())

	if err := gcsUploader.Upload(ctx, filePath, podName); err != nil {
		return fmt.Errorf("upload failed: %w", err)
	}

	// Delete local file ONLY after successful upload
	logger.Log.Infof("Upload successful. Deleting local file: %s", filePath)
	if err := os.Remove(filePath); err != nil {
		return fmt.Errorf("failed to delete local file: %w", err)
	}

	logger.Log.Infof("Successfully processed and deleted: %s", filePath)
	return nil
}

// scanAndUploadExisting scans for existing .jfr files and uploads them
func scanAndUploadExisting(ctx context.Context, gcsUploader *uploader.GCSUploader, rootDir string) error {
	logger.Log.Infof("Scanning for existing .jfr files in %s", rootDir)

	return filepath.Walk(rootDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			logger.Log.Infof("Error accessing path %s: %v", path, err)
			return nil // Continue walking
		}

		if !info.IsDir() && strings.HasSuffix(info.Name(), ".jfr") {
			logger.Log.Infof("Found existing file: %s", path)
			if err := processFile(ctx, gcsUploader, path); err != nil {
				logger.Log.Infof("Failed to process existing file %s: %v", path, err)
			}
		}

		return nil
	})
}

// watchDirectoryRecursive adds the directory and all subdirectories to the watcher
func watchDirectoryRecursive(watcher *fsnotify.Watcher, root string) error {
	return filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if info.IsDir() {
			logger.Log.Infof("Watching directory: %s", path)
			if err := watcher.Add(path); err != nil {
				return fmt.Errorf("failed to watch %s: %w", path, err)
			}
		}

		return nil
	})
}
