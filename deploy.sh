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

echo "Recreating services on the remote server..."
ssh -T "${REMOTE_USER}@${REMOTE_HOST}" <<EOF
cd /home/homeserver/docker
docker pull $DOCKER_REPO:latest
docker tag $DOCKER_REPO:latest portrait-server
docker-compose up -d --remove-orphans
EOF

echo "Deployment completed successfully."
