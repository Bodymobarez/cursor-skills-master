# Remote Docker Management

Manage Docker daemons on remote hosts via SSH, TCP, or contexts.

## Docker Contexts

### Create SSH Context

```bash
# Create context for remote host via SSH
docker context create REMOTE_NAME --docker "host=ssh://user@hostname"
docker context create rpi --docker "host=ssh://pi@raspberry-pi.local"

# Use context
docker context use REMOTE_NAME
docker ps  # Now runs on remote host

# List contexts
docker context ls

# Show current context
docker context show

# Inspect context
docker context inspect REMOTE_NAME

# Switch back to default
docker context use default
```

### Create TCP Context

```bash
# Create context for TCP socket (requires TLS in production)
docker context create REMOTE_NAME --docker "host=tcp://hostname:2376"
docker context create REMOTE_NAME --docker "host=tcp://hostname:2376" --docker "tls=true"

# Use TLS certificates
docker context create REMOTE_NAME \
  --docker "host=tcp://hostname:2376" \
  --docker "tls=true" \
  --docker "tlscacert=/path/to/ca.pem" \
  --docker "tlscert=/path/to/cert.pem" \
  --docker "tlskey=/path/to/key.pem"
```

### Context Management

```bash
# Update context
docker context update REMOTE_NAME --docker "host=ssh://newuser@newhost"

# Export context
docker context export REMOTE_NAME -o context.tar

# Import context
docker context import REMOTE_NAME context.tar

# Remove context
docker context rm REMOTE_NAME
```

## SSH-Based Remote Access

### Direct SSH Connection

```bash
# Set DOCKER_HOST environment variable
export DOCKER_HOST=ssh://user@hostname
docker ps  # Commands run on remote host

# Unset to return to local
unset DOCKER_HOST

# One-time command
DOCKER_HOST=ssh://user@hostname docker ps
```

### SSH Key Setup

```bash
# Generate SSH key if needed
ssh-keygen -t ed25519 -C "docker-remote"

# Copy key to remote host
ssh-copy-id user@hostname

# Test SSH connection
ssh user@hostname "docker ps"

# Use with Docker context
docker context create remote --docker "host=ssh://user@hostname"
docker context use remote
```

### SSH Config Integration

```bash
# ~/.ssh/config
Host docker-host
    HostName actual-hostname.com
    User myuser
    IdentityFile ~/.ssh/docker_key
    Port 22

# Use SSH config hostname
docker context create remote --docker "host=ssh://docker-host"
```

## TCP Socket Access

### Remote Daemon Configuration

On remote host (`/etc/docker/daemon.json`):

```json
{
  "hosts": ["tcp://0.0.0.0:2376", "unix:///var/run/docker.sock"]
}
```

**Security Warning**: Use TLS certificates in production!

### Connect via TCP

```bash
# Set DOCKER_HOST
export DOCKER_HOST=tcp://hostname:2376
docker ps

# With TLS
export DOCKER_HOST=tcp://hostname:2376
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH=/path/to/certs
docker ps
```

## Remote Operations

### Execute Commands Remotely

```bash
# Using context
docker context use remote
docker run -d --name myapp myapp:latest
docker logs myapp
docker context use default  # Return to local

# Using DOCKER_HOST
DOCKER_HOST=ssh://user@host docker run -d --name myapp myapp:latest
```

### Remote Build and Deploy

```bash
# Build locally, push to registry, pull on remote
docker build -t registry.example.com/myapp:latest .
docker push registry.example.com/myapp:latest

docker context use remote
docker pull registry.example.com/myapp:latest
docker run -d --name myapp registry.example.com/myapp:latest
```

### Remote Compose Operations

```bash
# Use context for compose
docker context use remote
docker compose -f docker-compose.yml up -d
docker compose ps
docker compose logs -f
```

## Multi-Host Management

### Script for Multiple Hosts

```bash
#!/bin/bash
# Execute command on multiple Docker hosts
HOSTS=("ssh://user@host1" "ssh://user@host2" "ssh://user@host3")
COMMAND="$1"

for host in "${HOSTS[@]}"; do
  echo "Executing on $host..."
  DOCKER_HOST=$host docker $COMMAND
done
```

### Context Switching Script

```bash
#!/bin/bash
# Quick context switcher
CONTEXT="$1"

if [ -z "$CONTEXT" ]; then
  docker context ls
  exit 0
fi

docker context use $CONTEXT
echo "Switched to context: $CONTEXT"
docker info | grep "Name:"
```

## Security Considerations

### TLS Configuration

```bash
# Generate TLS certificates (on remote host)
# Use Docker's certificate generation or your CA

# Client configuration
export DOCKER_HOST=tcp://hostname:2376
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH=~/.docker/certs

# Files needed:
# - ca.pem (CA certificate)
# - cert.pem (client certificate)
# - key.pem (client private key)
```

### SSH Key Security

```bash
# Use dedicated SSH key for Docker access
ssh-keygen -t ed25519 -f ~/.ssh/docker_remote -C "docker-remote"

# Restrict key usage in ~/.ssh/authorized_keys on remote
command="docker-proxy" ssh-ed25519 AAAAC3... user@host

# Use SSH agent
ssh-add ~/.ssh/docker_remote
```

### Firewall Rules

On remote host:

```bash
# Allow SSH (for SSH-based access)
sudo ufw allow 22/tcp

# Allow Docker TCP (if using TCP socket)
sudo ufw allow from TRUSTED_IP to any port 2376

# Block direct Docker socket access from network
# Only allow via SSH or TLS
```

## Troubleshooting Remote Access

### Test Connection

```bash
# Test SSH connection
ssh user@hostname "docker version"

# Test Docker context
docker context use remote
docker version
docker info

# Test TCP connection
DOCKER_HOST=tcp://hostname:2376 docker version
```

### Debug Connection Issues

```bash
# Verbose SSH
ssh -v user@hostname "docker ps"

# Check Docker daemon status on remote
ssh user@hostname "sudo systemctl status docker"

# Check Docker socket permissions
ssh user@hostname "ls -la /var/run/docker.sock"

# Test with docker context debug
docker context inspect remote
```

### Common Issues

**Permission denied**:
- User not in `docker` group on remote host
- SSH key not authorized
- Docker socket permissions incorrect

**Connection refused**:
- Docker daemon not running
- Firewall blocking port
- Wrong host/port

**TLS errors**:
- Certificates not configured correctly
- Certificate expired
- Wrong certificate path
