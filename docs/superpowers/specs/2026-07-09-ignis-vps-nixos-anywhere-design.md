# Design: `ignis` host — NixOS-anywhere unattended install on OVH VPS

**Date:** 2026-07-09
**Target:** `ubuntu@91.134.137.184` (OVH KVM VPS) → wipe Ubuntu 26.04, install NixOS
**Reference host:** `clematis` (the existing host that imports `modules/ignis.nix`)

## Goal

Provision a fresh public VPS with a NixOS config derived from `clematis`, running the
Ignis Obsidian-vault server, via `nixos-anywhere` in a single unattended pass — adapting
the config from a home-LAN Proxmox VM to a public cloud box.

## Target facts (inspected read-only, 2026-07-09)

| Property | Value |
|---|---|
| OS (to be wiped) | Ubuntu 26.04 LTS |
| Virt / provider | KVM (OVH) |
| Arch / CPU / RAM | x86_64, 4 vCPU, 7.6 GiB |
| Disk | single 75 G, `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-0-0-0` (`/dev/sda`) |
| Boot mode | **BIOS/legacy** (no `/sys/firmware/efi`) |
| Network | public `/32` IPv4 + IPv6 on `ens3` (DHCP), no private LAN |
| Access now | `ubuntu` user, passwordless sudo, **empty `authorized_keys`** (password login only) |

## Decisions (confirmed with user)

1. **Host name:** `ignis` (`nixosConfigurations.ignis`, `hosts/ignis/`).
2. **Access after install:** generate a fresh **ed25519 keypair on hyacinth**, authorize the
   pubkey for `reginleif88`, keep the private key on hyacinth (`~/.ssh/ignis_vps`). Also set a
   `hashedPassword` for `reginleif88` (OVH-console / sudo fallback). `PasswordAuthentication = false`
   (key-only over SSH); `PermitRootLogin` stays `no`.
3. **Exposure:** public firewall = **SSH + TCP 443 only**. Ignis (`:8080`) / code-server (`:8081`)
   stay firewalled off the internet; reached later via a Cloudflare tunnel the user sets up
   himself (tunnel dials outbound, needs no inbound port). LAN-scoped firewall rules to the
   Proxmox host (`192.168.1.150`) are **removed** — that host does not exist here.
4. **Archived from the clematis config:** AMD GPU passthrough (`modules/amdgpu.nix`, `render`
   group), QEMU **guest-agent** service (`services.qemuGuest`). Virtio *kernel drivers* are
   kept — the box cannot boot without them.
5. **No autologin:** `modules/login.nix` (getty autologin) is dropped.
6. **Bootloader:** GRUB (BIOS), not systemd-boot (the box boots legacy BIOS).

## What is kept from clematis ("keep the rest")

`modules/common.nix`, `modules/core.nix`, `modules/security.nix`, `modules/ssh-server.nix`,
`modules/ignis.nix`, `modules/code-server.nix`, the headless `xdg.portal` shim, serial console
(`console=ttyS0,115200` — useful for the OVH KVM console), `mitigations=off`, and the
`performance` CPU governor.

## New files

```
hosts/ignis/default.nix                 # imports configuration + hardware
hosts/ignis/configuration.nix           # adapted from hosts/clematis/configuration.nix
hosts/ignis/hardware-configuration.nix  # virtio modules, hostPlatform (no fileSystems — disko owns them)
hosts/ignis/disko.nix                   # GPT: 1M BIOS-boot (EF02) + ext4 root 100%
```

### `disko.nix`
GPT layout, disk addressed by stable `by-id` path:
- `boot` — 1 MiB, type `EF02` (BIOS boot partition for GRUB-on-GPT)
- `root` — 100%, ext4, mounted `/`

Swap: none on disk; `zramSwap.enable = true` in the host config (helps npm/chromium builds on 7.6 GiB).

### `hardware-configuration.nix`
```nix
boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
```
No `fileSystems`/`swapDevices` (disko generates them); no `qemu-guest.nix` profile import.

### `configuration.nix` (delta from clematis)
- imports: drop `amdgpu.nix`, `login.nix`; add `inputs.disko.nixosModules.disko` + `./disko.nix`
- bootloader: `boot.loader.grub = { enable = true; device = "<by-id disk>"; efiSupport = false; }`;
  drop `systemd-boot` + `efi.canTouchEfiVariables`
- `networking.hostName = "ignis"`; keep NetworkManager (DHCP)
- `networking.firewall.allowedTCPPorts = [ 443 ]`; **remove** `firewall.extraCommands` LAN rules
- `services.openssh.settings.PasswordAuthentication = lib.mkForce false`
- `users.users.reginleif88 = { hashedPassword = "…"; openssh.authorizedKeys.keys = [ "ssh-ed25519 …" ]; }`
- drop `services.qemuGuest.enable`, drop `render` group membership
- keep the `xdg.portal` headless shim; `zramSwap.enable = true`
- `system.stateVersion = "25.11"`

## Flake changes
- add input `disko` (`github:nix-community/disko`, `follows` nixpkgs)
- add `nixosConfigurations.ignis = mkHost "ignis" ./hosts/ignis;`

## Secrets bootstrap
Ship the existing sops **age key** (`~/.config/sops/age/keys.txt`, pub
`age1um3qdra5aptne5wrc3cdanj2lkwu8me30kp99gq5eufg5tslrypqufrj20`) to the target via
`nixos-anywhere --extra-files`, landing at
`/home/reginleif88/.config/sops/age/keys.txt`, so sops-nix decrypts `secrets/secrets.yaml`
on the new box. SSH access does **not** depend on secrets — a sops failure would not lock us out.

## Install command (from hyacinth, same arch → build locally, copy closure)
```
SSHPASS='***' nix run github:nix-community/nixos-anywhere -- \
  --flake .#ignis \
  --target-host ubuntu@91.134.137.184 \
  --env-password \                # sshpass with $SSHPASS for the ubuntu password
  --extra-files <staged-age-key-dir>
```
`nixos-anywhere` kexecs the target into its installer, partitions with disko, installs, copies
extra-files, and reboots.

## Post-install verification
1. `ssh -i ~/.ssh/ignis_vps reginleif88@91.134.137.184` succeeds (key-only).
2. `uname -a` shows NixOS; `nixos-rebuild` present; `systemctl is-system-running`.
3. Password auth refused; root SSH refused.
4. Firewall: only 22 + 443 reachable; `ss -tlnp` shows 8080/8081 bound but firewalled.
5. `sops`-managed secrets present under `/run/secrets` (if age key shipped correctly).

## Known follow-ups (NOT part of this install — user handles later)
- Ignis app won't fully serve until the private **Yggdrasil vault** is cloned to
  `~/Documents/Yggdrasil`, `gh` is authenticated, and the vault `.env` exists. `ignis.service`
  will restart-loop harmlessly until then. Run `scripts/target-setup.sh ignis` on the box for
  the sops/secrets side.
- User sets up the **Cloudflare tunnel** (`cloudflared`) on the box for `notes.reginleif.xyz`.
- Consider `chown reginleif88` on the shipped age key for manual `sops edit` on the box.

## Risks
- **Lockout** — mitigated by ed25519 key + password + OVH KVM console + serial console.
- **Wrong disk / data loss** — user confirmed backup taken; single disk, addressed by stable by-id.
- **BIOS boot correctness** — EF02 bios_boot partition + GRUB `device = <disk>`, `efiSupport = false`.
- **`mitigations=off` on a public box** — inherited from clematis ("keep the rest"); single-tenant VM, acceptable but noted.
