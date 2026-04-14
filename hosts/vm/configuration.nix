{ config, pkgs, inputs, lib, ... }:

{
  imports = [
    ../../modules/core.nix
    ../../modules/security.nix
    ../../modules/login.nix
    ../../modules/amdgpu.nix
    ../../modules/desktop-xfce.nix
    ../../modules/sunshine.nix
    ../../modules/moonlight-web-stream.nix
    inputs.sops-nix.nixosModules.sops
  ];

  # AMD iGPU (Radeon Vega 7) — no NVIDIA, so build Sunshine with VAAPI/AMF
  modules.sunshine.useCuda = false;

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
  # video=HDMI-A-1:1920x1080@60e forces the iGPU's first HDMI connector
  # to report `connected` even with no monitor, so amdgpu allocates a
  # real 1920x1080 scanout buffer. Without it, all connectors are
  # `disconnected`, X falls back to a tiny root window, and Sunshine
  # captures an empty framebuffer (Moonlight shows a black screen).
  # NOTE: the connector name must match the kernel's naming for this
  # specific GPU. Verify with `ls /sys/class/drm/` — on this Renoir/
  # Barcelo APU it's HDMI-A-1 / HDMI-A-2 (not HDMI-A-0 as on some
  # older AMD parts).
  #
  # drm.edid_firmware=<conn>:edid/<file> loads an EDID blob from
  # /lib/firmware/edid/<file>. Modern kernels (6.x) no longer embed
  # built-in EDIDs, so we ship one ourselves via hardware.firmware
  # below (pkgs.edid-generator provides standard-resolution .bin files
  # at $out/lib/firmware/edid/). Without the blob, amdgpu logs
  # `Requesting EDID firmware ... failed (err=-2)` and the `e` flag
  # alone gives a kernel framebuffer but no EDID, so Xorg falls back
  # to its 1024x768 default and XFCE renders into a tiny root window
  # that then gets stretched by the streaming pipeline.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
    "mitigations=off"
    "video=HDMI-A-1:1920x1080@60e"
    "drm.edid_firmware=HDMI-A-1:edid/1920x1080.bin"
  ];

  # Ship edid-generator's prebuilt EDID blobs to /lib/firmware/edid/.
  # Required by the drm.edid_firmware= kernel param above.
  hardware.firmware = [ pkgs.edid-generator ];

  # Pin CPU at max clock — eliminates frequency-scaling latency spikes
  # (typically 5-40 ms) during Sunshine encoder ramp-up, which manifest
  # as stream stutters. Costs ~5W idle power on the host.
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
