# role: base

System-level setup that doesn't depend on chimebox specifics:

- Apt cache update + safe upgrade
- Timezone
- Essential packages (sudo, git, rsync, htop, curl)
- Disable Pi-OS-default services we don't want (e.g., avahi if you don't
  need mDNS, though we keep it on by default since SETUP.md leans on it)

This role is opinionated about minimal surface area; it doesn't install
anything chimebox-specific.
