# nixos-config

Personal NixOS configuration managed with flakes and Home Manager. The active
hosts are a Hyprland desktop (`hyacinth`) and an OVH KVM VPS (`ignis`).

## Hosts

`hyacinth` owns the graphical stack: Hyprland, Quickshell, Gruvbar, Flatpak,
desktop applications, Docker-based Windows, and the host-specific hardware
configuration.

`ignis` is a headless public server. It uses disko for its legacy-BIOS GPT
layout, SSH, Ignis, code-server on loopback, and an outbound Cloudflare Tunnel.
The public firewall exposes SSH only.

## Install

Install NixOS with flakes enabled, then clone the repository:

```sh
nix-shell -p git sops age
git clone https://github.com/Reginleif88/nixos-config.git ~/Documents/nixos-config
cd ~/Documents/nixos-config
```

For an existing desktop installation, create or decrypt the user SOPS key and
initialize the encrypted secrets:

```sh
./scripts/target-setup.sh hyacinth
sudo nixos-rebuild switch --flake .#hyacinth
```

For `ignis`, disko and `nixos-anywhere` install the server. The host expects
the age key at `/var/lib/sops-nix/keys.txt`, so decrypt the passphrase-protected
key into an extra-files tree before deployment:

```sh
install -d -m 700 /tmp/ignis-extra/var/lib/sops-nix
age -d -o /tmp/ignis-extra/var/lib/sops-nix/keys.txt secrets/keys.txt.age
chmod 600 /tmp/ignis-extra/var/lib/sops-nix/keys.txt
nixos-anywhere --flake .#ignis --extra-files /tmp/ignis-extra root@IGNIS_HOST
```

The `ignis` disk identifier is declared in `hosts/ignis/disko.nix`; verify it
matches the target before installing. After changing encrypted values, run
`sops edit secrets/secrets.yaml` and rebuild the relevant host.

## Ownership

Home Manager owns the Hyprland Lua entry point, module ordering, Gruvbar plugin,
graphical-session user services, lock/idle configuration, and Quickshell files.
The Quickshell WebEngine sidebar is created only on workspace 1's monitor and
only while workspace 1 is active. Its temporary compatibility patch is kept in
`home/quickshell.nix` and should be removed when upstream Quickshell PR #351 is
merged.

The Windows container and its RDP client are manual lifecycle services:

```sh
sudo systemctl start docker-windows
systemctl --user start windows-desktop
systemctl --user stop windows-desktop
sudo systemctl stop docker-windows
```

The container is intentionally not configured to auto-start.

## Secrets and recovery

Keep the age key private. `scripts/target-setup.sh` refuses symlinks, creates
the key directory as `0700`, writes the key as `0600`, and validates the final
mode. If the graphical session fails, switch to a TTY, keep the previous NixOS
generation available, and use `sudo nixos-rebuild switch --rollback` or boot a
known-good generation before changing multiple graphics variables at once.

## Validation and updates

```sh
nix fmt
nix flake check --no-build --show-trace
statix check .
deadnix --fail .
shellcheck scripts/*.sh dotfiles/quickshell/bar/scripts/*.sh
```

Update inputs deliberately with `nix flake update`, then rerun the validation
commands and test the host before committing `flake.lock`. State versions are
compatibility settings and should not be changed during ordinary updates.
