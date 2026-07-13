_:

{
  programs.git = {
    enable = true;
    settings.user = {
      name = "Reginleif88";
      email = "git@reginleif.io";
    };
    signing.format = null;
  };

  # Enabled on every host, graphical or not. ignis is headless but needs `gh`
  # more than the desktop does: it is the git credential helper for the private
  # Yggdrasil repo (modules/ignis.nix pullScript), and that helper reads the
  # token from ~/.config/gh/hosts.yml — which only exists once a human has run
  # `gh auth login` on the box. Gating this on `isGraphical` left the helper
  # wired up with no token behind it and no way to create one.
  programs.gh.enable = true;
}
