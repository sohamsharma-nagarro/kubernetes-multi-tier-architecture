#!/bin/bash

# Docker Image Build and Push Script
# Builds Docker images and pushes them to Docker Hub

set -e

DOCKER_USERNAME=${1:-sohamsharma}
DOCKER_REGISTRY="${DOCKER_USERNAME}/py-api-service"
IMAGE_TAG=${2:-latest}
API_DIR="./api"

echo "🐳 Docker Image Build and Push"
echo ""
echo "Registry: $DOCKER_REGISTRY"
echo "Tag: $IMAGE_TAG"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check Docker daemon
echo "Checking Docker daemon..."
if ! docker ps &>/dev/null; then
    echo "❌ Docker daemon is not running. Please start Docker."
    exit 1
fi
echo "✅ Docker daemon is running"
echo ""

# Build API image
echo "📦 Building API Service image..."
echo "  - Dockerfile: $API_DIR/Dockerfile"
echo "  - Context: $API_DIR"
docker build -t "$DOCKER_REGISTRY:$IMAGE_TAG" "$API_DIR"
echo "✅ API image built successfully"
echo ""

# Tag with latest
if [ "$IMAGE_TAG" != "latest" ]; then
    echo "📌 Tagging image as latest..."
    docker tag "$DOCKER_REGISTRY:$IMAGE_TAG" "$DOCKER_REGISTRY:latest"
    echo "✅ Image tagged as latest"
    echo ""
fi

# Display image info
echo "📋 Image Information:"
docker images | grep "$DOCKER_USERNAME/py-api-service" | head -2
echo ""

# Check if user is logged in
echo "🔐 Checking Docker Hub authentication..."
if docker info | grep -q "Username"; then
    echo "✅ Authenticated with Docker Hub"
else
    echo "❌ Not authenticated with Docker Hub"
    echo ""
    echo "Please log in to Docker Hub:"
    echo "  docker login -u $DOCKER_USERNAME"
    echo ""
    read -p "Have you logged in? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting without pushing images."
        exit 1
    fi
fi

# Push images
echo ""
echo "📤 Pushing images to Docker Hub..."
echo "   Pushing $DOCKER_REGISTRY:$IMAGE_TAG..."
docker push "$DOCKER_REGISTRY:$IMAGE_TAG"
echo "✅ Image $DOCKER_REGISTRY:$IMAGE_TAG pushed successfully"

if [ "$IMAGE_TAG" != "latest" ]; then
    echo "   Pushing $DOCKER_REGISTRY:latest..."
    docker push "$DOCKER_REGISTRY:latest"
    echo "✅ Image $DOCKER_REGISTRY:latest pushed successfully"
fi

echo ""
echo "🎉 Docker images pushed to Docker Hub successfully!"
echo ""
echo "Images available at:"
echo "  - $DOCKER_REGISTRY:$IMAGE_TAG"
if [ "$IMAGE_TAG" != "latest" ]; then
    echo "  - $DOCKER_REGISTRY:latest"
fi
echo ""
echo "To use these images in Kubernetes deployments, update the image:"
echo "  image: $DOCKER_REGISTRY:$IMAGE_TAG"
echo ""
