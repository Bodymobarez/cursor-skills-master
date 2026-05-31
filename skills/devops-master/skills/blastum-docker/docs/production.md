# Production Deployment Patterns

## Production Checklist

- ✅ Use specific image versions (not `latest`)
- ✅ Run as non-root user
- ✅ Multi-stage builds to minimize image size
- ✅ Health checks implemented
- ✅ Resource limits configured
- ✅ Restart policy set
- ✅ Logging configured
- ✅ Secrets managed securely (not in environment variables)
- ✅ Vulnerability scanning (Docker Scout)
- ✅ Read-only root filesystem when possible
- ✅ Network segmentation
- ✅ Regular image updates

## Security Best Practices

### Image Security Checklist

- ✅ Start with minimal base images (Alpine, Distroless)
- ✅ Use specific versions, not `latest`
- ✅ Scan for vulnerabilities regularly
- ✅ Run as non-root user
- ✅ Don't include secrets in images (use runtime secrets)
- ✅ Minimize attack surface (only install needed packages)
- ✅ Use multi-stage builds (no build tools in final image)
- ✅ Sign and verify images
- ✅ Keep images updated

### Container Security

**Dockerfile**:
```dockerfile
# Non-root user
RUN adduser -D appuser
USER appuser

# Read-only root filesystem (requires runtime flag)
# Runtime: docker run --read-only -v /tmp --tmpfs /run myapp
```

**Runtime security** (use docker-cli skill for commands):
- Read-only root filesystem: `--read-only`
- Drop capabilities: `--cap-drop=ALL --cap-add=NET_BIND_SERVICE`
- No new privileges: `--security-opt=no-new-privileges`
- Resource limits: `--memory=512m --cpus=0.5 --pids-limit=100`

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Docker Build and Push

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: user/app:latest,user/app:${{ github.sha }}
          cache-from: type=registry,ref=user/app:buildcache
          cache-to: type=registry,ref=user/app:buildcache,mode=max

      - name: Run vulnerability scan
        uses: docker/scout-action@v1
        with:
          command: cves
          image: user/app:${{ github.sha }}
```

## Recommended Base Images

| Language/Framework | Recommended Base |
|-------------------|------------------|
| Node.js | `node:20-alpine` |
| Python | `python:3.11-slim` |
| Java | `eclipse-temurin:21-jre-alpine` |
| Go | `scratch` (for compiled binary) |
| .NET | `mcr.microsoft.com/dotnet/aspnet:8.0-alpine` |
| PHP | `php:8.2-fpm-alpine` |
| Ruby | `ruby:3.2-alpine` |
| Static sites | `nginx:alpine` |

## Additional Resources

- **Official Documentation**: https://docs.docker.com
- **Docker Hub**: https://hub.docker.com
- **Best Practices**: https://docs.docker.com/develop/dev-best-practices/
- **Security**: https://docs.docker.com/engine/security/
- **Dockerfile Reference**: https://docs.docker.com/engine/reference/builder/
- **Compose Specification**: https://docs.docker.com/compose/compose-file/
