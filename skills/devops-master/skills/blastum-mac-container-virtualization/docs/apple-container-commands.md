# Apple's Container Tool Command Reference

## Overview

Complete command reference for Apple's native container tool on macOS. All commands focus on the micro-VM architecture and macOS integration.

## System Management

### System Control

```bash
# Start container system
container system start

# Stop container system
container system stop

# Restart container system
container system restart

# Check system status
container system status

# View system logs
container system logs
container system logs -f  # Follow logs
```

### Kernel Management

```bash
# Set recommended kernel (Apple Silicon)
container system kernel set --recommended

# List available kernels
container system kernel list

# Check current kernel
container system kernel current

# Set specific kernel
container system kernel set kata
container system kernel set --arch x86_64  # Intel Macs
```

## Image Management

### Building Images

```bash
# Build from Containerfile in current directory
container build -t myapp .

# Build with specific Containerfile
container build -f Containerfile.dev -t myapp:dev .

# Build with custom options
container build \
  --no-cache \
  --progress=plain \
  -t myapp:v1.0 \
  --build-arg SWIFT_VERSION=6.2 \
  .

# Build quietly
container build -q -t myapp .
```

### Image Operations

```bash
# List all images
container image list

# List images with details
container image list --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Inspect image details
container image inspect myapp

# Remove image
container image rm myapp
container image rm myapp:v1.0

# Remove unused images
container image prune

# Remove all unused images
container image prune -a
```

## Container Management

### Running Containers

```bash
# Run in foreground (development)
container run -it --rm ubuntu:latest

# Run in background
container run -d -p 8080:8080 --name web-server nginx

# Run with environment variables
container run -d \
  -e PORT=8080 \
  -e LOG_LEVEL=debug \
  --name vapor-server \
  swift-vapor-server

# Run with resource limits
container run -d \
  --memory 512m \
  --cpus 1.0 \
  -p 8080:8080 \
  swift-vapor-server

# Run with restart policy
container run -d \
  --restart unless-stopped \
  -p 8080:8080 \
  swift-vapor-server
```

### Port Mapping

```bash
# Map single port
container run -d -p 8080:8080 nginx

# Map different host port
container run -d -p 9000:8080 nginx

# Map multiple ports
container run -d \
  -p 8080:8080 \
  -p 8443:443 \
  nginx

# Map port range
container run -d -p 8080-8090:8080-8090 myapp
```

### Container Operations

```bash
# List running containers
container list

# List all containers (including stopped)
container list -a

# List with custom format
container list --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Start stopped container
container start mycontainer

# Stop running container
container stop mycontainer

# Restart container
container restart mycontainer

# Pause/unpause container
container pause mycontainer
container unpause mycontainer

# Remove container
container rm mycontainer

# Remove running container (force)
container rm -f mycontainer

# Remove all stopped containers
container rm $(container list -q)
```

## Debugging & Monitoring

### Container Logs

```bash
# View logs
container logs mycontainer

# Follow logs (real-time)
container logs -f mycontainer

# Show last N lines
container logs --tail 100 mycontainer

# Show logs since timestamp
container logs --since "2024-01-01T00:00:00" mycontainer

# Show logs with timestamps
container logs -t mycontainer
```

### Container Inspection

```bash
# Inspect container details
container inspect mycontainer

# Get specific information
container inspect mycontainer | jq .State.Status
container inspect mycontainer | jq .NetworkSettings.Ports

# Check container processes
container exec mycontainer ps aux

# Check resource usage
container stats mycontainer

# Monitor multiple containers
container stats
```

### Interactive Debugging

```bash
# Execute command in running container
container exec mycontainer ls -la

# Get interactive shell
container exec -it mycontainer bash

# Execute as specific user
container exec -it --user root mycontainer bash

# Run command and exit
container exec mycontainer apt-get update
```

## Storage Management

### Volume Operations

```bash
# Create named volume
container volume create mydata

# List volumes
container volume list

# Inspect volume
container volume inspect mydata

# Remove volume
container volume rm mydata

# Remove unused volumes
container volume prune
```

### Bind Mounts

```bash
# Mount host directory
container run -d \
  -v $HOME/data:/app/data \
  swift-vapor-server

# Read-only mount
container run -d \
  -v $HOME/config:/app/config:ro \
  swift-vapor-server

# Mount with specific permissions
container run -d \
  -v $HOME/logs:/app/logs:rw \
  swift-vapor-server
```

