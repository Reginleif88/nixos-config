{ config, pkgs, inputs, lib, ... }:

{
  imports = [
    ../../modules/core.nix
    ../../modules/security.nix
    ../../modules/login.nix
    ../../modules/services.nix
    ../../modules/nvidia.nix
    ../../modules/hyprland.nix
    ../../modules/virtualisation.nix
    ../../modules/gaming.nix
    inputs.sops-nix.nixosModules.sops
  ];

  # CachyOS kernel (BORE scheduler, sched-ext, BBRv3, x86-64-v3)
  # TODO: re-enable when lantian cache catches up
  # nixpkgs.overlays = [
  #   inputs.nix-cachyos-kernel.overlays.pinned
  # ];
  # boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore;

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "desktop";
  networking.networkmanager.enable = true;

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
  };

  # Timezone — change to your actual timezone
  time.timeZone = "Europe/Paris";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Nix settings
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    download-buffer-size = 268435456; # 256 MiB
    substituters = [
      "https://cache.nixos.org"
      "https://attic.xuyh0120.win/lantian"
    ];
    trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
  };

  # User account
  users.users.reginleif88 = {
    isNormalUser = true;
    description = "reginleif88";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "libvirt" "kvm" "docker" ];
    shell = pkgs.zsh;
  };

  # Enable zsh system-wide (required for user shell)
  programs.zsh.enable = true;

  # sops-nix secrets
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.keyFile = "${config.users.users.reginleif88.home}/.config/sops/age/keys.txt";
    secrets = {
      "github_token" = {
        owner = "reginleif88";
      };
      "github_repos" = {
        owner = "reginleif88";
      };
    };
  };

  system.stateVersion = "25.11";
}
