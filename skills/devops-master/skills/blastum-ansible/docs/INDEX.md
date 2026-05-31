# Ansible Index

## Core Topics
- [basics.md](basics.md) - Installation, inventory, playbooks, roles
- [modules.md](modules.md) - Common modules reference
- [security.md](security.md) - Vault, secrets, hardening
- [patterns.md](patterns.md) - Usage patterns and best practices
- [troubleshooting.md](troubleshooting.md) - Common issues and debugging

## Quick Reference

**Directory structure:**
```
ansible/
├── inventory/hosts.yml
├── playbooks/site.yml
├── roles/{role}/tasks/main.yml
└── group_vars/all/vault.yml
```

**Essential commands:**
- `ansible-playbook -i inventory site.yml --check --diff` - Dry run
- `ansible-vault create group_vars/all/vault.yml` - Encrypt secrets
- `ansible-playbook site.yml --tags "security" --limit webservers` - Selective runs
