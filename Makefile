.PHONY: help build-java build-go build-all clean-java clean-go clean-all deploy-java deploy-go deploy-all redeploy-java redeploy-go redeploy-all delete-java delete-go delete-all test-health test-create test-running test-stop test-list test-all

# Default target
help:
	@echo "Available targets:"
	@echo ""
	@echo "Build targets:"
	@echo "  build-java       - Build Java application Docker image"
	@echo "  build-go         - Build Go sidecar Docker image"
	@echo "  build-all        - Build both Java and Go Docker images"
	@echo ""
	@echo "Deploy targets:"
	@echo "  deploy-java      - Deploy Java StatefulSet"
	@echo "  deploy-go        - Deploy Go DaemonSet"
	@echo "  deploy-all       - Deploy both Java and Go applications"
	@echo "  redeploy-java    - Rebuild and redeploy Java application"
	@echo "  redeploy-go      - Rebuild and redeploy Go sidecar"
	@echo "  redeploy-all     - Rebuild and redeploy all applications"
	@echo "  delete-java      - Delete Java StatefulSet"
	@echo "  delete-go        - Delete Go DaemonSet"
	@echo "  delete-all       - Delete all deployments"
	@echo ""
	@echo "Clean targets:"
	@echo "  clean-java       - Clean Java build artifacts"
	@echo "  clean-go         - Clean Go build artifacts"
	@echo "  clean-all        - Clean all build artifacts"
	@echo ""
	@echo "Test targets:"
	@echo "  test-health      - Test API health endpoint"
	@echo "  test-create      - Create a JFR profile (duration=30s)"
	@echo "  test-running     - List running JFR profiles"
	@echo "  test-stop        - Stop a JFR profile (requires NAME=<recording-name>)"
	@echo "  test-list        - List profile files"
	@echo "  test-all         - Run all API tests"

# Build Java application
build-java:
	@echo "Switching to Minikube Docker daemon..."
	@eval $$(minikube docker-env) && \
	echo "Deleting old Java image from Minikube (if exists)..." && \
	docker rmi -f profiler-app:latest 2>/dev/null || true && \
	echo "Building Java application in Minikube..." && \
	cd java-app && docker build --no-cache -t profiler-app:latest .
	@echo "Java application built successfully!"

# Build Go sidecar
build-go:
	@echo "Switching to Minikube Docker daemon..."
	@eval $$(minikube docker-env) && \
	echo "Deleting old Go sidecar image from Minikube (if exists)..." && \
	docker rmi -f profiler-sidecar:latest 2>/dev/null || true && \
	echo "Building Go sidecar in Minikube..." && \
	cd go-sidecar && docker build -t profiler-sidecar:latest .
	@echo "Go sidecar built successfully!"

# Build both applications
build-all: build-java build-go
	@echo "All applications built successfully!"

# Clean Java artifacts
clean-java:
	@echo "Cleaning Java build artifacts..."
	cd java-app && rm -rf build .gradle
	@echo "Java artifacts cleaned!"

# Clean Go artifacts
clean-go:
	@echo "Cleaning Go build artifacts..."
	cd go-sidecar && go clean
	@echo "Go artifacts cleaned!"

# Clean all artifacts
clean-all: clean-java clean-go
	@echo "All artifacts cleaned!"

# Test API health
test-health:
	@./infra/scripts/test-jfr-api.sh health

# Create a JFR profile
test-create:
	@./infra/scripts/test-jfr-api.sh create 30s test-profile.jfr

# List running JFR profiles
test-running:
	@./infra/scripts/test-jfr-api.sh running

# Stop a JFR profile (requires NAME variable)
test-stop:
	@if [ -z "$(NAME)" ]; then \
		echo "Error: NAME variable is required. Usage: make test-stop NAME='Recording 1'"; \
		exit 1; \
	fi
	@./infra/scripts/test-jfr-api.sh stop "$(NAME)"

# List profile files
test-list:
	@./infra/scripts/test-jfr-api.sh list

# Run all API tests
test-all:
	@./infra/scripts/test-jfr-api.sh all

# Deploy Java StatefulSet
deploy-java:
	@echo "Deploying Java StatefulSet..."
	kubectl apply -f infra/java/statefulSet.yaml
	@echo "Java StatefulSet deployed!"

# Deploy Go DaemonSet
deploy-go:
	@echo "Deploying Go DaemonSet..."
	kubectl apply -f infra/go/daemonset.yaml
	@echo "Go DaemonSet deployed!"

# Deploy all applications
deploy-all: deploy-java deploy-go
	@echo "All applications deployed!"

# Delete Java StatefulSet
delete-java:
	@echo "Deleting Java StatefulSet..."
	kubectl delete statefulset java-jfr-with-sidecar --ignore-not-found=true
	@echo "Java StatefulSet deleted!"

# Delete Go DaemonSet
delete-go:
	@echo "Deleting Go DaemonSet..."
	kubectl delete daemonset profiler-daemon --ignore-not-found=true
	@echo "Go DaemonSet deleted!"

# Delete all deployments
delete-all: delete-java delete-go
	@echo "All deployments deleted!"

# Rebuild and redeploy Java application
redeploy-java: build-java delete-java
	@echo "Waiting for pod termination..."
	@sleep 3
	@$(MAKE) deploy-java
	@echo "Java application redeployed!"

# Rebuild and redeploy Go sidecar
redeploy-go: build-go delete-java delete-go
	@echo "Waiting for pod termination..."
	@sleep 3
	@$(MAKE) deploy-all
	@echo "Go sidecar redeployed!"

# Rebuild and redeploy all applications
redeploy-all: build-all delete-all
	@echo "Waiting for pod termination..."
	@sleep 3
	@$(MAKE) deploy-all
	@echo "All applications redeployed!"
