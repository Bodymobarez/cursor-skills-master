# Tailscale Authentication & Access Configuration

## Overview

Tailscale authentication is device-based, not user-based. This guide covers auth key management, access patterns, and security configuration for Swift Vapor containers.

## Authentication Architecture

### How Auth Keys Work

**Traditional Authentication:**
```
User Account → Password/Login → Access Token → API Access
```

**Tailscale Authentication:**
```
Auth Key → Device Registration → Tailnet Membership → Network Access
```

### Key Types & Use Cases

#### Ephemeral Keys (Recommended for Containers)

```bash
# Create ephemeral key (auto-expires)
# Best for: Development, testing, temporary deployments
# Expires: 90 days (configurable)
# Reusable: No (single device only)
```

**When to use:**
- Development containers
- CI/CD pipelines
- Temporary testing environments
- Auto-scaling deployments

#### Reusable Keys (For Persistent Services)

```bash
# Create reusable key (long-lived)
# Best for: Production servers, persistent infrastructure
# Expires: Never (manual revocation)
# Reusable: Yes (multiple devices)
```

**When to use:**
- Production servers
- Long-running infrastructure
- Devices that need persistent access

## Auth Key Management

### Creating Auth Keys

#### Via Admin Console (Recommended)

1. **Navigate to Admin Console**:
   ```bash
   open https://login.tailscale.com/admin/authkeys
   ```

2. **Generate New Key**:
   - Click "Generate auth key"
   - **Description**: `swift-vapor-server-dev`
   - **Type**: Ephemeral (recommended)
   - **Expiry**: 90 days
   - **Tags**: Leave empty (full access)

3. **Key Format**:
   ```
   tskey-ABC123def456ghi789...
   ```

#### Via Tailscale CLI (Advanced)

```bash
# List existing keys
tailscale auth-keys list

# Create new key
tailscale auth-keys create \
  --description "swift-vapor-server" \
  --ephemeral \
  --expiry 2160h  # 90 days

# Revoke key
tailscale auth-keys delete tskey-ABC123...
```

### Key Security Best Practices

#### Key Rotation Strategy

```bash
# Ephemeral keys (recommended)
# - Auto-expire every 90 days
# - No manual rotation needed
# - Perfect for containers

# Reusable keys
# - Rotate quarterly
# - Use different keys per environment
# - Monitor usage in admin console
```

#### Environment Separation

```bash
# Development
TAILSCALE_AUTH_KEY=tskey-dev-ABC123...

# Staging
TAILSCALE_AUTH_KEY=tskey-staging-DEF456...

# Production
TAILSCALE_AUTH_KEY=tskey-prod-GHI789...
```

## Access Patterns

### Local Development Access

**When container runs locally without Tailscale:**
```bash
# Direct localhost access
curl http://localhost:8080/health

# Container networking only
# No remote access
# No Tailscale involvement
```

**Best for:**
- Local development
- Testing without network dependencies
- Isolated development environments

### Tailscale Network Access

**When Tailscale runs on host:**
```bash
# Hostname access (MagicDNS)
curl http://swift-vapor-server:8080/health

# IP address access
curl http://100.x.x.x:8080/health

# From any Tailscale-connected device
# Secure, encrypted access
```

**Best for:**
- Remote development
- Team access
- Production deployments

### Hybrid Access (Both)

**Container exposes both interfaces:**
```bash
# Local development
curl http://localhost:8080/health

# Remote access via Tailscale
curl http://swift-vapor-server:8080/health
```

## Configuration Examples

### Apple's Container Tool

```bash
# Build image
container build -t swift-vapor-server .

# Run with Tailscale access
container run -d -p 8080:8080 \
  --name vapor-server \
  swift-vapor-server

# Access via Tailscale
curl http://swift-vapor-server:8080/health
```

### Docker/Colima with Host Tailscale

```bash
# Tailscale on macOS host
tailscale up --auth-key=tskey-host-...

# Container with port mapping
docker run -d -p 8080:8080 \
  swift-vapor-server

# Access through host Tailscale
curl http://swift-vapor-server:8080/health
```

### Docker with Container Tailscale

```yaml
# docker-compose.yml
version: '3.8'
services:
  app:
    image: swift-vapor-server
    network_mode: host
    environment:
      - TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}
      - TAILSCALE_HOSTNAME=swift-vapor-server
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - tailscale-data:/var/lib/tailscale
```

## Security Configuration

### Access Control Lists (ACLs)

**Default Policy**: All devices can reach each other

**Custom ACLs for Security**:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:admin"],
      "dst": ["swift-vapor-server:*"]
    },
    {
      "action": "accept",
      "src": ["group:developers"],
      "dst": ["swift-vapor-server:8080"]
    }
  ]
}
```

### Device Approval Settings

**Automatic Approval** (for trusted networks):
- Enable in admin console
- Auto-approve devices from known IP ranges

**Manual Approval** (recommended):
- All new devices require admin approval
- Better security for production

### Network Segmentation

**Tag-Based Access**:
```json
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"],
    "tag:dev": ["group:developers"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:dev"],
      "dst": ["tag:server:8080"]
    }
  ]
}
```

## Troubleshooting Authentication

### Common Issues

#### "Auth key expired"

**Symptoms:**
```
tailscale: auth key expired
```

**Solutions:**
```bash
# Generate new ephemeral key
# Update environment variable
# Restart container
container run -d -p 8080:8080 \
  -e TAILSCALE_AUTH_KEY=tskey-new-key... \
  swift-vapor-server
