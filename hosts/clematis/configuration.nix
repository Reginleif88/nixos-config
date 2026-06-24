{ pkgs, ... }:

{
  imports = [
    ../../modules/common.nix
    ../../modules/core.nix
    ../../modules/security.nix
    ../../modules/login.nix
    ../../modules/amdgpu.nix
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
  # Note: this VM is headless GPU-compute only — no compositor and no
  # display. The amdgpu render node (/dev/dri/renderD128) is reached
  # directly via the `render` group, so the old `video=DP-1` connector
  # spoof + drm.edid_firmware blob (which only existed to give Hyprland a
  # KMS output) are deliberately gone.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
    "mitigations=off"
  ];

  # Pin CPU at max clock — eliminates frequency-scaling latency spikes on
  # bursty compute. Costs ~5W idle power on the host.
  powerManagement.cpuFreqGovernor = "performance";

  # Networking
  networking.hostName = "clematis";
  networking.networkmanager.enable = true;

  # Ignis dev server (apps/ignis-server, `npm run dev:run`) listens on 8080.
  # The base firewall (modules/security.nix) only allows SSH + ICMP, so open
  # 8080 here to make the browser client reachable from the LAN. Host-scoped
  # because Ignis runs only on this VM.
  networking.firewall.allowedTCPPorts = [ 8080 ];

  # VM-specific group memberships (universals come from modules/common.nix):
  # render — Mesa/GBM access to the passed-through amdgpu render node.
  users.users.reginleif88.extraGroups = [ "render" ];

  # core.nix enables services.flatpak, which asserts xdg.portal.enable. On
  # the graphical hosts the Hyprland module wires portals up transitively;
  # this headless VM has no compositor, so enable a minimal portal + gtk
  # backend here purely to satisfy Flatpak's requirement. (The Flatpak apps
  # themselves are GUI-only and won't run headless — kept only because
  # core.nix is shared unchanged across hosts.)
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "gtk" ];
  };

  # ── QEMU guest agent (Proxmox integration) ────────────────────────
  services.qemuGuest.enable = true;

  system.stateVersion = "25.11";
}
