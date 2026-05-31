# SSH Key Setup

Set up passwordless SSH access to Raspberry Pi.

## Generate SSH Key Pair

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

## Copy Public Key to Pi

### Method 1: ssh-copy-id (recommended)
```bash
ssh-copy-id pi@raspberrypi.local
```

### Method 2: Manual copy
```bash
# Copy your public key
cat ~/.ssh/id_ed25519.pub | ssh pi@raspberrypi.local "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"

# Set correct permissions
ssh pi@raspberrypi.local "chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"
```

## Verify Key Authentication

```bash
ssh pi@raspberrypi.local
# Should connect without password prompt
```

## Key Management

### List keys on local machine
```bash
ssh-add -l
```

### Add key to ssh-agent
```bash
ssh-add ~/.ssh/id_ed25519
```

### Remove key
```bash
ssh-add -d ~/.ssh/id_ed25519
```