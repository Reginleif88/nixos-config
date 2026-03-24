{ pkgs, ... }:

{
  # PipeWire audio stack
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Thunar file manager with plugins
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-volman
      thunar-archive-plugin
      thunar-media-tags-plugin
    ];
  };

  # Thumbnail generation
  services.tumbler.enable = true;
  environment.systemPackages = with pkgs; [
    ffmpegthumbnailer
    xarchiver
    nwg-displays
    pwvucontrol
    qpwgraph
    pavucontrol
  ];

  # Virtual filesystem and disk management
  services.gvfs.enable = true;
  services.udisks2.enable = true;
}
