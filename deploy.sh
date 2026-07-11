#!/bin/bash

# Configuration
DOCKER_REPO="madebydamo/portrait-server"
REMOTE_USER="homeserver"
REMOTE_HOST="orion"

set -e

echo "Building Docker image using docker-compose..."
docker compose build

echo "Tagging the built image..."
docker tag portrait-server $DOCKER_REPO:latest

echo "Pushing Docker image to repository..."
docker push $DOCKER_REPO:latest

echo "Manually update on your new homeserver or wait till midnight"
