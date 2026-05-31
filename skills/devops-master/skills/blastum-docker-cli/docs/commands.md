# Docker CLI Commands Reference

Complete command reference organized by category. Use `docker COMMAND --help` for detailed options.

## Container Management

### Lifecycle

```bash
# Create and run
docker run [OPTIONS] IMAGE [COMMAND] [ARG...]
docker run -d --name myapp -p 8080:3000 myapp:latest
docker run -it --rm ubuntu:22.04 /bin/bash

# Create without starting
docker create [OPTIONS] IMAGE [COMMAND] [ARG...]

# Start/stop/restart
docker start [OPTIONS] CONTAINER [CONTAINER...]
docker stop [OPTIONS] CONTAINER [CONTAINER...]
docker restart [OPTIONS] CONTAINER [CONTAINER...]

# Remove
docker rm [OPTIONS] CONTAINER [CONTAINER...]
docker rm -f CONTAINER  # Force remove running container
```

### Common Run Options

```bash
-d, --detach                    # Run in background
--name NAME                     # Container name
-p, --publish HOST:CONTAINER    # Port mapping
-e, --env KEY=VALUE             # Environment variable
-v, --volume HOST:CONTAINER      # Volume mount
--network NETWORK               # Network
--restart POLICY                # Restart policy (no, always, unless-stopped, on-failure)
--memory LIMIT                  # Memory limit
--cpus DECIMAL                  # CPU limit
-it                             # Interactive TTY
--rm                            # Auto-remove on exit
--read-only                     # Read-only root filesystem
--user UID:GID                  # Run as user
```

### Inspection and Debugging

```bash
# List containers
docker ps                       # Running containers
docker ps -a                    # All containers
docker ps --filter "status=exited"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Logs
docker logs [OPTIONS] CONTAINER
docker logs -f CONTAINER         # Follow logs
docker logs --tail 100 CONTAINER # Last 100 lines
docker logs --since 1h CONTAINER # Since time

# Execute commands
docker exec [OPTIONS] CONTAINER COMMAND [ARG...]
docker exec -it CONTAINER /bin/sh
docker exec CONTAINER ls /app

# Inspect
docker inspect [OPTIONS] CONTAINER|IMAGE|NETWORK|VOLUME
docker inspect --format='{{.NetworkSettings.IPAddress}}' CONTAINER

# Stats and processes
docker stats [OPTIONS] [CONTAINER...]
docker stats --no-stream        # One-time stats
docker top CONTAINER             # Container processes

# Filesystem changes
docker diff CONTAINER            # Show filesystem changes
docker cp CONTAINER:SRC DEST     # Copy from container
docker cp SRC CONTAINER:DEST     # Copy to container
```

### Container Commands (Management Group)

```bash
docker container ls              # List containers
docker container start CONTAINER
docker container stop CONTAINER
docker container restart CONTAINER
docker container rm CONTAINER
docker container prune           # Remove stopped containers
docker container inspect CONTAINER
docker container logs CONTAINER
docker container exec CONTAINER COMMAND
docker container stats CONTAINER
docker container top CONTAINER
docker container update [OPTIONS] CONTAINER  # Update resource limits
```

## Image Management

### Building

```bash
# Build image
docker build [OPTIONS] PATH | URL | -
docker build -t NAME:TAG .
docker build -f Dockerfile.prod -t myapp:prod .
docker build --build-arg KEY=VALUE -t myapp:latest .
docker build --no-cache -t myapp:latest .  # No cache
docker build --target STAGE -t myapp:dev . # Build specific stage

# Buildx (advanced builds)
docker buildx build [OPTIONS] PATH | URL | -
docker buildx build --platform linux/amd64,linux/arm64 -t myapp:latest .
docker buildx build --load -t myapp:latest .  # Load to local
docker buildx build --push -t registry/myapp:latest .  # Push to registry
```

### Image Operations

