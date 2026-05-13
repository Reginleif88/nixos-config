{ ... }:

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
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
    "mitigations=off"
  ];

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
