# Pi first-boot setup

This guide walks through getting a Raspberry Pi 5 to the point where it can
be provisioned by chimebox's Ansible playbook. After this is done, all
further configuration is automated by `pi/ansible/`.

You only need to do this once per device.

## What you'll end up with

- A Pi 5 running Raspberry Pi OS Bookworm Lite (64-bit), no desktop.
- An admin user (`bryan`) with `sudo` and SSH key authentication.
- The Pi reachable as `chimebox-dev.local` on your LAN.
- Wi-Fi (or wired Ethernet) configured.
- No password authentication over SSH.

## Prerequisites

- A Raspberry Pi 5.
- A microSD card or NVMe SSD (16GB+). microSD is fine for development;
  NVMe is recommended for daily-driver use due to better wear behavior.
- A way to write to the storage from your workstation:
  - macOS: built-in SD slot or a USB SD reader.
  - For NVMe: an NVMe-to-USB adapter, OR write the image to microSD first
    and copy onto NVMe later.
- Your SSH public key (e.g., `~/.ssh/id_ed25519.pub` on your workstation).
  If you don't have one yet:
  ```sh
  ssh-keygen -t ed25519 -C "your-email@example.com"
  ```

## Step 1 — Install Raspberry Pi Imager (on your workstation)

On macOS:
```sh
brew install --cask raspberry-pi-imager
```

Or download from <https://www.raspberrypi.com/software/>.

## Step 2 — Flash Raspberry Pi OS Lite with custom settings

1. Insert the microSD/NVMe into your workstation.
2. Open Raspberry Pi Imager.
3. Click **Choose Device** → **Raspberry Pi 5**.
4. Click **Choose OS** → **Raspberry Pi OS (other)** → **Raspberry Pi OS
   Lite (64-bit)**. (The "Lite" variant has no desktop, which is what we
   want.)
5. Click **Choose Storage** → select your microSD/NVMe device. **Triple-
   check this is the right device** — Imager will overwrite it.
6. Click **Next** → **Edit Settings** when prompted.

In the **General** tab:
- **Set hostname**: `chimebox-dev`
- **Set username and password**:
  - Username: `bryan`
  - Password: any strong password (you'll rarely use it once SSH keys work)
- **Configure wireless LAN** (skip if using Ethernet):
  - SSID, password, country (e.g., US)
- **Set locale settings**: your timezone, keyboard layout (e.g., `us`)

In the **Services** tab:
- ✅ **Enable SSH**
- Select **Allow public-key authentication only**
- Paste your SSH public key from `~/.ssh/id_ed25519.pub` (run
  `cat ~/.ssh/id_ed25519.pub` on your workstation).

In the **Options** tab:
- Disable **Eject media when finished** if you want to inspect the boot
  partition before moving the card to the Pi (optional).

Click **Save**, then **Yes** to apply settings, then **Yes** to confirm
overwriting the storage. Wait for write + verify (5–15 minutes for
microSD).

## Step 3 — Boot the Pi

1. Eject the storage from your workstation.
2. Insert into the Pi.
3. Connect Ethernet (preferred for first boot; Wi-Fi works too if you
   configured it).
4. Connect power. The Pi 5 needs the official 27W USB-C PSU; underpowered
   supplies will cause silent throttling and weird crashes.
5. Wait ~60 seconds for first-boot setup. The green ACT LED will flicker
   irregularly while the OS expands the partition and applies your custom
   settings.

## Step 4 — Find the Pi on your network

Try mDNS first (works on most home networks):
```sh
ping chimebox-dev.local
```

If that resolves, great. If not, find the IP from your router's DHCP
lease table (look for hostname `chimebox-dev`), or scan:
```sh
# On Linux / macOS with nmap installed:
nmap -sn 10.20.0.0/24 | grep -B 2 -i "raspberry"
```

## Step 5 — First SSH login

From your workstation:
```sh
ssh bryan@chimebox-dev.local
# or, if mDNS didn't work:
ssh bryan@<ip-address-from-step-4>
```

You should land in a prompt without being asked for a password. If you
*are* asked for a password, your public key didn't make it onto the Pi —
check the Imager settings or copy your key with `ssh-copy-id`:
```sh
ssh-copy-id bryan@chimebox-dev.local
```

Once in, run:
```sh
sudo apt-get update && sudo apt-get -y upgrade
sudo reboot
```

After the reboot, SSH back in. You're done with first-boot setup.

## Step 6 — Configure SSH multiplexing (optional but recommended)

If you SSH to the Pi a lot, set up connection sharing so each command
doesn't open a new connection:

In `~/.ssh/config` on your workstation, add:
```
Host chimebox-dev
    HostName chimebox-dev.local
    User bryan
    ControlMaster auto
    ControlPath ~/.ssh/control/%r@%h:%p
    ControlPersist 8h
```

Then create the control directory once:
```sh
mkdir -p ~/.ssh/control && chmod 700 ~/.ssh/control
```

Now `ssh chimebox-dev` is shorter and faster.

## Step 7 — Hand off to Ansible

You're ready to provision the chimebox. From your workstation, in the
chimebox repo:

```sh
cd pi/ansible
cp inventory.example.ini inventory.ini
# Edit inventory.ini to match your Pi's hostname/IP:
#   chimebox-dev ansible_host=chimebox-dev.local ansible_user=bryan

ansible-playbook -i inventory.ini playbook.yml
```

See [`pi/ansible/README.md`](./ansible/README.md) for what the playbook
does and how to run it.

## Troubleshooting

**Pi doesn't boot (no green LED, no HDMI signal):**
- Wrong power supply. Use the official 27W USB-C unit.
- microSD seated wrong, or card is dead.
- microSD wasn't successfully written. Re-flash with Imager.

**Boots but no Ethernet/Wi-Fi:**
- Check the configured Wi-Fi SSID/password in Imager settings.
- For Ethernet, try a different cable and another switch port.

**SSH connects but asks for a password:**
- Public key not installed correctly. Run `ssh-copy-id` from your
  workstation, or re-flash and double-check the Imager Services tab.

**`chimebox-dev.local` doesn't resolve:**
- mDNS may be disabled on your router or by Windows-style network
  configuration. Use the raw IP address from your router's lease table
  instead.

**Pi runs hot / throttles:**
- Pi 5 *needs* an active cooler. Without it, the SoC hits 80°C and starts
  throttling within minutes. Add the official Active Cooler or a
  case+fan combo.

## Next: NVMe migration (when your SSD arrives)

Two paths:

1. **Reflash + reprovision (recommended)**: re-do steps 2–7 with the NVMe
   instead of microSD. Ansible re-runs are idempotent; nothing to lose.
   Push your prepared disks back via `scripts/push-disks.sh`.

2. **Clone microSD to NVMe**: the Raspberry Pi OS desktop variant has a
   "SD Card Copier" tool, or use `dd` from another Linux box. More
   error-prone; only do this if you have customizations not captured by
   Ansible.

Either way, the swap takes ~10 minutes. The Ansible playbook is the
source of truth for what should be on the device.
