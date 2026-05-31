# Docker Compose Configuration

## Basic Structure

```yaml
services:
  web:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://user:pass@db:5432/app
    depends_on:
      - db
      - redis
    volumes:
      - ./src:/app/src      # Development: live code reload
    networks:
      - app-network
    restart: unless-stopped

  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: app
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - app-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    networks:
      - app-network
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:

networks:
  app-network:
    driver: bridge
```

## Development vs Production

**compose.yml** (base):
```yaml
services:
  web:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/app
```

**compose.override.yml** (development, auto-loaded):
```yaml
services:
  web:
    volumes:
      - ./src:/app/src      # Live code reload
    environment:
      - NODE_ENV=development
      - DEBUG=true
    command: npm run dev
```

**compose.prod.yml** (production):
```yaml
services:
  web:
    image: registry.example.com/myapp:1.0
    restart: always
    environment:
      - NODE_ENV=production
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
```

Usage: `docker compose -f compose.yml -f compose.prod.yml up -d`

## Health Checks

```yaml
services:
  web:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 3s
      start-period: 40s
      retries: 3
```

## Resource Limits

```yaml
services:
  web:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```

## Restart Policies

```yaml
services:
  web:
    restart: unless-stopped    # Options: no, always, unless-stopped, on-failure
```

## Logging Configuration

```yaml
services:
  web:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

## Environment Variables

**Using .env file**:
```yaml
services:
  web:
    env_file:
      - .env
```

**Using Docker secrets** (Swarm):
```yaml
services:
  web:
    secrets:
      - db_password

secrets:
  db_password:
    external: true
```

## Service Communication

```yaml
services:
  web:
    depends_on:
      - db
    environment:
      # Use service name as hostname
      - DATABASE_URL=postgresql://user:pass@db:5432/app

  db:
    image: postgres:15-alpine
```

## Volume Patterns

**Named volumes** (persistent data):
```yaml
services:
  db:
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

**Bind mounts** (development):
```yaml
services:
  web:
    volumes:
      - ./src:/app/src
      - ./config:/app/config:ro  # Read-only
```