```

#### "Device not approved"

**Symptoms:**
```
Device appears in admin console as "pending"
```

**Solutions:**
- Approve device in admin console
- Check ACL rules allow access
- Verify device tags match policy

#### "Invalid auth key"

**Symptoms:**
```
tailscale: invalid auth key
```

**Solutions:**
- Verify key format (starts with `tskey-`)
- Check key hasn't been revoked
- Ensure key type matches usage (ephemeral vs reusable)

### Debug Commands

```bash
# Check Tailscale status
tailscale status

# View device information
tailscale ip -4
tailscale whois $(tailscale ip -4)

# Test connectivity
tailscale ping swift-vapor-server

# Check auth key validity
tailscale debug --auth-key-state
```

### Log Analysis

```bash
# Container logs
container logs vapor-server

# Tailscale daemon logs (if in container)
docker logs container_name | grep tailscale

# System logs
log show --predicate 'subsystem == "tailscale"' --last 1h
```

## Performance & Monitoring

### Connection Monitoring

```bash
# Real-time status
watch tailscale status

# Connection quality
tailscale ping --count=10 swift-vapor-server

# Bandwidth usage (admin console)
# https://login.tailscale.com/admin/stats
```

### Key Usage Tracking

**In Admin Console:**
- View key creation dates
- See which devices used which keys
- Monitor for unusual key usage patterns

**Audit Logging:**
```json
{
  "event": "device_approved",
  "device": "swift-vapor-server",
  "auth_key": "tskey-ABC123...",
  "timestamp": "2026-01-31T10:30:00Z"
}
```

## Migration Strategies

### From No Authentication

**Before:**
```bash
# Open access via localhost
curl http://localhost:8080/health
```

**After:**
```bash
# Install Tailscale
brew install tailscale
tailscale up

# Deploy with auth key
container run -d -p 8080:8080 \
  -e TAILSCALE_AUTH_KEY=tskey-... \
  swift-vapor-server

# Access securely
curl http://swift-vapor-server:8080/health
```

### From Traditional VPN

**VPN Approach:**
- Complex firewall rules
- Shared VPN credentials
- All-or-nothing access

**Tailscale Approach:**
- Device-based authentication
- Granular ACLs
- Direct device-to-device connections

### From ngrok/LocalTunnel

**Tunnel Approach:**
- Temporary URLs
- Rate limiting
- External service dependency

**Tailscale Approach:**
- Persistent hostnames
- Unlimited usage
- Self-hosted networking

## Best Practices

### Development Environment

1. **Use ephemeral keys** for all development containers
2. **Enable MagicDNS** for easy hostnames
3. **Test locally first** before enabling Tailscale
4. **Use descriptive hostnames** for device identification

### Production Environment

1. **Implement ACLs** for access control
2. **Use reusable keys** only when necessary
3. **Enable device approval** for new devices
4. **Monitor key usage** and device connections
5. **Plan key rotation** and access reviews

### Security Recommendations

1. **Regular key audits** in admin console
2. **Monitor device connections** for anomalies
3. **Use tags and ACLs** for role-based access
4. **Enable logging** for security events
5. **Keep Tailscale updated** for security patches

## Advanced Configuration

### Custom Auth Key Tags

```bash
# Create key with specific tags
tailscale auth-keys create \
  --description "production-server" \
  --reusable \
  --tags "tag:prod,tag:server"
```

### IP Address Management

```bash
# Reserve specific IPs (Tailscale admin)
# Useful for firewall rules or DNS

# View current IP
tailscale ip -4

# Release and get new IP
tailscale up --reset
```

### Integration with CI/CD

**GitHub Actions Example:**
```yaml
- name: Deploy to Tailscale
  run: |
    # Get auth key from secrets
    echo "TAILSCALE_AUTH_KEY=${{ secrets.TAILSCALE_AUTH_KEY }}" >> .env

    # Deploy container
    container run -d -p 8080:8080 \
      --env-file .env \
      swift-vapor-server
```

**Automated Key Rotation:**
```bash
# Create short-lived keys for CI
tailscale auth-keys create \
  --description "ci-deployment-$(date +%s)" \
  --ephemeral \
  --expiry 24h
```

## Resources

- [Tailscale Auth Keys Documentation](https://tailscale.com/kb/1085/auth-keys)
- [ACL Policy Guide](https://tailscale.com/kb/1018/acls)
- [Security Best Practices](https://tailscale.com/kb/1007/security-audit)
- [Admin Console](https://login.tailscale.com/admin)