```bash
# List images
docker images                    # List all images
docker images --filter "dangling=true"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# Pull/Push
docker pull [OPTIONS] NAME[:TAG|@DIGEST]
docker pull --platform linux/arm64 nginx:alpine
docker push [OPTIONS] NAME[:TAG]
docker push registry.example.com/myapp:1.0

# Tag
docker tag SOURCE_IMAGE[:TAG] TARGET_IMAGE[:TAG]
docker tag myapp:latest registry.example.com/myapp:1.0

# Remove
docker rmi [OPTIONS] IMAGE [IMAGE...]
docker rmi -f IMAGE              # Force remove
docker image prune               # Remove dangling images
docker image prune -a            # Remove all unused images

# Inspect
docker inspect IMAGE
docker history IMAGE             # Show image layers
docker image inspect IMAGE

# Save/Load
docker save [OPTIONS] IMAGE [IMAGE...]
docker save -o myapp.tar myapp:latest
docker load [OPTIONS]
docker load -i myapp.tar

# Import/Export
docker import [OPTIONS] file|URL|- [REPOSITORY[:TAG]]
docker export [OPTIONS] CONTAINER
docker export -o container.tar CONTAINER
```

### Image Commands (Management Group)

```bash
docker image ls                   # List images
docker image pull IMAGE
docker image push IMAGE
docker image rm IMAGE
docker image prune               # Remove unused
docker image inspect IMAGE
docker image history IMAGE
docker image tag SOURCE TARGET
docker image save IMAGE -o file.tar
docker image load -i file.tar
```

## Docker Compose

### Basic Operations

```bash
# Start/Stop
docker compose up [OPTIONS]
docker compose up -d             # Detached mode
docker compose up --build        # Build before starting
docker compose up --scale SERVICE=N  # Scale service
docker compose down [OPTIONS]
docker compose down -v           # Remove volumes

# Management
docker compose start [SERVICE...]
docker compose stop [SERVICE...]
docker compose restart [SERVICE...]
docker compose pause [SERVICE...]
docker compose unpause [SERVICE...]

# Status
docker compose ps                # List containers
docker compose top [SERVICE...]  # Show processes
docker compose logs [OPTIONS] [SERVICE...]
docker compose logs -f SERVICE   # Follow logs
docker compose logs --tail=100 SERVICE

# Execution
docker compose exec [OPTIONS] SERVICE COMMAND [ARG...]
docker compose exec -it web /bin/sh
docker compose run [OPTIONS] SERVICE [COMMAND] [ARG...]  # One-off command
docker compose run --rm web npm test

# Build
docker compose build [OPTIONS] [SERVICE...]
docker compose build --no-cache SERVICE
docker compose pull [SERVICE...] # Pull images
docker compose push [SERVICE...]  # Push images
```

### Compose Options

```bash
-f, --file FILE                  # Compose file (can specify multiple)
-p, --project-name NAME          # Project name
--profile PROFILE                 # Profile to enable
--env-file FILE                  # Environment file
--project-directory DIR          # Working directory
```

### Compose Utilities

```bash
docker compose config            # Validate and show config
docker compose config --services # List services
docker compose config --volumes  # List volumes
docker compose ps                # Container status
docker compose port SERVICE PRIVATE_PORT  # Public port mapping
docker compose images            # List images
docker compose volumes           # List volumes
docker compose events            # Real-time events
docker compose wait [SERVICE...] # Wait for services
docker compose watch             # Watch and rebuild
```

## Network Management

### Network Operations

```bash
# List networks
docker network ls
docker network ls --filter "driver=bridge"

# Create network
docker network create [OPTIONS] NETWORK
docker network create --driver bridge mynet
docker network create --subnet 172.20.0.0/16 mynet
docker network create --driver overlay myoverlay  # Swarm

# Inspect
docker network inspect [OPTIONS] NETWORK [NETWORK...]
docker network inspect --format='{{range .Containers}}{{.Name}} {{end}}' NETWORK

# Connect/Disconnect
docker network connect [OPTIONS] NETWORK CONTAINER
docker network disconnect [OPTIONS] NETWORK CONTAINER

# Remove
docker network rm NETWORK [NETWORK...]
docker network prune            # Remove unused networks
```

