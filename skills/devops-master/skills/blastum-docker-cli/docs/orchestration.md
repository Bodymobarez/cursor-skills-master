# Docker Orchestration Patterns

Script patterns and automation workflows for multi-step Docker operations.

## Container Lifecycle Scripts

### Start with Health Check

```bash
#!/bin/bash
# Start container and wait for health
CONTAINER="myapp"
IMAGE="myapp:latest"

docker run -d --name $CONTAINER \
  --health-cmd="curl -f http://localhost:3000/health || exit 1" \
  --health-interval=10s \
  --health-timeout=3s \
  --health-retries=3 \
  -p 8080:3000 \
  $IMAGE

# Wait for healthy status
while [ "$(docker inspect -f '{{.State.Health.Status}}' $CONTAINER)" != "healthy" ]; do
  echo "Waiting for $CONTAINER to be healthy..."
  sleep 2
done

echo "$CONTAINER is healthy"
```

### Graceful Shutdown

```bash
#!/bin/bash
# Graceful shutdown with timeout
CONTAINER="myapp"
TIMEOUT=30

docker stop -t $TIMEOUT $CONTAINER || docker kill $CONTAINER
docker rm $CONTAINER
```

### Restart with Cleanup

```bash
#!/bin/bash
# Restart container, removing old one if exists
CONTAINER="myapp"
IMAGE="myapp:latest"

[ "$(docker ps -aq -f name=$CONTAINER)" ] && docker rm -f $CONTAINER
docker run -d --name $CONTAINER -p 8080:3000 $IMAGE
```

## Multi-Container Orchestration

### Sequential Startup with Dependencies

```bash
#!/bin/bash
# Start services in order: db -> redis -> app

# Start database
docker run -d --name db \
  -e POSTGRES_PASSWORD=secret \
  -v db_data:/var/lib/postgresql/data \
  postgres:15-alpine

# Wait for database
until docker exec db pg_isready -U postgres; do
  echo "Waiting for database..."
  sleep 2
done

# Start Redis
docker run -d --name redis redis:7-alpine

# Wait for Redis
until docker exec redis redis-cli ping; do
  echo "Waiting for Redis..."
  sleep 1
done

# Start application
docker run -d --name app \
  --link db:db \
  --link redis:redis \
  -e DATABASE_URL=postgresql://postgres:secret@db:5432/mydb \
  -p 8080:3000 \
  myapp:latest
```

### Network-Based Service Discovery

```bash
#!/bin/bash
# Create network and start services
NETWORK="app-network"

docker network create $NETWORK

docker run -d --name db --network $NETWORK \
  -e POSTGRES_PASSWORD=secret \
  postgres:15-alpine

docker run -d --name redis --network $NETWORK \
  redis:7-alpine

docker run -d --name app --network $NETWORK \
  -e DATABASE_URL=postgresql://postgres:secret@db:5432/mydb \
  -e REDIS_URL=redis://redis:6379 \
  -p 8080:3000 \
  myapp:latest
```

## Image Build and Deploy Workflows

### Build and Push Pipeline

```bash
#!/bin/bash
# Build, tag, and push image
IMAGE="myapp"
VERSION="${1:-latest}"
REGISTRY="registry.example.com"

# Build
docker build -t $IMAGE:$VERSION .
docker build -t $IMAGE:latest .

# Tag for registry
docker tag $IMAGE:$VERSION $REGISTRY/$IMAGE:$VERSION
docker tag $IMAGE:latest $REGISTRY/$IMAGE:latest

# Push
docker push $REGISTRY/$IMAGE:$VERSION
docker push $REGISTRY/$IMAGE:latest
```

### Multi-Platform Build

```bash
#!/bin/bash
# Build for multiple platforms
IMAGE="myapp"
VERSION="1.0.0"
REGISTRY="registry.example.com"

docker buildx create --use --name multiplatform || docker buildx use multiplatform

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t $REGISTRY/$IMAGE:$VERSION \
  -t $REGISTRY/$IMAGE:latest \
  --push \
  .
```

### Build with Cache

```bash
#!/bin/bash
# Build with registry cache
IMAGE="myapp"
REGISTRY="registry.example.com"

docker buildx build \
  --cache-from type=registry,ref=$REGISTRY/$IMAGE:buildcache \
  --cache-to type=registry,ref=$REGISTRY/$IMAGE:buildcache,mode=max \
  -t $IMAGE:latest \
  --load \
  .
```

## Backup and Restore Patterns

### Volume Backup

```bash
#!/bin/bash
# Backup named volume
VOLUME="app_data"
BACKUP_FILE="backup-$(date +%Y%m%d-%H%M%S).tar.gz"

docker run --rm \
  -v $VOLUME:/data \
  -v $(pwd):/backup \
  alpine \
  tar czf /backup/$BACKUP_FILE /data

echo "Backup created: $BACKUP_FILE"
```

### Volume Restore

```bash
#!/bin/bash
# Restore volume from backup
VOLUME="app_data"
BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <backup-file>"
  exit 1
fi

docker run --rm \
  -v $VOLUME:/data \
  -v $(pwd):/backup \
  alpine \
  tar xzf /backup/$BACKUP_FILE -C /
```

### Container State Backup

```bash
#!/bin/bash
# Export container filesystem
CONTAINER="myapp"
BACKUP_FILE="container-$(date +%Y%m%d-%H%M%S).tar"

docker export $CONTAINER > $BACKUP_FILE
echo "Container exported: $BACKUP_FILE"
```

