# Swift Vapor Deployment Strategies

## Overview

Production deployment patterns for Swift Vapor applications using Apple's container tool, covering scaling, monitoring, and operational concerns.

## Container Deployment

### Basic Production Deployment

**Resource-constrained deployment:**
```bash
container run -d \
  --name vapor-prod \
  --memory 512m \
  --cpus 1.0 \
  --restart unless-stopped \
  -p 8080:8080 \
  swift-vapor-server
```

**Health monitoring:**
```bash
# Check container health
container inspect vapor-prod | jq .State.Health.Status

# View health logs
container logs vapor-prod | grep health
```

### Environment Configuration

**Production environment variables:**
```bash
container run -d \
  -e LOG_LEVEL=info \
  -e DATABASE_URL=postgres://prod-db:5432/app \
  -e REDIS_URL=redis://cache:6379 \
  swift-vapor-server
```

**Configuration management:**
```bash
# Environment file
container run -d --env-file production.env swift-vapor-server

# Volume-mounted config
container run -d -v config:/app/config swift-vapor-server
```

## Scaling Strategies

### Horizontal Scaling

**Multiple container instances:**
```bash
# Run multiple instances
container run -d -p 8081:8080 --name app-1 swift-vapor-server
container run -d -p 8082:8080 --name app-2 swift-vapor-server
container run -d -p 8083:8080 --name app-3 swift-vapor-server

# Load balancing required
```

### Vertical Scaling

**Resource allocation:**
```bash
# Scale up resources
container run -d \
  --memory 2g \
  --cpus 2.0 \
  -p 8080:8080 \
  swift-vapor-server
```

## Monitoring & Observability

### Health Checks

**Built-in health endpoints:**
```bash
# Application health
curl http://localhost:8080/health

# Container health
container exec vapor-prod curl http://localhost:8080/health
```

### Logging Strategies

**Centralized logging:**
```bash
# Container logs
container logs -f vapor-prod

# Application logs to files
container run -d \
  -v logs:/app/logs \
  swift-vapor-server
```

### Metrics Collection

**Performance monitoring:**
```bash
# Container metrics
container stats vapor-prod

# Application metrics via endpoints
curl http://localhost:8080/metrics
```

## Backup & Recovery

### Data Persistence

**Database backups:**
```bash
# Volume snapshots
container run -d -v app-data:/app/data swift-vapor-server

# Backup volumes
container run --rm -v app-data:/data alpine tar czf - /data > backup.tar.gz
```

### Container Updates

**Rolling updates:**
```bash
# Stop old container
container stop vapor-prod

# Start new version
container run -d --name vapor-prod-v2 swift-vapor-server

# Verify health
container logs vapor-prod-v2 | grep "Server starting"

# Remove old container
container rm vapor-prod
```

## Security Hardening

### Runtime Security

**Non-root execution:**
```bash
# Verified in Containerfile
container exec vapor-prod whoami  # Should show 'vapor'
```

**Resource limits:**
```bash
container run -d \
  --memory 512m \
  --cpus 1.0 \
  --read-only \
  swift-vapor-server
```

### Network Security

**Tailscale integration:**
```bash
# Host-based security
tailscale up --auth-key=tskey-prod

# Container access via secure network
curl http://vapor-prod:8080/health
```

## Performance Optimization

### Runtime Tuning

**Swift runtime optimization:**
```bash
# Environment tuning
container run -d \
  -e SWIFT_THREADING=cooperative \
  -e SWIFT_BACKTRACE=enable=yes \
  swift-vapor-server
```

**Memory management:**
```bash
# Jemalloc tuning
container run -d \
  -e MALLOC_CONF=narenas:1,tcache:false \
  swift-vapor-server
```

## Operational Procedures

### Maintenance Windows

**Scheduled updates:**
```bash
# Graceful shutdown
container stop -t 30 vapor-prod

# Update container
container run -d --name vapor-prod-v2 swift-vapor-server

# Health verification
sleep 10
container logs vapor-prod-v2 | grep "Ready"
```

### Emergency Response

**Container failure:**
```bash
# Check status
container list

# Restart failed container
container restart vapor-prod

# Rollback if needed
container run -d --name vapor-prod-rollback swift-vapor-server:v1
```

## Cloud Deployment

### Container Registry

**Push to registry:**
```bash
# Tag for registry
container image tag swift-vapor-server registry.example.com/app:latest

# Push image
container image push registry.example.com/app:latest
```

### Orchestration

**Kubernetes deployment:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vapor-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: vapor
  template:
    spec:
      containers:
      - name: vapor
        image: swift-vapor-server
        ports:
        - containerPort: 8080
```

## Best Practices

### Deployment
1. Use health checks for reliability
2. Implement graceful shutdown
3. Configure resource limits
4. Enable restart policies

### Monitoring
1. Monitor application health
2. Collect performance metrics
3. Centralize logging
4. Set up alerts

### Security
1. Run as non-root user
2. Use read-only filesystems where possible
3. Implement network segmentation
4. Regular security updates

### Maintenance
1. Plan update strategies
2. Backup critical data
3. Test rollback procedures
4. Document procedures

## Related Topics

- Swift Vapor Build Optimization - Build-time optimization
- Performance Tuning - Runtime optimization
- Troubleshooting Guide - Issue resolution