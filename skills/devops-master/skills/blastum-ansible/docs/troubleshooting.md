# Ansible Troubleshooting

## Connection Issues

```bash
# Test SSH connection manually
ssh -v user@hostname

# Debug Ansible connection
ansible hostname -i inventory/hosts.yml -m ping -vvv

# Check inventory parsing
ansible-inventory -i inventory/hosts.yml --list
```

## Common Errors

**"Permission denied"**
- Check SSH key permissions: `chmod 600 ~/.ssh/id_*`
- Verify user has sudo access
- Add `become: yes` to playbook

**"Host key verification failed"**
- **Recommended**: Add host key: `ssh-keyscan -H hostname >> ~/.ssh/known_hosts`
- **If necessary** (ask user first - explain MITM risk): Set `ansible_ssh_common_args: '-o StrictHostKeyChecking=no'` in inventory

**"Module not found"**
- Use FQCN: `ansible.builtin.apt` instead of `apt`
- Install collection: `ansible-galaxy collection install community.general`

**"Python interpreter not found"**
- Set in inventory: `ansible_python_interpreter: /usr/bin/python3`
- Or in playbook: `vars: ansible_python_interpreter: /usr/bin/python3`

## Debugging Playbooks

```bash
# Verbose output
ansible-playbook site.yml -v    # Basic
ansible-playbook site.yml -vv   # More detail
ansible-playbook site.yml -vvv  # Maximum detail

# Step through tasks interactively
ansible-playbook site.yml --step

# Start at specific task
ansible-playbook site.yml --start-at-task="Install nginx"

# Check mode (dry run) with diff
ansible-playbook site.yml --check --diff
```

## Performance Optimization

```bash
# Increase parallelism (default: 5)
ansible-playbook site.yml -f 10

# Enable SSH pipelining (in ansible.cfg)
[ssh_connection]
pipelining = True

# Enable fact caching (in ansible.cfg)
[defaults]
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
```

## Testing Playbooks

```bash
# Syntax check
ansible-playbook site.yml --syntax-check

# List tasks without running
ansible-playbook site.yml --list-tasks

# List hosts that would be affected
ansible-playbook site.yml --list-hosts
```
