# Tailscale Security Best Practices

## Overview

Security considerations and best practices for using Tailscale with Apple's container tool, focusing on access controls, authentication, and network security.

## Authentication Security

### Auth Key Management

**Ephemeral keys for containers:**
```bash
# Generate short-lived keys
tailscale auth-keys create \
  --description "container-deployment-$(date +%s)" \
  --ephemeral \
  --expiry 24h

# Use immediately, auto-expires
# Perfect for CI/CD and temporary access
```

**Reusable keys with restrictions:**
```bash
# Create restricted keys
tailscale auth-keys create \
  --description "production-access" \
  --reusable \
  --tags "tag:production"
```

### Key Rotation Strategy

**Automated rotation:**
```bash
# Rotate keys quarterly
# Use different keys per environment
# Monitor key usage in admin console
```

## Access Control Lists (ACLs)

### Basic ACL Structure

**Allow specific access:**
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:developers"],
      "dst": ["swift-vapor-server:*"]
    },
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["*"]
    }
  ]
}
```

### Service-Specific Rules

**Web application access:**
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["swift-vapor-server:80,443"]
    }
  ]
}
```

### Time-Based Access

**Temporary access rules:**
```json
{
  "acls": [
    {
      "action": "accept",
      "src": [" contractor@company.com"],
      "dst": ["swift-vapor-server:*"],
      "proto": "tcp",
      "ports": "80,443"
    }
  ],
  "expires": "2024-12-31T23:59:59Z"
}
```

## Network Security

### Device Approval Process

**Manual approval workflow:**
1. New device requests access
2. Admin reviews device information
3. Manual approval or denial
4. Audit trail maintained

**Automatic approval (trusted networks):**
```json
{
  "autoApprovers": {
    "routes": {
      "192.168.1.0/24": ["tag:trusted"]
    }
  }
}
```

### Subnet Routing

**Secure subnet access:**
```bash
# Advertise local network
tailscale up --advertise-routes=192.168.1.0/24

# Control access via ACLs
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:admin"],
      "dst": ["192.168.1.0/24:*"]
    }
  ]
}
```

## Container Security

### Non-Root Execution

**Run containers as non-root:**
```dockerfile
# In Containerfile
RUN useradd --user-group --create-home --system vapor
USER vapor:vapor
```

**Benefits:**
- Principle of least privilege
- Reduced attack surface
- Compliance requirements

### Resource Limits

**Prevent resource exhaustion:**
```bash
container run -d \
  --memory 512m \
  --cpus 1.0 \
  --read-only \
  swift-vapor-server
```

### Minimal Base Images

**Use security-focused images:**
```dockerfile
FROM ubuntu:noble

# Install only required packages
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

## Monitoring & Auditing

### Access Logging

**Monitor device connections:**
```bash
# View connected devices
tailscale status

# Check device approval status
tailscale admin console

# Audit access patterns
tailscale status --json
```

### Security Monitoring

**Container security scanning:**
```bash
# Scan images for vulnerabilities
# Integrate with security tools
# Regular security updates
```

### Incident Response

**Security breach procedures:**
1. Revoke compromised auth keys
2. Remove unauthorized devices
3. Update ACLs to block access
4. Audit access logs

## Compliance Considerations

### Data Protection

**Encrypt sensitive data:**
- All Tailscale traffic is encrypted
- Use HTTPS for web applications
- Encrypt sensitive container data

### Access Reviews

**Regular access audits:**
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:auditors"],
      "dst": ["swift-vapor-server:80,443"]
    }
  ]
}
```

### Compliance Frameworks

**Common requirements:**
- SOC 2 Type II compliance
- GDPR data protection
- HIPAA for healthcare
- PCI DSS for payments

## Best Practices Summary

### Authentication
1. Use ephemeral keys for containers
2. Rotate keys regularly
3. Implement device approval
4. Monitor key usage

### Access Control
1. Implement least privilege ACLs
2. Use groups for access management
3. Regular access reviews
4. Time-bound permissions

### Network Security
1. Enable device logging
2. Use subnet routing carefully
3. Implement network segmentation
4. Regular security audits

### Container Security
1. Run as non-root user
2. Use minimal base images
3. Apply resource limits
4. Regular vulnerability scanning

## Emergency Procedures

### Key Compromise

**Immediate response:**
```bash
# Revoke compromised key
tailscale auth-keys delete tskey-compromised

# Update all affected containers
# Regenerate new keys
# Update access credentials
```

### Unauthorized Access

**Containment steps:**
1. Identify unauthorized device
2. Remove from tailnet
3. Update ACLs to prevent re-access
4. Audit access patterns
5. Notify security team

### System Compromise

**Recovery procedures:**
1. Isolate affected systems
2. Revoke all auth keys
3. Rebuild containers from trusted images
4. Update all access controls
5. Perform security assessment

## Related Topics

- Tailscale Fundamentals - Core concepts
- Auth Key Configuration - Key management
- Network Access Methods - Access patterns
- Troubleshooting Guide - Security issues