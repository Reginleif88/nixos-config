{ config, pkgs, lib, ... }:

{
  programs.git = {
    enable = true;
    settings.user = {
      name = "Reginleif88";
      email = "git@reginleif.io";
    };
    signing.format = null;
  };

  programs.gh = {
    enable = true;
  };

}
