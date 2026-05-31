# Ansible Basics

## Installation

```bash
pip install ansible  # Cross-platform
brew install ansible  # macOS
```

Verify: `ansible --version`

## Inventory

Define hosts in `inventory/hosts.yml`:

```yaml
all:
  children:
    webservers:
      hosts:
        web1:
          ansible_host: 192.0.2.10
          ansible_user: deploy
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519
        web2:
          ansible_host: 192.0.2.11
          ansible_user: deploy
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519
    
    databases:
      hosts:
        db1:
          ansible_host: 192.0.2.20
```

**Note**: Replace example IPs (`192.0.2.x`) and hostnames with actual values.

## Playbooks

Entry points for automation:

```yaml
# playbooks/site.yml
---
- name: Configure all servers
  hosts: all
  become: yes
  roles:
    - common
    - security

- name: Setup application servers
  hosts: webservers
  become: yes
  roles:
    - nodejs
    - app
```

## Roles

Reusable, modular configurations:

```yaml
# roles/common/tasks/main.yml
---
- name: Update apt cache
  ansible.builtin.apt:
    update_cache: yes
    cache_valid_time: 3600
  when: ansible_os_family == "Debian"

- name: Install essential packages
  ansible.builtin.apt:
    name:
      - curl
      - git
      - vim
    state: present
```

## Running Playbooks

```bash
# Dry run (check mode)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff

# Execute
ansible-playbook -i inventory/hosts.yml playbooks/site.yml

# With tags
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags "security,nodejs"

# Limit to specific hosts
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit webservers
```
