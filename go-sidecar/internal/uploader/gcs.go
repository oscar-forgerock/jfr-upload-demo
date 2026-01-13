package uploader

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"cloud.google.com/go/storage"
	"github.com/oscar-wu_pingcorp/profiler-sidecar/internal/logger"
	"github.com/sirupsen/logrus"
)

type GCSUploader struct {
	client     *storage.Client
	bucketName string
}

// NewGCSUploader creates a new GCS uploader
func NewGCSUploader(ctx context.Context, bucketName string) (*GCSUploader, error) {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create GCS client: %w", err)
	}

	return &GCSUploader{
		client:     client,
		bucketName: bucketName,
	}, nil
}

// Upload uploads a file to GCS and returns nil on success
func (u *GCSUploader) Upload(ctx context.Context, localPath, podName string) error {
	// Open local file
	file, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("failed to open file %s: %w", localPath, err)
	}
	defer file.Close()

	// Get file info
	fileInfo, err := file.Stat()
	if err != nil {
		return fmt.Errorf("failed to get file info: %w", err)
	}

	// Wait a bit and check if file is still being written
	// (size should be stable)
	time.Sleep(2 * time.Second)
	newInfo, err := file.Stat()
	if err != nil {
		return fmt.Errorf("failed to re-check file info: %w", err)
	}

	if newInfo.Size() != fileInfo.Size() {
		return fmt.Errorf("file is still being written (size changed)")
	}

	// Construct GCS object path: {POD_NAME}/{FILENAME}
	filename := filepath.Base(localPath)
	objectPath := fmt.Sprintf("%s/%s", podName, filename)

	// Create GCS object writer
	obj := u.client.Bucket(u.bucketName).Object(objectPath)
	writer := obj.NewWriter(ctx)
	writer.ContentType = "application/octet-stream"

	// Stream file to GCS
	logger.Log.WithFields(logrus.Fields{
		"local_path": localPath,
		"gcs_path":   fmt.Sprintf("gs://%s/%s", u.bucketName, objectPath),
		"size_bytes": fileInfo.Size(),
	}).Info("Uploading file to GCS")

	bytesWritten, err := io.Copy(writer, file)
	if err != nil {
		writer.Close()
		return fmt.Errorf("failed to upload file: %w", err)
	}

	// Close the writer to finalize the upload
	if err := writer.Close(); err != nil {
		return fmt.Errorf("failed to finalize upload: %w", err)
	}

	logger.Log.WithFields(logrus.Fields{
		"bytes_written": bytesWritten,
		"gcs_path":      fmt.Sprintf("gs://%s/%s", u.bucketName, objectPath),
	}).Info("Successfully uploaded file to GCS")
	return nil
}

// Close closes the GCS client
func (u *GCSUploader) Close() error {
	return u.client.Close()
}
