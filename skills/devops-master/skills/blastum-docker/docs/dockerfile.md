# Dockerfile Patterns

## Essential Instructions

```dockerfile
FROM <image>:<tag>                        # Base image (use specific versions)
WORKDIR /app                              # Working directory
COPY package*.json ./                     # Dependencies first (caching)
RUN npm install --production              # Install dependencies
COPY . .                                  # Application code last
ENV NODE_ENV=production                   # Environment variables
EXPOSE 3000                               # Document exposed ports
USER node                                 # Non-root user (security)
CMD ["node", "server.js"]                 # Default command
```

## Multi-Stage Builds

Separate build and runtime to reduce image size:

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: Production
FROM node:20-alpine AS production
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

**Benefits**: Smaller final image, no build tools, improved security

## Layer Caching Optimization

Order matters for cache efficiency:

1. **Dependencies first** (COPY package.json, RUN npm install)
2. **Application code last** (COPY . .)
3. Code changes don't invalidate dependency layers

## Security Hardening

```dockerfile
# Use specific versions
FROM node:20.11.0-alpine3.19

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set ownership
COPY --chown=nodejs:nodejs . .

# Switch to non-root
USER nodejs
```

## .dockerignore

Exclude unnecessary files from build context:

```
node_modules
.git
.env
*.log
.DS_Store
README.md
docker-compose.yml
.dockerignore
Dockerfile
dist
coverage
```

## Language-Specific Patterns

### Node.js

```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

FROM node:20-alpine AS production
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY package*.json ./
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

### Python

```dockerfile
FROM python:3.11-slim AS build
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim AS production
WORKDIR /app
COPY --from=build /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY . .
RUN adduser --disabled-password --gecos '' appuser && \
    chown -R appuser:appuser /app
USER appuser
EXPOSE 8000
CMD ["python", "app.py"]
```

### Go

```dockerfile
FROM golang:1.21-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

FROM scratch
COPY --from=build /app/main /main
EXPOSE 8080
CMD ["/main"]
```

### Java (Spring Boot)

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN ./mvnw clean package -DskipTests

FROM eclipse-temurin:21-jre-alpine AS production
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
RUN addgroup -g 1001 -S spring && \
    adduser -S spring -u 1001
USER spring
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### Static SPA (React/Vue/Angular)

```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine AS production
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

## Health Checks

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1
```

## Build Arguments

```dockerfile
ARG VERSION=latest
ARG BUILD_DATE
LABEL version=$VERSION
LABEL build-date=$BUILD_DATE
```

Build with: `docker build --build-arg VERSION=1.0 --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')`

## Build Workflow Best Practices

**Build locally first** before deploying to remote/embedded systems:

1. **Faster iteration**: Local builds are faster than remote (especially ARM devices)
2. **Easier debugging**: Immediate feedback, better error visibility
3. **Fix compilation errors early**: Catch issues before long remote builds
4. **Test before deploy**: Verify image works locally, then transfer

**Workflow:**
```bash
# 1. Build and test locally
docker build -t myapp .
docker run -p 8080:8080 myapp

# 2. Save image for transfer
docker save myapp | gzip > myapp.tar.gz

# 3. Transfer and load on remote
scp myapp.tar.gz remote:/tmp/
ssh remote "docker load < /tmp/myapp.tar.gz"
```

**For cross-architecture builds** (e.g., macOS → Raspberry Pi):
- Build locally to debug quickly
- Use `docker buildx` for multi-arch if needed
- Or build on target if architecture differs significantly
