# Ansible Security

## Vault for Secrets

Encrypt sensitive data:

```bash
# Create encrypted vars file
ansible-vault create inventory/group_vars/all/vault.yml

# Edit encrypted file
ansible-vault edit inventory/group_vars/all/vault.yml

# Run with vault password prompt
ansible-playbook site.yml --ask-vault-pass

# Use vault password file (secure permissions: chmod 600)
ansible-playbook site.yml --vault-password-file ~/.vault_pass
```

**Vault file structure:**
```yaml
# inventory/group_vars/all/vault.yml
---
# EXAMPLE VALUES - Replace with actual secrets
vault_db_password: "EXAMPLE_PASSWORD_CHANGE_ME"
vault_api_key: "EXAMPLE_API_KEY_CHANGE_ME"
vault_deploy_ssh_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  EXAMPLE_KEY_CONTENT_REPLACE_WITH_ACTUAL_KEY
  -----END OPENSSH PRIVATE KEY-----
```

**Important**: Never commit unencrypted secrets. Always use `ansible-vault` for passwords, API keys, and private keys.

## Group Variables

```yaml
# inventory/group_vars/all.yml
---
timezone: UTC
deploy_user: deploy
ssh_port: 22

# Security settings
security_ssh_password_auth: false
security_ssh_permit_root: false
security_fail2ban_enabled: true
security_ufw_enabled: true
security_ufw_allowed_ports:
  - 22
  - 80
  - 443
```

## SSH Host Key Verification

**Security Warning**: Disabling host key checking removes protection against man-in-the-middle attacks. Only disable in isolated test environments.

**Recommended approach**: Add host keys manually:
```bash
ssh-keyscan -H hostname >> ~/.ssh/known_hosts
```

**If you must disable** (ask user first - explain MITM risk):
```bash
# Per-host in inventory (preferred over global)
ansible_ssh_common_args: '-o StrictHostKeyChecking=no'

# Or in ansible.cfg (not recommended)
[defaults]
host_key_checking = False
```

**Best practice**: Always verify host authenticity manually on first connection, then add to known_hosts.

## Protecting Secrets in Output

Use `no_log` to prevent sensitive data in logs:

```yaml
- name: Set database password
  ansible.builtin.set_fact:
    db_password: "{{ vault_db_password }}"
  no_log: true
```
