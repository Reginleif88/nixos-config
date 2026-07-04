{ pkgs, ... }:

{
  imports = [
    ../../modules/common.nix
    ../../modules/core.nix
    ../../modules/security.nix
    ../../modules/login.nix
    ../../modules/amdgpu.nix
    ../../modules/ssh-server.nix
    ../../modules/ignis.nix
    ../../modules/code-server.nix
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

  # Ignis (modules/ignis.nix, :8080) and code-server (modules/code-server.nix,
  # :8081) are both origins for Cloudflare tunnels. cloudflared does NOT run in
  # this VM — it runs on the Proxmox HOST (192.168.1.150) and dials each origin at
  # this VM's LAN address (192.168.1.41:<port>). That traffic arrives on ens18, so
  # it is subject to the firewall — modules/security.nix keeps the base policy SSH
  # + ICMP only, which silently drops the tunnel's origin dials and surfaces as a
  # 502 Bad Gateway. Open each port to the Proxmox host ALONE so the tunnels reach
  # their origins without exposing the vault (or a code-server shell) to the rest
  # of the LAN. These append to the iptables nixos-fw chain because clematis uses
  # the default iptables firewall backend (no networking.nftables.enable). A
  # broader `networking.firewall.allowedTCPPorts = [ 8080 8081 ];` would also fix
  # the 502, but would let ANY LAN host reach the origins directly, bypassing
  # Cloudflare Access.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s 192.168.1.150 --dport 8080 -j nixos-fw-accept
    iptables -A nixos-fw -p tcp -s 192.168.1.150 --dport 8081 -j nixos-fw-accept
  '';

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
