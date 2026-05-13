{ pkgs, ... }:

{
  imports = [
    ../../modules/common.nix
    ../../modules/core.nix
    ../../modules/security.nix
    ../../modules/login.nix
    ../../modules/amdgpu.nix
    ../../modules/hyprland.nix
    ../../modules/wayvnc.nix
    ../../modules/github-repo-clone.nix
    ../../modules/ssh-server.nix
  ];

  # Bootloader: systemd-boot on UEFI/GPT (Q35 + OVMF on Proxmox).
  # Requires the VM to be (re)created with `machine: q35` and `bios: ovmf`
  # before this config will boot. hardware-configuration.nix must also
  # have a fileSystems."/boot" entry for the ESP — regenerate with
  # `nixos-generate-config --root /mnt` during install.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable serial console for Proxmox xterm.js + disable CPU mitigations.
  # mitigations=off bypasses Spectre/Meltdown/etc. workarounds on Zen 3,
  # reclaiming ~5-15% CPU. Acceptable here because this is a single-tenant
  # VM running only trusted workloads — do NOT use on multi-tenant hosts.
  #
  # video=DP-1:1920x1080@60e forces amdgpu's DP-1 connector ON even though
  # no monitor is physically wired to the iGPU outputs. The `e` suffix is
  # documented in admin-guide/kernel-parameters.txt and tells DRM to bring
  # the connector up with a synthesized EDID at the given mode. This is
  # what gives Hyprland a real KMS output to render to once the Proxmox
  # `vga: none` change removes virtio-gpu — amdgpu then becomes the only
  # DRM device, so all rendering, screencopy, and VAAPI H.264 encode stay
  # on a single GPU (no cross-device DMA-BUF, no llvmpipe fallback).
  #
  # drm.edid_firmware=DP-1:edid/1920x1080.bin tells the kernel to feed
  # amdgpu's Display Core a real EDID blob for the spoofed connector.
  # Without it, DCN re-probes every ~3s with "No EDID found on DP-1"
  # spam in dmesg. The .bin file is provided by edid-generator via
  # hardware.firmware below — CONFIG_DRM_LOAD_EDID_FIRMWARE=y only ships
  # the loader, not the blobs (the kernel-built EDIDs were removed in v6.5
  # when their assembler trick stopped working with modern linkers).
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
    "mitigations=off"
    "video=DP-1:1920x1080@60e"
    "drm.edid_firmware=DP-1:edid/1920x1080.bin"
  ];

  # Ship the 1920x1080 EDID blob referenced above. edid-generator builds
  # binary EDIDs from Xorg modelines and lays them out at the exact path
  # the kernel firmware loader searches (lib/firmware/edid/*.bin), so it
  # composes cleanly with hardware.enableRedistributableFirmware = true
  # from modules/amdgpu.nix.
  hardware.firmware = [ pkgs.edid-generator ];

  # Pin CPU at max clock — eliminates frequency-scaling latency spikes
  # (typically 5-40 ms) during video encoding, which manifest as stream
  # stutters. Costs ~5W idle power on the host.
  powerManagement.cpuFreqGovernor = "performance";

  # Networking
  networking.hostName = "clematis";
  networking.networkmanager.enable = true;

  # VM-specific group memberships (universals come from modules/common.nix):
  # render — Mesa/GBM access for GPU passthrough; uinput — synthetic input
  # devices for wayvnc/Sunshine.
  users.users.reginleif88.extraGroups = [ "render" "uinput" ];


  # TCP buffer headroom for sustained H.264 streaming bursts. Default
  # tcp_wmem max is 4 MiB which is fine for ~500 kbps average wayvnc
  # traffic but can stall on full-screen scroll bursts (≥10 Mbps for a
  # second or two). 8 MiB gives the kernel room to absorb a burst
  # without applying back-pressure to wayvnc's encoder. Memory is
  # only consumed when actually buffered, so this is essentially free.
  boot.kernel.sysctl = {
    "net.core.rmem_max"   = 8388608;
    "net.core.wmem_max"   = 8388608;
    "net.ipv4.tcp_rmem"   = "4096 87380 8388608";
    "net.ipv4.tcp_wmem"   = "4096 65536 8388608";
  };

  # Host-specific sops secrets (universals in modules/common.nix)
  sops.secrets = {
    "wayvnc_password" = {
      owner = "reginleif88";
    };
    "cloudflare_dns_token" = {
      # Read by lego (the ACME DNS-01 backend). File must contain
      # ONLY the raw Cloudflare API token — no `KEY=` prefix. The
      # token needs `Zone:DNS:Edit` scoped to the relevant zone.
      owner = "acme";
    };
  };

  # ── QEMU guest agent (Proxmox integration) ────────────────────────
  services.qemuGuest.enable = true;

  system.stateVersion = "25.11";
}
