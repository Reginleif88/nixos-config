{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
    python3
    cmake
    ffmpeg
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-libav
    ntfs3g
    pandoc
    texliveFull
  ];

  boot.supportedFilesystems = [ "ntfs" ];

  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    atkinson-hyperlegible
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Atkinson Hyperlegible" ];
    serif = [ "Atkinson Hyperlegible" ];
    monospace = [ "FiraCode Nerd Font" ];
  };

  programs.nix-ld.enable = true;
  services.udev.packages = [ pkgs.platformio-core ];

  services.flatpak = {
    enable = true;
    update.onActivation = true;
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };

    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
      {
        name = "GeForceNOW";
        location = "https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo";
      }
    ];

    packages = [
      "com.spotify.Client"
      "me.proton.Mail"
      "com.stremio.Stremio"
      "io.podman_desktop.PodmanDesktop"
      {
        appId = "com.nvidia.geforcenow";
        origin = "GeForceNOW";
      }
    ];

    overrides."com.stremio.Stremio".Environment.WEBKIT_DISABLE_DMABUF_RENDERER = "1";
  };
}
