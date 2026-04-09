{ pkgs, lib, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  # Node.js (replaces NVM), Bun, Gemini CLI, Claude Code
  home.packages = with pkgs; [
    nodejs
    bun
    gemini-cli
    jq  # used by statusline.sh
    inputs.claude-code.packages.${system}.default
    inputs.claude-desktop.packages.${system}.claude-desktop-fhs
  ];

  # Claude Code settings (dotfile symlinks)
  home.file.".claude/settings.json".source = ../dotfiles/claude/settings.json;
  home.file.".claude/settings.local.json".source = ../dotfiles/claude/settings.local.json;
  home.file.".claude/statusline.sh" = {
    source = ../dotfiles/claude/statusline.sh;
    executable = true;
  };

  # Playwright MCP plugin: redirect user-data-dir to a writable path
  # (the default uses PLAYWRIGHT_BROWSERS_PATH which is in the read-only Nix store)
  home.file.".claude/plugins/cache/claude-plugins-official/playwright/unknown/.mcp.json".text = builtins.toJSON {
    playwright = {
      command = "npx";
      args = [ "@playwright/mcp@latest" "--user-data-dir" "/tmp/playwright-mcp" ];
    };
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

  # direnv for per-project Node/tooling versions
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
