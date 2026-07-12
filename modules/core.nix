{ pkgs, ... }:

{
  # Core CLI packages
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    vim
    xdg-user-dirs
    tmux
    unzip
    unrar
    ripgrep
    jq
    cpio
  ];
}
