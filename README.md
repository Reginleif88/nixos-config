<div align="center">

# nixos-config

Personal NixOS system configuration for a Hyprland desktop, managed with Nix Flakes and Home Manager.

![NixOS](https://img.shields.io/badge/NixOS-5277C3?style=flat&logo=nixos&logoColor=white)
![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=flat&logo=hyprland&logoColor=black)
![Wayland](https://img.shields.io/badge/Wayland-FFBC00?style=flat&logo=wayland&logoColor=black)
![Home Manager](https://img.shields.io/badge/Home_Manager-5277C3?style=flat&logoColor=white)
![Flakes](https://img.shields.io/badge/Flakes-5277C3?style=flat&logoColor=white)

Gruvbox Dark themed, multi-host (desktop, ThinkPad, and remote VM)

</div>

---

## What's Included

| Category | Tools |
|---|---|
| Window Manager | Hyprland, Gruvbar (custom titlebar plugin) |
| Status Bar | Quickshell (custom QML bar) |
| Terminal | Kitty |
| Shell | Zsh, Oh My Zsh, Starship |
| App Launcher | Fuzzel |
| Notifications | SwayNC |
| Clipboard | cliphist |
| Screenshots | grimblast |
| File Manager | Thunar |
| Image Viewer | swayimg |
| Browsers | Zen Browser, Google Chrome |
| Knowledge | Obsidian |
| Media | Spotify (Flatpak), Stremio (Flatpak), VLC |
| Privacy | ProtonVPN, ProtonMail Desktop |
| Development | VS Code, Claude Code, Gemini CLI, Node.js, Bun, direnv |
| Containers | Docker, Podman |
| Virtualisation | KVM / QEMU, libvirt, virt-manager |
| Android | scrcpy, escrcpy, Winboat |
| Gaming | Steam, DawnProton, GameScope, GeForce NOW |
| GPU | NVIDIA with suspend/hibernate and VRAM preservation; PRIME offload (ThinkPad) |
| Power & Hardware | TLP, thermald, fprintd, fwupd (ThinkPad) |
| Secrets | sops-nix with age encryption |
| Theme | Gruvbox Material Dark |
| Kernel | CachyOS BORE (sched-ext, BBRv3, x86-64-v3) |
| CI/CD | GitHub Actions (automated flake updates) |

---

## Repository Structure

```
nixos-config/
├── flake.nix                       # Flake inputs and system config
├── flake.lock
├── .github/
│   └── workflows/
│       └── flake-update.yml        # Automated daily flake.lock updates
├── hosts/
│   ├── hyacinth/
│   │   ├── default.nix             # Host entry point
│   │   ├── configuration.nix       # Desktop system config
│   │   └── hardware-configuration.nix
│   └── ignis/
│       ├── default.nix             # Host entry point
│       ├── configuration.nix       # VPS system config
│       └── hardware-configuration.nix
├── archive/                         # Decommissioned host configurations
├── modules/
│   ├── core.nix                    # Base packages, fonts, Flatpak
│   ├── hyprland.nix                # Compositor and desktop components
│   ├── nvidia.nix                  # GPU drivers, modesetting, VRAM
│   ├── nvidia-prime.nix            # PRIME offload, fine-grained power mgmt
│   ├── amdgpu.nix                  # AMD GPU stack for VM passthrough
│   ├── gaming.nix                  # Steam, Proton, GameScope
│   ├── virtualisation.nix          # KVM, Docker, Podman
│   ├── services.nix                # PipeWire, Bluetooth, Thunar, Flatpak
│   ├── security.nix                # GNOME Keyring, sops-nix
│   ├── wayvnc.nix                  # Headless Hyprland + noVNC bridge
│   └── login.nix                   # Auto-login TTY
├── home/
│   ├── default.nix                 # Home Manager entry point
│   ├── shell.nix                   # Zsh, Starship prompt
│   ├── kitty.nix                   # Terminal config
│   ├── hyprland.nix                # Hyprland dotfile deployment
│   ├── quickshell.nix              # Status bar, SwayNC, Fuzzel
│   ├── gtk.nix                     # GTK theming, fonts, cursors
│   ├── apps.nix                    # Desktop apps, VS Code, MIME types
│   ├── browser.nix                 # Zen Browser + user.js deployment
│   ├── ai.nix                      # Claude Code, Gemini CLI, Bun
│   └── git.nix                     # Git identity, GitHub CLI
├── plugins/
│   └── gruvbar/                    # Custom Hyprland titlebar plugin (C++)
├── dotfiles/
│   ├── claude/                     # Claude Code settings
│   ├── fuzzel/                     # App launcher config
│   ├── hypr/                       # Hyprland configs (deployed via home.file)
│   │   └── hosts/hyacinth/          # Per-host env, monitors, workspaces, settings
│   ├── quickshell/bar/             # Quickshell QML bar + scripts
│   ├── swaync/                     # Notification center config and theme
│   └── zen-browser/                # Zen Browser user.js and policies.json
├── secrets/
│   ├── .sops.yaml                  # sops-nix config
│   ├── keys.txt.age                # Passphrase-protected age private key
│   └── secrets.yaml                # Encrypted secrets (age)
├── overlays/
│   └── default.nix                 # Custom overlays
└── scripts/                        # Utility scripts
```

---

## Prerequisites

- **NixOS** with flakes enabled

---

## Installation

After a fresh NixOS install and first reboot:

```bash
nix-shell -p git sops age
git clone https://github.com/Reginleif88/nixos-config.git ~/Documents/nixos-config
cd ~/Documents/nixos-config

./scripts/target-setup.sh hyacinth # or ignis
sudo nixos-rebuild switch --flake .#hyacinth  # or .#ignis
```

The `target-setup.sh` script handles:

1. Decrypting the age key from `secrets/keys.txt.age` (you'll be prompted for the passphrase)
2. Encrypting secrets with sops (first time only, skipped if already encrypted in repo)

The age private key and encrypted secrets are both stored in the repo — the key is passphrase-protected, so you just need to remember one passphrase.

---

## License

[MIT](LICENSE)
