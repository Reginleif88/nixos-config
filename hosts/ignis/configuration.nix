{ config, lib, ... }:

# `ignis` — the Yggdrasil Obsidian server (modules/ignis.nix) running on a public
# OVH KVM VPS. Adapted from hosts/clematis (the Proxmox VM that first ran Ignis).
# What changed vs clematis, and why:
#   - GRUB/BIOS instead of systemd-boot: the VPS boots in legacy BIOS mode.
#   - disko owns the disk (hosts/ignis/disko.nix); no manual partitioning.
#   - AMD GPU passthrough + the QEMU guest-agent are gone (no passthrough GPU
#     here; the guest-agent was Proxmox integration). virtio DRIVERS stay in
#     hardware-configuration.nix — the box needs them to boot.
#   - No TTY autologin (modules/login.nix dropped): this is a headless public
#     box reached over SSH, so autologin would be a foothold, not a convenience.
#   - Public firewall is SSH + 443 only. The clematis LAN rules that opened
#     :8080/:8081 to the Proxmox host (192.168.1.150) are gone — there is no LAN
#     and no Proxmox host here. Ignis (:8080), code-server (:8081), and Actual
#     Budget (:8082) stay firewalled off the internet and are reached via a
#     Cloudflare Tunnel set up out-of-band; the tunnel dials OUTBOUND, so it
#     needs no inbound port.

{
  imports = [
    ../../modules/common.nix
    ../../modules/core.nix
    ../../modules/security.nix
    ../../modules/ssh-server.nix
    ../../modules/ignis.nix
    ../../modules/code-server.nix
    ../../modules/actual.nix
  ];

  # Bootloader: GRUB in BIOS mode. The VPS has no UEFI (/sys/firmware/efi absent),
  # so systemd-boot/EFI is not an option. The install DISK is not named here on
  # purpose: disko (hosts/ignis/disko.nix) sees the EF02 bios_grub partition and
  # registers the parent disk into boot.loader.grub.devices itself. Setting
  # `device` here as well would list the disk twice and trip GRUB's
  # duplicate-device (mirroredBoots) assertion.
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
  };

  # zram swap: the box has 7.6 GiB RAM and no disk swap partition (disko keeps the
  # layout minimal). A compressed RAM swap gives headroom for the Ignis build
  # (npm ci + chromium fetch) without carving disk.
  zramSwap.enable = true;
  nix.gc.options = "--delete-older-than 14d";

  # ── Networking ────────────────────────────────────────────────────────────
  networking.hostName = "ignis";
  networking.networkmanager.enable = true; # ens3 gets its address via DHCP

  # The public firewall exposes SSH only. Cloudflare Tunnel dials local origins
  # outbound, so no web port is opened here.

  users.users.reginleif88 = {
    hashedPasswordFile = config.sops.secrets.ignis_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKaOT9ISVrvhVHqAJ2vUg9KwCWZR5wJGGEJNngUdx51 reginleif88@ignis-vps"
    ];
  };

  # sops age key lives at a root-owned system path here, not under the user's
  # home (common.nix's default). It is delivered by `nixos-anywhere --extra-files`,
  # which extracts as root — landing it in ~/.config would pre-create the user's
  # home root-owned before the account exists and break gh/keyring. sops decrypts
  # as root at boot from either path.
  sops.age.keyFile = lib.mkForce "/var/lib/sops-nix/keys.txt";

  sops.secrets.ignis_password_hash = {
    neededForUsers = true;
  };

  system.stateVersion = "25.11";
}
