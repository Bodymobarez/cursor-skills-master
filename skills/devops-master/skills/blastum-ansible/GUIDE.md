---
name: blastum-ansible
description: Infrastructure automation with Ansible. Use for server provisioning, configuration management, application deployment, and multi-host orchestration.
metadata: {"openclaw":{"requires":{"bins":["ansible","ansible-playbook"]},"install":[{"id":"ansible","kind":"pip","package":"ansible","bins":["ansible","ansible-playbook"],"label":"Install Ansible (pip)"}]}}
---

# Ansible

See [docs/INDEX.md](docs/INDEX.md) for complete guide.

## Quick Start

```bash
# Install
pip install ansible  # or: brew install ansible

# Test connection
ansible all -i inventory/hosts.yml -m ping

# Run playbook
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff
```
