{ pkgs, inputs, ... }:

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

  # Networking
  networking.hostName = "hyacinth";
  networking.networkmanager.enable = true;

  # Workstation-specific group memberships (universals come from modules/common.nix)
  users.users.reginleif88.extraGroups = [ "libvirt" "kvm" "docker" ];

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
