{ config, pkgs, inputs, lib, ... }:

{
  imports = [
    ../../modules/core.nix
    ../../modules/security.nix
    ../../modules/login.nix
    ../../modules/amdgpu.nix
    ../../modules/desktop-xfce.nix
    ../../modules/kasmvnc.nix
    inputs.sops-nix.nixosModules.sops
  ];

  # KasmVNC owns its own Xkasmvnc display (:1) — LightDM and autologin
  # (set by desktop-xfce.nix for the Sunshine/X-capture setup) would
  # compete for a real X server we no longer have, so suppress them.
  services.xserver.displayManager.lightdm.enable = lib.mkForce false;
  services.displayManager.autoLogin.enable = lib.mkForce false;

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
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "uinput" ];
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
      "kasmvnc_password" = {
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

      gh auth login --with-token --insecure-storage < "$TOKEN_FILE"

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

  # ── QEMU guest agent (Proxmox integration) ────────────────────────
  services.qemuGuest.enable = true;

  # ── SSH server ─────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  system.stateVersion = "25.11";
}