### Working Directory

```bash
# Set working directory
container run -d \
  --workdir /app \
  -p 8080:8080 \
  swift-vapor-server

# Mount and set working directory
container run -d \
  -v $(pwd):/app \
  --workdir /app \
  swift-vapor-server
```

## Networking

### Network Configuration

```bash
# Check port mappings
container port mycontainer

# Get container IP (internal)
container inspect mycontainer | jq .NetworkSettings.IPAddress

# Test connectivity
container exec mycontainer ping google.com

# Check network interfaces
container exec mycontainer ip addr show
```

### Hostname & DNS

```bash
# Set custom hostname
container run -d --hostname myhost swift-vapor-server

# Add extra hosts
container run -d \
  --add-host db:192.168.1.100 \
  swift-vapor-server

# Use custom DNS
container run -d \
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  swift-vapor-server
```

## Advanced Operations

### Multi-Container Management

```bash
# Start multiple containers
container run -d --name db postgres:13
container run -d --name web -p 8080:8080 --link db:db swift-vapor-server

# Check all container status
container list -a

# Stop all running containers
container stop $(container list -q)

# Clean up everything
container system prune -a --volumes
```

### Health Checks

```bash
# Run health check manually
container exec mycontainer curl http://localhost:8080/health

# Check container health status
container inspect mycontainer | jq .State.Health.Status

# View health check logs
container logs mycontainer | grep -A5 -B5 health
```

### Resource Management

```bash
# Set memory limit
container run -d --memory 1g swift-vapor-server

# Set CPU limit (cores)
container run -d --cpus 2.0 swift-vapor-server

# Set memory and swap
container run -d \
  --memory 512m \
  --memory-swap 1g \
  swift-vapor-server

# View resource usage
container stats --no-stream
```

## Swift Vapor Specific Commands

### Development Workflow

```bash
# Build Swift Vapor image
cd swift-vapor-server
container build -t vapor-dev .

# Run with source mounting
container run -d \
  -p 8080:8080 \
  -v $(pwd):/app \
  --name vapor-dev \
  vapor-dev

# View application logs
container logs -f vapor-dev

# Debug application
container exec -it vapor-dev bash
swift run  # Inside container
```

### Production Deployment

```bash
# Build production image
container build \
  --target runtime \
  -t vapor-prod .

# Run with resource limits
container run -d \
  --name vapor-prod \
  --memory 512m \
  --cpus 1.0 \
  --restart unless-stopped \
  -p 8080:8080 \
  vapor-prod

# Health monitoring
container logs -f vapor-prod
```

## Troubleshooting Commands

### System Diagnostics

```bash
# Check system health
container system status

# View system logs for errors
container system logs | grep -i error

# Check kernel logs
container system logs | grep kernel

# Restart system if unresponsive
container system restart
```

### Container Diagnostics

```bash
# Check why container stopped
container logs mycontainer

# Inspect failed container
container inspect mycontainer

# Check container exit code
container inspect mycontainer | jq .State.ExitCode

# Debug startup issues
container run -it --rm swift-vapor-server bash
```

### Network Diagnostics

```bash
# Test port availability
lsof -i :8080

# Check container networking
container exec mycontainer netstat -tlnp

# Test external connectivity
container exec mycontainer curl http://google.com

# Check DNS resolution
container exec mycontainer nslookup google.com
```

### Performance Diagnostics

```bash
# Monitor resource usage
container stats mycontainer

# Check container processes
container exec mycontainer ps aux --sort=-%cpu

# View memory usage
container exec mycontainer free -h

# Check disk usage
container exec mycontainer df -h
```

## Common Command Patterns

### Development Cycle
```bash
# Clean, build, run
container system prune -a
container build -t myapp .
container run -d -p 8080:8080 --name myapp myapp
container logs -f myapp
```

### Production Deployment
```bash
# Stop old, start new
container stop myapp
container rm myapp
container run -d -p 8080:8080 --name myapp myapp:v2.0
container logs myapp
```

### Debugging Session
```bash
# Inspect and debug
container list
container logs myapp
container exec -it myapp bash
# Debug commands...
exit
container restart myapp
```

### Cleanup Routine
```bash
# Remove stopped containers
container rm $(container list -q)

# Remove unused images
container image prune -a

# Remove unused volumes
container volume prune

# System cleanup
container system prune
```