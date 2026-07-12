{ pkgs, inputs, lib, ... }:

{
  imports = [
    ../../modules/common.nix
    ../../modules/core.nix
    ../../modules/security.nix
    ../../modules/antivirus.nix
    ../../modules/login.nix
    ../../modules/services.nix
    ../../modules/nvidia.nix
    ../../modules/hyprland.nix
    ../../modules/virtualisation.nix
    ../../modules/gaming.nix
    ../../modules/huion-ble.nix
    ../../modules/github-repo-clone.nix
  ];

  # CachyOS kernel (BORE scheduler, sched-ext, BBRv3, x86-64-v3)
  nixpkgs.overlays = [
    inputs.nix-cachyos-kernel.overlays.pinned
  ];
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore;

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Cap kernels kept on the 1 GB ESP. Without this, systemd-boot copies a
  # kernel + (fat NVIDIA) initrd per generation and eventually fills /boot,
  # failing the bootloader install with ENOSPC. This limits ESP entries only;
  # Nix profile generations are retained independently until GC.
  boot.loader.systemd-boot.configurationLimit = 5;

  # Networking
  networking.hostName = "hyacinth";
  networking.networkmanager.enable = true;

  # Workstation-specific group memberships (universals come from modules/common.nix)
  users.users.reginleif88.extraGroups = [ "libvirtd" "kvm" "docker" ];

  # Windows 11 VM managed by Docker (dockur/windows).
  virtualisation.oci-containers = {
    backend = "docker";
    containers.windows = {
      image = "dockurr/windows";
      environment = {
        VERSION = "11";
        RAM_SIZE = "16G";
        CPU_CORES = "6";
        CPU_MODEL = "host";
        DISK_SIZE = "256G";
        ALLOCATE = "Y";
      };
      devices = [
        "/dev/kvm:/dev/kvm"
        "/dev/net/tun:/dev/net/tun"
      ];
      ports = [
        "127.0.0.1:8006:8006"
        "127.0.0.1:3389:3389/tcp"
        "127.0.0.1:3389:3389/udp"
      ];
      volumes = [ "/var/lib/windows:/storage" ];
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--stop-timeout=120"
      ];
    };
  };

  systemd.tmpfiles.rules = [ "d /var/lib/windows 0750 root docker -" ];
  systemd.services.docker-windows.serviceConfig.Restart = lib.mkForce "always";

  # Disable unwanted ALSA audio devices (NVIDIA GPU HDMI, Corsair ST100)
  services.pipewire.wireplumber.extraConfig."51-disable-unwanted-audio" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "device.description" = "~GP104.*"; }
          { "device.description" = "~.*ST100.*"; }
        ];
        actions = {
          "update-props" = {
            "device.disabled" = true;
          };
        };
      }
    ];
  };

  # Auto-connect Edifier R1280DBs on login
  systemd.user.services.bt-connect-edifier = {
    description = "Auto-connect Edifier R1280DBs Bluetooth speaker";
    after = [ "bluetooth.target" ];
    wants = [ "bluetooth.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bluez}/bin/bluetoothctl connect 08:F0:B6:51:73:7E";
      Restart = "on-failure";
      RestartSec = 5;
      RestartMaxDelaySec = 30;
    };
  };

  system.stateVersion = "25.11";
}
