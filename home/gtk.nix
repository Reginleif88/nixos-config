{ pkgs, lib, isGraphical, ... }:

{
  gtk = {
    enable = true;

    theme = {
      name = "Gruvbox-Material-Dark";
      package = pkgs.gruvbox-material-gtk-theme;
    };

    font = {
      name = "Atkinson Hyperlegible";
      size = 11;
    };

    iconTheme = {
      name = "hicolor";
    };

    gtk3.extraConfig = {
      gtk-cursor-theme-size = 24;
      gtk-xft-antialias = 1;
      gtk-xft-hinting = 1;
      gtk-xft-hintstyle = "hintslight";
      gtk-xft-rgba = "rgb";
    };

    gtk4.theme = null;
    gtk4.extraConfig = {
      gtk-cursor-theme-size = 24;
    };
  };

  # dconf is only usable on graphical hosts. The HM dconf module's activation
  # step shells out to `dconf load` over the ca.desrt.dconf D-Bus service, which
  # only exists where programs.dconf.enable is set system-side
  # (modules/hyprland.nix). On headless hosts that service is unactivatable, so
  # the whole step must be disabled — note the gtk + pointerCursor modules also
  # emit dconf keys, so gating only these settings below is not enough.
  dconf.enable = isGraphical;

  # Dark mode via dconf (applied only when dconf.enable above is true).
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
