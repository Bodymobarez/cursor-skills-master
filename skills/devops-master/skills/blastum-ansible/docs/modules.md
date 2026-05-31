# Ansible Modules

## Common Modules

| Module | Purpose | Example |
|--------|---------|---------|
| `ansible.builtin.apt` | Package management (Debian) | `ansible.builtin.apt: name=nginx state=present` |
| `ansible.builtin.yum` | Package management (RHEL) | `ansible.builtin.yum: name=nginx state=present` |
| `ansible.builtin.copy` | Copy files | `ansible.builtin.copy: src=file.txt dest=/etc/file.txt` |
| `ansible.builtin.template` | Template files (Jinja2) | `ansible.builtin.template: src=nginx.conf.j2 dest=/etc/nginx/nginx.conf` |
| `ansible.builtin.file` | File/directory management | `ansible.builtin.file: path=/opt/app state=directory mode=0755` |
| `ansible.builtin.user` | User management | `ansible.builtin.user: name=deploy groups=sudo shell=/bin/bash` |
| `ansible.builtin.authorized_key` | SSH keys | `ansible.builtin.authorized_key: user=deploy key="{{ ssh_pubkey }}"` |
| `ansible.builtin.systemd` | Service management | `ansible.builtin.systemd: name=nginx state=started enabled=yes` |
| `ansible.builtin.ufw` | Firewall (Ubuntu) | `ansible.builtin.ufw: rule=allow port=22 proto=tcp` |
| `ansible.builtin.lineinfile` | Edit single line | `ansible.builtin.lineinfile: path=/etc/ssh/sshd_config regexp='^PermitRootLogin' line='PermitRootLogin no'` |
| `ansible.builtin.git` | Clone repos | `ansible.builtin.git: repo=https://github.com/user/repo.git dest=/opt/repo` |
| `ansible.builtin.command` | Run command | `ansible.builtin.command: /opt/script.sh` |
| `ansible.builtin.shell` | Run shell command | `ansible.builtin.shell: df -h` |

## Best Practices

**Always use FQCN (Fully Qualified Collection Names):**
```yaml
# Good
- ansible.builtin.apt:
    name: nginx
    state: present

# Avoid
- apt:
    name: nginx
```

**Always name tasks:**
```yaml
# Good
- name: Install nginx web server
  ansible.builtin.apt:
    name: nginx
    state: present

# Bad
- ansible.builtin.apt:
    name: nginx
```

**Write idempotent tasks:**
```yaml
# Good - idempotent
- name: Ensure config line exists
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^PasswordAuthentication'
    line: 'PasswordAuthentication no'

# Bad - not idempotent
- name: Add config line
  ansible.builtin.shell: echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
```

**Use handlers for restarts:**
```yaml
# tasks/main.yml
- name: Update SSH config
  ansible.builtin.template:
    src: sshd_config.j2
    dest: /etc/ssh/sshd_config
  notify: Restart SSH

# handlers/main.yml
- name: Restart SSH
  ansible.builtin.systemd:
    name: sshd
    state: restarted
```