### Network Types

```bash
# Bridge (default)
docker network create --driver bridge mybridge

# Host (no isolation)
docker run --network host nginx

# None (no network)
docker run --network none alpine

# Overlay (multi-host)
docker network create --driver overlay myoverlay

# MACVLAN (L2 access)
docker network create --driver macvlan --subnet=192.168.1.0/24 --gateway=192.168.1.1 -o parent=eth0 mymacvlan
```

## Volume Management

### Volume Operations

```bash
# List volumes
docker volume ls
docker volume ls --filter "dangling=true"

# Create volume
docker volume create [OPTIONS] [VOLUME]
docker volume create --name mydata
docker volume create --driver local --opt type=none --opt device=/path --opt o=bind mydata

# Inspect
docker volume inspect [OPTIONS] VOLUME [VOLUME...]
docker volume inspect --format='{{.Mountpoint}}' mydata

# Remove
docker volume rm VOLUME [VOLUME...]
docker volume prune            # Remove unused volumes
```

### Volume Usage

```bash
# Named volume
docker run -v mydata:/app/data myapp

# Bind mount
docker run -v /host/path:/container/path myapp
docker run -v /host/path:/container/path:ro myapp  # Read-only

# tmpfs (memory)
docker run --tmpfs /tmp myapp
docker run --tmpfs /tmp:rw,noexec,nosuid,size=100m myapp
```

## System Management

### System Commands

```bash
# System information
docker system info              # Docker daemon info
docker system df                # Disk usage
docker system df -v             # Verbose disk usage
docker system events            # Real-time events
docker system events --filter "type=container"

# Cleanup
docker system prune [OPTIONS]
docker system prune -a          # Remove all unused resources
docker system prune -a --volumes # Include volumes
```

### Builder Management

```bash
# Buildx builders
docker buildx ls                 # List builders
docker buildx create --name mybuilder --use  # Create and use
docker buildx use mybuilder      # Switch builder
docker buildx inspect mybuilder  # Inspect builder
docker buildx rm mybuilder       # Remove builder
docker buildx prune              # Remove build cache
docker buildx du                 # Disk usage
```

### Context Management

```bash
# List contexts
docker context ls

# Create remote context
docker context create REMOTE --docker "host=ssh://user@host"
docker context create REMOTE --docker "host=tcp://host:2376"

# Use context
docker context use REMOTE
docker context show              # Current context
docker context inspect REMOTE    # Inspect context

# Remove context
docker context rm REMOTE
```

## Utility Commands

### Search and Login

```bash
# Search Docker Hub
docker search [OPTIONS] TERM
docker search --limit 10 nginx

# Registry login
docker login [OPTIONS] [SERVER]
docker login -u USERNAME
docker login registry.example.com
docker logout [SERVER]
```

### Version and Info

```bash
docker version                   # Client and server version
docker info                     # System-wide information
docker info --format '{{.OperatingSystem}}'
```

### Events and Monitoring

```bash
# Events stream
docker events [OPTIONS]
docker events --filter "type=container"
docker events --filter "container=myapp"
docker events --since "2024-01-01T00:00:00"
docker events --until "2024-01-02T00:00:00"
```

## Filtering and Formatting

### Filters

```bash
# Container filters
--filter "name=myapp"
--filter "status=running"
--filter "status=exited"
--filter "label=env=prod"
--filter "ancestor=nginx:alpine"

# Image filters
--filter "dangling=true"
--filter "reference=myapp:*"
--filter "before=myapp:1.0"
--filter "since=myapp:1.0"

# Network filters
--filter "driver=bridge"
--filter "type=custom"
```

### Formatting

```bash
# Go template formatting
--format "{{.ID}}\t{{.Names}}\t{{.Status}}"
--format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
--format "json"                  # JSON output
--format "{{json .}}"           # JSON for single object
```

## Command Aliases

Many commands have shorter aliases:

```bash
docker ps = docker container ls
docker images = docker image ls
docker rmi = docker image rm
docker rm = docker container rm
docker build = docker buildx build (with BuildKit)
```
