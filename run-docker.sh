#!/bin/bash

# Build and run Hugo blog with Docker

echo "Building Docker image..."
#docker build -t myblog-hugo .
docker build --build-arg ENABLED_MODULES="headers-more" -t myblog-hugo .

echo "Running container on port 80..."
#docker run -d --name myblog-hugo -p 80:80 myblog-hugo
docker run -d --name myblog-hugo -p 80:80 --rm myblog-hugo

echo "Blog is now running at http://localhost:80"
echo "To stop the container, run: docker stop myblog-hugo"
