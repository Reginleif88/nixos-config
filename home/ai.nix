{ pkgs, lib, ... }:

{
  # Node.js (replaces NVM), Bun, Gemini CLI — claude-code installed via npm
  home.packages = with pkgs; [
    nodejs
    bun
    gemini-cli
    jq  # used by statusline.sh
  ];

  # Claude Code settings (dotfile symlinks)
  home.file.".claude/settings.json".source = ../dotfiles/claude/settings.json;
  home.file.".claude/settings.local.json".source = ../dotfiles/claude/settings.local.json;
  home.file.".claude/statusline.sh" = {
    source = ../dotfiles/claude/statusline.sh;
    executable = true;
  };

  # Claude Code ISC (Ideal State Criteria) tools and commands
  home.file.".claude/tools/isc/ISCManager.ts".source = ../dotfiles/claude/tools/isc/ISCManager.ts;
  home.file.".claude/tools/isc/ISCFormat.md".source = ../dotfiles/claude/tools/isc/ISCFormat.md;
  home.file.".claude/tools/isc/isc-validate.sh" = {
    source = ../dotfiles/claude/tools/isc/isc-validate.sh;
    executable = true;
  };
  home.file.".claude/commands/isc.md".source = ../dotfiles/claude/commands/isc.md;
  home.file.".claude/commands/isc-show.md".source = ../dotfiles/claude/commands/isc-show.md;
  home.file.".claude/commands/isc-clear.md".source = ../dotfiles/claude/commands/isc-clear.md;

  # Claude provider toggle (also used by Quickshell bar and zsh initExtra)
  home.file.".local/bin/claude-provider" = {
    source = ../dotfiles/quickshell/bar/scripts/claude_provider.sh;
    executable = true;
  };

  # npm global prefix (writable, for `npm install -g` on NixOS)
  home.file.".npmrc".text = "prefix=\${HOME}/.npm-global\n";

  # Auto-install/update claude-code on every rebuild
  home.activation.claude-code = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export npm_config_prefix="$HOME/.npm-global"
    export PATH="$npm_config_prefix/bin:$PATH"

    npm install -g @anthropic-ai/claude-code@latest 2>/dev/null || true
    claude install 2>/dev/null || true
  '';

  # direnv for per-project Node/tooling versions
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
