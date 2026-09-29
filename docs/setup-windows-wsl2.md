# Lab machine setup: Windows 11 + WSL2 + Docker Engine

Target: your Windows 11 Pro PC (i9-12900K, 32 GB RAM, 4 TB NVMe). Every lab runs
**inside WSL2 Ubuntu**, using plain Docker Engine (not Docker Desktop).

> **Nutanix analogy:** WSL2 is a small Linux VM that Windows runs on its built-in hypervisor
> (the same one Hyper-V uses). Think of it as a single "CVM-like" Linux VM that hosts our labs.
> Docker then runs containers inside that VM, and kind runs Kubernetes "nodes" as those containers.
>
> ```
> Windows 11 ─▶ WSL2 VM (Ubuntu) ─▶ Docker Engine ─▶ kind node containers ─▶ your pods
> ```

Sources, checked 2026-09-29:
- WSL configuration (`.wslconfig`, `wsl.conf`, systemd, `nestedVirtualization`):
  <https://learn.microsoft.com/en-us/windows/wsl/wsl-config>
- Docker Engine on Ubuntu: <https://docs.docker.com/engine/install/ubuntu/>
- Linux post-install steps (docker group): <https://docs.docker.com/engine/install/linux-postinstall/>
- kind known issues (inotify limits): <https://kind.sigs.k8s.io/docs/user/known-issues/>

---

## 0. Confirm hardware virtualization is on (PowerShell)

Your inventory showed `VirtualizationFirmwareEnabled: False`, but
`VirtualizationBasedSecurityStatus: 2` means VBS is **running**. VBS runs on the Windows
hypervisor, and that hypervisor takes over VT-x. Once it has, Windows reports the firmware flag
as False. To confirm, run:

```powershell
systeminfo | Select-String "Hyper-V|hypervisor"
```

If you see **"A hypervisor has been detected"**, VT-x is on and nothing needs changing. If
you don't, enable *Intel Virtualization Technology (VT-x)* in the BIOS/UEFI setup.

## 1. Update WSL and make Ubuntu the default distro (PowerShell)

```powershell
wsl --update
wsl --version                  # you want a recent WSL 2.x from the Microsoft Store
wsl --set-default Ubuntu       # docker-desktop is currently your default distro
wsl -l -v
```

**Why:** we need a recent WSL for systemd support. Without Ubuntu as the default, `wsl`
opens the Docker Desktop utility distro, which isn't meant for interactive use.

## 2. Take Docker Desktop out of the picture

You chose plain Docker Engine inside WSL2. Two Docker installs fighting over the `docker`
command is a common source of confusion, so do **one** of these:

- **Recommended:** uninstall Docker Desktop (*Settings → Apps → Installed apps*).
- **Or** keep it installed but not running: in Docker Desktop, turn off *Start Docker Desktop
  when you sign in*, turn off *Settings → Resources → WSL integration* for Ubuntu, then quit it.

**Why:** with WSL integration on, Docker Desktop injects its own `docker` CLI into Ubuntu that
talks to its own daemon, so the labs could end up using the wrong Docker.

## 3. (Optional for Tier 1) Size the WSL2 VM, in `%UserProfile%\.wslconfig`

By default WSL2 gets **50% of RAM (16 GB)**, which is plenty for Tier 1. Leave it unless you
need to change it. For reference, this is what Tier 2 (KubeVirt) will use:

```ini
[wsl2]
memory=20GB
processors=16
# Default is already true on Windows 11; shown so you know the setting exists.
nestedVirtualization=true
```

Apply with `wsl --shutdown` in PowerShell, then reopen Ubuntu.

## 4. Enable systemd in Ubuntu (Ubuntu terminal)

```bash
cat /etc/wsl.conf 2>/dev/null        # look first - it may already say systemd=true
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

In PowerShell run `wsl --shutdown`, then reopen Ubuntu and check:

```bash
ps -p 1 -o comm=     # should print: systemd
```

**Why:** with systemd running, Docker starts automatically as a normal service, the same way it
would on a real Linux server.

## 5. Install Docker Engine from Docker's apt repository (Ubuntu)

These steps come straight from the Docker docs linked above.

```bash
# Remove any conflicting distro packages (it's fine if none are installed)
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc | cut -f1)

# Trust Docker's signing key - why: apt verifies every package against it
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Let your user run Docker without `sudo`:

```bash
sudo usermod -aG docker "$USER"
newgrp docker            # or close and reopen the terminal
docker run --rm hello-world
```

> **Security note:** membership of the `docker` group is effectively root on this Linux VM,
> because anyone who can start containers can mount the host filesystem. That's acceptable on a
> personal lab VM. On a shared server, treat it like handing out the root password.

Check the cgroup version:

```bash
docker info --format 'cgroup v{{.CgroupVersion}}'     # expect: cgroup v2
```

If it prints `v1`, `labctl` detects that and applies a compatibility setting automatically.
Kubernetes v1.35+ refuses cgroup v1 by default.

## 6. Raise inotify limits (Ubuntu)

```bash
sudo tee /etc/sysctl.d/99-kind.conf >/dev/null <<'EOF'
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
sudo sysctl --system >/dev/null
```

**Why:** each kind node runs systemd, kubelet and containerd, and all of them watch files.
Ubuntu's default limits are too small for a 3-node kind cluster. When you hit them, the error is
a confusing "too many open files" (see kind's known issues).

## 7. Clone the repo into the Linux filesystem (Ubuntu)

```bash
sudo apt install -y git python3
cd ~
git clone <your-repo-url> Learning-Kubernetes
cd Learning-Kubernetes
```

**Why `~` and not `/mnt/c/...`:** files under `/mnt/c` cross the Windows/Linux boundary and are
much slower. They can also have odd permissions that break the executable bit on scripts.

## 8. Install the pinned tools and check everything

```bash
./labctl install-tools    # kind + kubectl into ~/.local/bin, SHA-256 verified
./labctl doctor
./labctl cluster up
./labctl list
```

The `kubectl` you already have on the Windows side came with Docker Desktop. Inside WSL, the
labs use the Linux `kubectl` installed above, and `./labctl doctor` shows which version is on
your PATH.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `Cannot connect to the Docker daemon` | `sudo systemctl start docker`; check `ps -p 1 -o comm=` says `systemd` |
| `permission denied ... docker.sock` | You're not in the docker group yet: `newgrp docker` or reopen the terminal |
| kind nodes stuck `NotReady`, "too many open files" | Step 6 |
| `labctl cluster up` warns about cgroup v1 | Harmless; the compatibility setting is applied automatically |
| Everything is slow | Is the repo under `/mnt/c`? Move it to `~` |
