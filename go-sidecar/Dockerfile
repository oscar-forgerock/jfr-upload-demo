# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum* ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build statically linked binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o profiler-sidecar ./cmd/main.go

# Runtime stage - use same base image as Java app
FROM openjdk:26-ea-17-jdk-trixie

WORKDIR /app

# Install runtime dependencies
# - procps: for pgrep to find Java process
# - ca-certificates: for HTTPS connections to GCS
# - python3, python3-pip: required for gcloud CLI
# - bash, curl: required for gcloud CLI
# Note: JDK (including jcmd) is already available in the base image
#RUN apt-get update && apt-get install -y \
#    procps \
#    ca-certificates \
#    python3 \
#    python3-pip \
#    bash \
#    curl \
#    && rm -rf /var/lib/apt/lists/*

## Install gcloud CLI
#RUN curl -o /tmp/google-cloud-sdk.tar.gz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz && \
#    tar -xzf /tmp/google-cloud-sdk.tar.gz -C /opt && \
#    /opt/google-cloud-sdk/install.sh  --path-update=true && \
#    rm /tmp/google-cloud-sdk.tar.gz

# Add gcloud to PATH
#ENV PATH="/opt/google-cloud-sdk/bin:${PATH}"

# Copy binary from builder
COPY --from=builder /app/profiler-sidecar /app/profiler-sidecar

# Make binary executable and create directories
RUN chmod +x /app/profiler-sidecar && \
    mkdir -p /tmp/jfr \

USER 111111

# Default entrypoint (mode must be specified as argument)
ENTRYPOINT ["/app/profiler-sidecar"]
