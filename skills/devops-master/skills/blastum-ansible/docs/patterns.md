# Ansible Patterns

## Pattern 1: New Server Setup

```bash
# 1. Add host to inventory
cat >> inventory/hosts.yml << 'EOF'
        newserver:
          ansible_host: 192.0.2.100
          ansible_user: root
          ansible_ssh_pass: "{{ vault_initial_password }}"
          deploy_user: deploy
          deploy_ssh_pubkey: "{{ vault_deploy_ssh_pubkey }}"
EOF

# 2. Run setup playbook
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml \
  --limit newserver \
  --ask-vault-pass

# 3. After initial setup, update inventory to use key auth
# ansible_user: deploy
# ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```

## Pattern 2: Selective Execution

```bash
# Security hardening only
ansible-playbook -i inventory/hosts.yml playbooks/security.yml \
  --limit production \
  --tags "ssh,firewall"

# Application deployment
ansible-playbook -i inventory/hosts.yml playbooks/deploy.yml \
  --tags "deploy,app" \
  --limit webservers
```

## Pattern 3: Rolling Updates

```bash
# Update one server at a time
ansible-playbook -i inventory/hosts.yml playbooks/update.yml \
  --serial 1

# Update in batches of 3
ansible-playbook -i inventory/hosts.yml playbooks/update.yml \
  --serial 3
```

## Pattern 4: Ad-hoc Commands

```bash
# Check disk space
ansible all -i inventory/hosts.yml -m shell -a "df -h"

# Restart service
ansible webservers -i inventory/hosts.yml -m systemd -a "name=nginx state=restarted"

# Copy file
ansible all -i inventory/hosts.yml -m copy -a "src=./config.txt dest=/tmp/config.txt"
```

## Pattern 5: Tags for Organization

```yaml
# playbooks/site.yml
---
- name: Security tasks
  ansible.builtin.include_tasks: security.yml
  tags: [security, hardening]

- name: App deployment
  ansible.builtin.include_tasks: deploy.yml
  tags: [deploy, app]

- name: Monitoring setup
  ansible.builtin.include_tasks: monitoring.yml
  tags: [monitoring]
```

## Pattern 6: Conditional Execution

```yaml
- name: Install packages
  ansible.builtin.apt:
    name: nginx
    state: present
  when: ansible_os_family == "Debian"

- name: Install packages
  ansible.builtin.yum:
    name: nginx
    state: present
  when: ansible_os_family == "RedHat"
```
