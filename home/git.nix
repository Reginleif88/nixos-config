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

  # Clone private GitHub repos on activation
  home.activation.cloneRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    TOKEN_FILE="/run/secrets/github_token"
    REPOS_FILE="/run/secrets/github_repos"
    REPOS_DIR="${config.home.homeDirectory}/Documents"

    if [ -f "$TOKEN_FILE" ] && [ -f "$REPOS_FILE" ]; then
      # Authenticate gh CLI
      $DRY_RUN_CMD ${pkgs.gh}/bin/gh auth login --with-token < "$TOKEN_FILE" 2>/dev/null || true

      # Clone repos if not already present
      mkdir -p "$REPOS_DIR"
      for repo in $(cat "$REPOS_FILE"); do
        if [ ! -d "$REPOS_DIR/$repo" ]; then
          $DRY_RUN_CMD ${pkgs.gh}/bin/gh repo clone "Reginleif88/$repo" "$REPOS_DIR/$repo" 2>/dev/null || true
        fi
      done
    fi
  '';
}
