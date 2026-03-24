<div align="center">

# nixos-config

Personal NixOS system configuration for a Hyprland desktop, managed with Nix Flakes and Home Manager.

![NixOS](https://img.shields.io/badge/NixOS-5277C3?style=flat&logo=nixos&logoColor=white)
![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=flat&logo=hyprland&logoColor=black)
![Wayland](https://img.shields.io/badge/Wayland-FFBC00?style=flat&logo=wayland&logoColor=black)
![Home Manager](https://img.shields.io/badge/Home_Manager-5277C3?style=flat&logoColor=white)
![Flakes](https://img.shields.io/badge/Flakes-5277C3?style=flat&logoColor=white)

Gruvbox Dark themed, dual-monitor, NVIDIA-optimized

</div>

---

## What's Included

| Category | Tools |
|---|---|
| Window Manager | Hyprland, Hyprbars |
| Status Bar | Quickshell |
| Terminal | Kitty |
| Shell | Zsh, Oh My Zsh, Starship |
| App Launcher | Walker, Elephant |
| Notifications | Mako |
| Clipboard | cliphist |
| Screenshots | grimblast |
| File Manager | Thunar |
| Image Viewer | swayimg |
| Browsers | Zen Browser, Google Chrome |
| Development | VS Code, Claude Code, Gemini CLI, Node.js, Bun, direnv |
| Containers | Docker, Podman |
| Virtualisation | KVM / QEMU, libvirt, virt-manager |
| Gaming | Steam, DawnProton, GameScope, GeForce NOW |
| GPU | NVIDIA with suspend/hibernate and VRAM preservation |
| Secrets | sops-nix with age encryption |
| Theme | Gruvbox Material Dark |
| Kernel | CachyOS BORE (sched-ext, BBRv3, x86-64-v3) |

---

## Repository Structure

```
nixos-config/
├── flake.nix                       # Flake inputs and system config
├── flake.lock
├── hosts/
│   └── desktop/
│       ├── default.nix             # Host entry point
│       ├── configuration.nix       # System-level config
│       └── hardware-configuration.nix
├── modules/
│   ├── core.nix                    # Base packages, locale, boot
│   ├── hyprland.nix                # Compositor and desktop components
│   ├── nvidia.nix                  # GPU drivers, modesetting, VRAM
│   ├── gaming.nix                  # Steam, Proton, GameScope
│   ├── virtualisation.nix          # KVM, Docker, Podman
│   ├── services.nix                # PipeWire, Bluetooth, Thunar, Flatpak
│   ├── security.nix                # GNOME Keyring, sops-nix
│   └── login.nix                   # Auto-login TTY
├── home/
│   ├── default.nix                 # Home Manager entry point
│   ├── shell.nix                   # Zsh, Starship prompt
│   ├── kitty.nix                   # Terminal config
│   ├── hyprland.nix                # Hyprland dotfile deployment
│   ├── quickshell.nix              # Status bar, Mako, Walker
│   ├── gtk.nix                     # GTK theming, fonts, cursors
│   ├── apps.nix                    # Desktop apps, VS Code, MIME types
│   ├── browser.nix                 # Zen Browser + user.js deployment
│   ├── ai.nix                      # Claude Code, Gemini CLI, Bun
│   └── git.nix                     # Git identity, GitHub CLI
├── dotfiles/
│   ├── hypr/                       # Hyprland configs (deployed via home.file)
│   ├── quickshell/bar/             # Quickshell QML bar + scripts
│   ├── xfce4/                      # Thunar config
│   └── zen-browser/user.js         # Zen Browser preferences
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

./scripts/target-setup.sh          # generates hardware config and decrypts age key
sudo nixos-rebuild switch --flake .#desktop
```

The `target-setup.sh` script handles:

1. Generating `hardware-configuration.nix` for the actual hardware
2. Decrypting the age key from `secrets/keys.txt.age` (you'll be prompted for the passphrase)
3. Encrypting secrets with sops (first time only, skipped if already encrypted in repo)

The age private key and encrypted secrets are both stored in the repo — the key is passphrase-protected, so you just need to remember one passphrase.

---

## License

[MIT](LICENSE)
