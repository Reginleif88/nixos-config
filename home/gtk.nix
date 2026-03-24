{ pkgs, ... }:

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

  # Dark mode via dconf
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
