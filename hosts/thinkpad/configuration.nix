{ config, pkgs, inputs, lib, ... }:

{
  imports = [
    ../../modules/core.nix
    ../../modules/security.nix
    ../../modules/login.nix
    ../../modules/services.nix
    ../../modules/nvidia-prime.nix
    ../../modules/hyprland.nix
    inputs.sops-nix.nixosModules.sops
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
  networking.hostName = "thinkpad";
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

  # Timezone
  time.timeZone = "Europe/Paris";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "ventoy-1.1.10"
  ];

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
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
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
      "zlm_api_key" = {
        owner = "reginleif88";
      };
    };
  };

  # Clone private GitHub repos after network is online
  systemd.services.clone-github-repos = {
    description = "Clone private GitHub repos into ~/Documents";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "reginleif88";
      Group = "users";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      StartLimitBurst = 3;
      Environment = [
        "HOME=/home/reginleif88"
        "GH_CONFIG_DIR=/home/reginleif88/.config/gh"
      ];
    };

    path = [ pkgs.gh pkgs.git pkgs.coreutils ];

    script = ''
      TOKEN_FILE="/run/secrets/github_token"
      REPOS_FILE="/run/secrets/github_repos"
      REPOS_DIR="/home/reginleif88/Documents"

      if [ ! -f "$TOKEN_FILE" ] || [ ! -f "$REPOS_FILE" ]; then
        echo "Secrets not available yet, exiting"
        exit 1
      fi

      gh auth login --with-token < "$TOKEN_FILE"

      mkdir -p "$REPOS_DIR"
      for repo in $(cat "$REPOS_FILE"); do
        if [ ! -d "$REPOS_DIR/$repo" ]; then
          echo "Cloning Reginleif88/$repo..."
          gh repo clone "Reginleif88/$repo" "$REPOS_DIR/$repo"
        else
          echo "Skipping $repo (already exists)"
        fi
      done
    '';
  };

  # ── SSH server ──────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # ── Laptop-specific ────────────────────────────────────────────────

  # TLP power management with ThinkPad charge thresholds
  services.tlp = {
    enable = true;
    settings = {
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };

  # Intel thermal daemon
  services.thermald.enable = true;

  # Fingerprint reader (Synaptics Metallica)
  services.fprintd.enable = true;

  # Firmware updates
  services.fwupd.enable = true;

  # Lid switch behavior
  services.logind.settings.Login.HandleLidSwitch = "suspend";

  # Bluetooth: available but not powered on at boot
  hardware.bluetooth.powerOnBoot = lib.mkForce false;

  system.stateVersion = "25.11";
}