## Monitoring and Health Checks

### Container Health Monitoring

```bash
#!/bin/bash
# Monitor container health status
CONTAINER="myapp"

while true; do
  STATUS=$(docker inspect -f '{{.State.Health.Status}}' $CONTAINER 2>/dev/null)
  if [ "$STATUS" != "healthy" ]; then
    echo "$(date): $CONTAINER is $STATUS"
    docker logs --tail 20 $CONTAINER
  fi
  sleep 30
done
```

### Resource Usage Alert

```bash
#!/bin/bash
# Alert on high resource usage
CONTAINER="myapp"
CPU_THRESHOLD=80
MEM_THRESHOLD=80

STATS=$(docker stats --no-stream --format "{{.CPUPerc}}\t{{.MemPerc}}" $CONTAINER)
CPU=$(echo $STATS | cut -f1 | sed 's/%//')
MEM=$(echo $STATS | cut -f2 | sed 's/%//')

if (( $(echo "$CPU > $CPU_THRESHOLD" | bc -l) )); then
  echo "ALERT: CPU usage at ${CPU}%"
fi

if (( $(echo "$MEM > $MEM_THRESHOLD" | bc -l) )); then
  echo "ALERT: Memory usage at ${MEM}%"
fi
```

## Cleanup Automation

### Prune Unused Resources

```bash
#!/bin/bash
# Clean up unused Docker resources
# Remove stopped containers older than 24 hours
docker container prune -f --filter "until=24h"

# Remove dangling images
docker image prune -f

# Remove unused volumes (careful!)
# docker volume prune -f

# Remove unused networks
docker network prune -f

# Full system cleanup (interactive)
# docker system prune -a
```

### Selective Cleanup

```bash
#!/bin/bash
# Remove containers by label
docker container prune -f --filter "label=env=test"

# Remove images by pattern
docker images | grep "myapp" | grep -v "latest" | awk '{print $3}' | xargs docker rmi

# Remove volumes not attached to containers
docker volume ls -q | xargs -r docker volume inspect | \
  grep -B 5 '"Mountpoint"' | grep -v '"Mountpoint"' | \
  grep -v '^--$' | awk '{print $2}' | tr -d '",' | \
  xargs -r docker volume rm
```

## Deployment Scripts

### Rolling Update

```bash
#!/bin/bash
# Rolling update without downtime
SERVICE="myapp"
NEW_IMAGE="myapp:2.0"
OLD_CONTAINER="${SERVICE}-old"
NEW_CONTAINER="${SERVICE}-new"

# Start new container
docker run -d --name $NEW_CONTAINER \
  --network app-network \
  -p 8081:3000 \
  $NEW_IMAGE

# Health check new container
until curl -f http://localhost:8081/health; do
  sleep 2
done

# Switch traffic (update load balancer config or use nginx)
# Then stop old container
docker stop $OLD_CONTAINER
docker rm $OLD_CONTAINER

# Rename new container
docker rename $NEW_CONTAINER $SERVICE
```

### Blue-Green Deployment

```bash
#!/bin/bash
# Blue-green deployment pattern
APP="myapp"
VERSION="$1"
BLUE="${APP}-blue"
GREEN="${APP}-green"

# Determine current color
if docker ps -q -f name=$BLUE | grep -q .; then
  CURRENT=$BLUE
  NEW=$GREEN
else
  CURRENT=$GREEN
  NEW=$BLUE
fi

# Start new version
docker run -d --name $NEW \
  --network app-network \
  -p 8080:3000 \
  ${APP}:${VERSION}

# Health check
until docker exec $NEW curl -f http://localhost:3000/health; do
  sleep 2
done

# Stop old version
docker stop $CURRENT
docker rm $CURRENT

echo "Deployed $NEW"
```

## Compose-Based Orchestration

### Compose with Environment Overrides

```bash
#!/bin/bash
# Deploy with environment-specific compose files
ENV="${1:-dev}"

docker compose -f docker-compose.yml \
  -f docker-compose.${ENV}.yml \
  up -d

docker compose -f docker-compose.yml \
  -f docker-compose.${ENV}.yml \
  ps
```

### Compose Scale and Update

```bash
#!/bin/bash
# Scale service and perform rolling update
SERVICE="web"
REPLICAS=3

# Scale up
docker compose up -d --scale $SERVICE=$REPLICAS

# Update images
docker compose pull $SERVICE
docker compose up -d --no-deps $SERVICE
```

## Error Handling Patterns

### Retry Logic

```bash
#!/bin/bash
# Retry Docker command with exponential backoff
MAX_RETRIES=5
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
  if docker run --rm alpine echo "test"; then
    echo "Success"
    exit 0
  fi
  
  RETRY=$((RETRY + 1))
  SLEEP=$((2 ** RETRY))
  echo "Retry $RETRY/$MAX_RETRIES in ${SLEEP}s..."
  sleep $SLEEP
done

echo "Failed after $MAX_RETRIES attempts"
exit 1
```

### Validation Before Operations

```bash
#!/bin/bash
# Validate container exists and is running
CONTAINER="myapp"

if ! docker ps -q -f name=$CONTAINER | grep -q .; then
  echo "Error: Container $CONTAINER is not running"
  exit 1
fi

# Proceed with operation
docker exec $CONTAINER /app/backup.sh
```
