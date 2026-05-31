# Getting Started with Apple's Container Tool

## Overview

This guide walks you through setting up Apple's native container tool on macOS with Tailscale networking for secure remote access. We'll deploy both Swift Vapor and Node.js TypeScript applications using micro-VM architecture.

## Prerequisites

- macOS 12.0 or later (preferably Apple Silicon)
- Homebrew installed
- Tailscale account with admin access
- Basic terminal/command line knowledge

## Quick Setup (5 minutes)

### 1. Install Apple's Container Tool

```bash
# Install Apple's native container runtime
brew install container

# Start the container system
container system start

# Set recommended kernel for ARM64
container system kernel set --recommended

# Verify installation
container version
container system status
```

### 2. Setup Tailscale on Host

```bash
# Install Tailscale
brew install tailscale

# Start Tailscale service
sudo brew services start tailscale

# Authenticate (opens browser)
tailscale up

# Verify connection
tailscale status
```

### 3. Get Tailscale Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/authkeys)
2. Create new auth key:
   - **Type**: Ephemeral (recommended)
   - **Description**: swift-vapor-server
   - **Tags**: Leave empty
   - **Expiry**: 90 days
3. Copy the generated key (starts with `tskey-`)

### 4. Deploy Applications

**Swift Vapor Server:**
```bash
# Navigate to project
cd swift-vapor-server

# Build container image
container build -t swift-vapor-server .

# Run container (Tailscale runs on host)
container run -d -p 8080:8080 \
  --name vapor-server \
  swift-vapor-server
```

**Node.js TypeScript App:**
```bash
# Navigate to project
cd server-2

# Build container image
container build -t server-2 .

# Run container
container run -d -p 8081:8080 \
  --name nodejs-server \
  server-2
```

### 5. Access Your Applications

**Local access:**
```bash
# Swift Vapor server
curl http://localhost:8080/health
# Should return: {"status":"healthy","timestamp":"2026-01-31T..."}

# Node.js server
curl http://localhost:8081/health
# Should return: {"status":"healthy","timestamp":"2026-02-01T...","version":"1.0.0"}
```

**Tailscale access:**
```bash
# Get Tailscale IP
tailscale ip -4

# Access via Tailscale
curl http://swift-vapor-server:8080/health
curl http://nodejs-server:8081/health
```

## Architecture Overview

```
macOS Host (Darwin Kernel)
├── Tailscale Daemon (host networking)
├── Apple's Container Tool
│   └── Kata Containers Micro-VM
│       └── Ubuntu Container
│           └── Swift Vapor App
└── Virtualization.framework
```

**Key advantages:**
- Tailscale runs on macOS host for better integration
- Each container gets its own micro-VM for isolation
- Native macOS integration with low overhead
- Optimized for Apple Silicon

## Verification Steps

### Check Container System
```bash
# System status
container system status

# List running containers
container list

# View container logs
container logs vapor-server
```

### Check Tailscale
```bash
# Status on host
tailscale status

# Check device in admin console
# https://login.tailscale.com/admin/machines
```

### Test Application
```bash
# Health check
curl http://localhost:8080/health

# Main page
curl http://localhost:8080/

# Via Tailscale
curl http://swift-vapor-server:8080/health
```

## Troubleshooting Quick Fixes

### Container won't start
```bash
# Check system status
container system status

# Restart system
container system restart

# Check kernel
container system kernel current
container system kernel set --recommended
```

### Tailscale connection issues
```bash
# Check host Tailscale
tailscale status

# Re-authenticate
tailscale up --reset
tailscale up

# Check admin console for device approval
```

### Port conflicts
```bash
# Find process using port
lsof -i :8080

# Use different port
container run -d -p 8081:8080 --name vapor-server swift-vapor-server
```

## Core Concepts

### Micro-VM Architecture

Unlike Docker's shared Linux VM, Apple's container tool creates a separate micro-VM for each container:

```
Traditional Docker:
macOS → Single Linux VM → Multiple Containers

Apple Container Tool:
macOS → Micro-VM #1 → Container #1
macOS → Micro-VM #2 → Container #2
```

**Benefits:**
- Better isolation between containers
- Lower resource usage per container
- Native macOS integration
- Apple Silicon optimization

### Host-Based Networking

Tailscale runs on the macOS host instead of inside containers:

```
Container Approach (Docker):
Container → Tailscale in container → TUN device → Host network

Host Approach (Apple Container):
macOS Host → Tailscale daemon → Direct network access → Container
```

**Benefits:**
- Simpler container setup
- Better macOS integration
- Easier debugging
- More reliable networking

## Next Steps

- **Customize**: Modify Containerfile for your Swift app
- **Scale**: Run multiple containers
- **Secure**: Configure Tailscale ACLs
- **Monitor**: Set up logging and health monitoring

## Resources

- Apple Container Tool Documentation
- Tailscale Setup Guide
- Swift Vapor Containerfile patterns
- Troubleshooting guide