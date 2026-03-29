{ pkgs, inputs, ... }:

let
  system = "x86_64-linux";
in
{
  # Node.js (replaces NVM), Claude Code, Bun, Gemini CLI
  home.packages = with pkgs; [
    nodejs
    bun
    gemini-cli
    inputs.claude-code.packages.${system}.default
  ];

  # Claude Code global settings + permissions
  home.file.".claude/settings.json".source = ../dotfiles/claude/settings.json;
  home.file.".claude/settings.local.json".source = ../dotfiles/claude/settings.local.json;
  home.file.".claude/statusline.sh" = {
    source = ../dotfiles/claude/statusline.sh;
    executable = true;
  };

  # direnv for per-project Node/tooling versions
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
