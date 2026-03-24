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

  # direnv for per-project Node/tooling versions
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
