# Docker CLI Quick Reference

Common command patterns for quick copy-paste.

## Container Operations

### Run Container

```bash
# Basic run
docker run -d --name myapp myapp:latest

# With port mapping
docker run -d --name myapp -p 8080:3000 myapp:latest

# With environment variables
docker run -d --name myapp -e NODE_ENV=production -e PORT=3000 myapp:latest

# With volume
docker run -d --name myapp -v mydata:/app/data myapp:latest

# Interactive
docker run -it --rm ubuntu:22.04 /bin/bash

# With resource limits
docker run -d --name myapp --memory=512m --cpus=0.5 myapp:latest
```

### Container Management

```bash
# Start/stop/restart
docker start myapp
docker stop myapp
docker restart myapp

# Remove
docker rm myapp
docker rm -f myapp  # Force remove running

# View logs
docker logs myapp
docker logs -f myapp  # Follow
docker logs --tail 100 myapp

# Execute command
docker exec -it myapp /bin/sh
docker exec myapp ls /app

# Inspect
docker inspect myapp
docker inspect --format='{{.NetworkSettings.IPAddress}}' myapp
```

### List Containers

```bash
# Running containers
docker ps

# All containers
docker ps -a

# Filter by name
docker ps -f "name=myapp"

# Filter by status
docker ps -f "status=exited"

# Custom format
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## Image Operations

### Build Image

```bash
# Basic build
docker build -t myapp:latest .

# With Dockerfile
docker build -f Dockerfile.prod -t myapp:prod .

# With build args
docker build --build-arg VERSION=1.0 -t myapp:1.0 .

# No cache
docker build --no-cache -t myapp:latest .

# Multi-platform
docker buildx build --platform linux/amd64,linux/arm64 -t myapp:latest .
```

### Image Management

```bash
# List images
docker images
docker images myapp

# Pull image
docker pull nginx:alpine
docker pull --platform linux/arm64 nginx:alpine

# Tag image
docker tag myapp:latest registry.example.com/myapp:1.0

# Push image
docker push registry.example.com/myapp:1.0

# Remove image
docker rmi myapp:latest
docker rmi -f myapp:latest  # Force

# Remove unused images
docker image prune
docker image prune -a  # All unused
```

## Docker Compose

### Basic Operations

```bash
# Start services
docker compose up
docker compose up -d  # Detached

# Stop services
docker compose down
docker compose down -v  # Remove volumes

# View logs
docker compose logs
docker compose logs -f web  # Follow service

# Execute command
docker compose exec web /bin/sh
docker compose run --rm web npm test

# Scale service
docker compose up -d --scale web=3
```

### Compose Management

```bash
# List services
docker compose ps

# Restart service
docker compose restart web

# Rebuild and start
docker compose up --build

# Pull images
docker compose pull

# Validate config
docker compose config
```

## Network Operations

```bash
# List networks
docker network ls

# Create network
docker network create mynet

# Connect container
docker network connect mynet myapp

# Disconnect container
docker network disconnect mynet myapp

# Inspect network
docker network inspect mynet

# Remove network
docker network rm mynet
docker network prune  # Remove unused
```

## Volume Operations

```bash
# List volumes
docker volume ls

# Create volume
docker volume create mydata

# Inspect volume
docker volume inspect mydata

# Remove volume
docker volume rm mydata
docker volume prune  # Remove unused

# Use volume
docker run -v mydata:/app/data myapp
```

## System Operations

```bash
# System info
docker info
docker version

# Disk usage
docker system df
docker system df -v

# Cleanup
docker system prune  # Unused resources
docker system prune -a  # All unused
docker system prune -a --volumes  # Include volumes

# Events
docker events
docker events --filter "type=container"
```

## Remote Management

```bash
# Create SSH context
docker context create remote --docker "host=ssh://user@host"

# Use context
docker context use remote

# List contexts
docker context ls

# Switch back
docker context use default

# Direct SSH
DOCKER_HOST=ssh://user@host docker ps
```

## Search and Discovery

```bash
# Search Docker Hub
docker search nginx

# Login to registry
docker login
docker login registry.example.com

# Logout
docker logout
```

## Monitoring

```bash
# Container stats
docker stats
docker stats myapp
docker stats --no-stream  # One-time

# Container processes
docker top myapp

# Container events
docker events --filter "container=myapp"
```

## Common Patterns

### One-liners

```bash
# Remove all stopped containers
docker container prune -f

# Remove all unused images
docker image prune -a -f

# Remove everything unused
docker system prune -a -f

# List container IPs
docker ps -q | xargs docker inspect --format '{{.Name}} {{.NetworkSettings.IPAddress}}'

# Stop all containers
docker stop $(docker ps -q)

# Remove all containers
docker rm $(docker ps -aq)

# Show disk usage by container
docker ps -q | xargs docker stats --no-stream
```

### Useful Filters

```bash
# Containers by name
docker ps -f "name=myapp"

# Containers by status
docker ps -f "status=running"
docker ps -f "status=exited"

# Containers by label
docker ps -f "label=env=prod"

# Images by reference
docker images -f "reference=myapp:*"

# Dangling images
docker images -f "dangling=true"
```

### Formatting Output

```bash
# Table format
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# JSON format
docker ps --format "{{json .}}"

# Custom format
docker ps --format "{{.Names}}: {{.Status}}"
```
