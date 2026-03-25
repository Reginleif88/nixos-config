{ pkgs, ... }:

{
  # Core CLI packages
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    vim
    python3
    xdg-user-dirs
    tmux
    unzip
    unrar
    ripgrep
    jq
    cpio
    cmake
    ffmpeg
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
    ntfs3g
  ];

  # NTFS support for mounting secondary drives
  boot.supportedFilesystems = [ "ntfs" ];

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    atkinson-hyperlegible
  ];

  # Set Atkinson Hyperlegible as default system font
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Atkinson Hyperlegible" ];
    serif = [ "Atkinson Hyperlegible" ];
    monospace = [ "FiraCode Nerd Font" ];
  };

  # PlatformIO udev rules for Arduino/ESP32 board access
  services.udev.packages = [ pkgs.platformio-core ];

  # Flatpak with declarative package management via nix-flatpak
  services.flatpak = {
    enable = true;

    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];

    packages = [
      "com.spotify.Client"
      "com.stremio.Stremio"
      "io.podman_desktop.PodmanDesktop"
    ];
  };
}
