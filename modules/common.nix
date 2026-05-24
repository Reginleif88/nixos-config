{ config, pkgs, inputs, ... }:

{
  imports = [ inputs.sops-nix.nixosModules.sops ];

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

  time.timeZone = "Europe/Paris";

  nixpkgs.config.allowUnfree = true;

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

  # Keep the desktop responsive while large packages compile from source.
  # A cache-miss rebuild spawns dozens of cc1plus jobs that otherwise compete
  # 1:1 with the compositor and media players for CPU/IO, starving them of the
  # scheduler slots they need to hit each vblank (perceived as video judder).
  # SCHED_IDLE + idle IO class makes build jobs yield to all interactive work;
  # builds run a bit slower when the machine is busy, full speed when it's idle.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  users.users.reginleif88 = {
    isNormalUser = true;
    description = "reginleif88";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age.keyFile = "${config.users.users.reginleif88.home}/.config/sops/age/keys.txt";
    secrets = {
      "github_token"         = { owner = "reginleif88"; };
      "github_repos"         = { owner = "reginleif88"; };
      "zlm_api_key"          = { owner = "reginleif88"; };
      "gtasks_client_id"     = { owner = "reginleif88"; };
      "gtasks_client_secret" = { owner = "reginleif88"; };
      "keyring_password"     = { owner = "reginleif88"; };
    };
  };
}
