{
  pkgs,
  lib,
  inputs,
  ...
}:

# AI CLI tooling — imported on EVERY host, graphical or headless.
#
# This module must stay headless-safe: home/shell.nix defines a `claude()` zsh
# wrapper unconditionally, and that wrapper depends on both the claude-code
# binary and ~/.local/bin/claude-provider from here. Gating this module (it was
# previously desktop-only) left ignis with a wrapper pointing at two paths that
# did not exist. Desktop-only pieces live in ./ai-desktop.nix instead.

let
  system = pkgs.stdenv.hostPlatform.system;
  gtasksPluginVersion = "0.1.0";
in
{
  # Node.js (replaces NVM), Bun, Gemini CLI, Codex CLI, Claude Code
  home.packages = with pkgs; [
    nodejs
    bun
    gemini-cli
    codex
    jq # used by statusline.sh
    inputs.claude-code.packages.${system}.default
  ];

  # Repository-owned settings are intentionally immutable; local permission
  # state is initialized once and then belongs to Claude Code.
  home.file.".claude/settings.json".source = ../dotfiles/claude/settings.json;
  home.activation.install-claude-local-settings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.claude/settings.local.json"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      ${pkgs.coreutils}/bin/install -Dm600 \
        ${../dotfiles/claude/settings.local.json} \
        "$target"
    fi
  '';
  home.file.".claude/statusline.sh" = {
    source = ../dotfiles/claude/statusline.sh;
    executable = true;
  };

  # Codex CLI config. Install as a regular writable file because Codex
  # persists choices like /model, /statusline, and /theme back to config.toml.
  home.activation.install-codex-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.codex/config.toml"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      ${pkgs.coreutils}/bin/install -Dm600 \
        ${../dotfiles/codex/config.toml} \
        "$target"
    fi
  '';

  # Claude provider toggle (also used by Quickshell bar and zsh initExtra).
  # Headless-safe: with no /run/secrets/zlm_api_key (the secret is declared on
  # hyacinth only) `--env` just unsets the ZLM vars and Claude Code talks to
  # Anthropic directly.
  home.file.".local/bin/claude-provider" = {
    source = ../dotfiles/quickshell/bar/scripts/claude_provider.sh;
    executable = true;
  };

  # gtasks credentials from sops secrets — re-evaluated on every shell start
  # (sessionVariablesExtra uses hm-session-vars.sh which is guarded by
  # __HM_SESS_VARS_SOURCED, set at graphical-session time before /run/secrets/ exists).
  # On hosts without the secrets these expand to empty strings.
  programs.zsh.initContent = ''
    export GTASKS_CLIENT_ID="$(cat /run/secrets/gtasks_client_id 2>/dev/null)"
    export GTASKS_CLIENT_SECRET="$(cat /run/secrets/gtasks_client_secret 2>/dev/null)"
  '';

  # gtasks Claude plugin — copied as real files (Claude Desktop rejects symlinks)
  home.activation.install-gtasks-plugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    plugin_version="${gtasksPluginVersion}"
    plugin_dir="$HOME/.claude/plugins/cache/local/gtasks/$plugin_version"
    rm -rf "$plugin_dir"
    mkdir -p "$plugin_dir/.claude-plugin" "$plugin_dir/skills/gtasks"
    cp ${../dotfiles/claude/plugins/gtasks/.claude-plugin/plugin.json} "$plugin_dir/.claude-plugin/plugin.json"
    cp ${../dotfiles/claude/plugins/gtasks/skills/gtasks/SKILL.md} "$plugin_dir/skills/gtasks/SKILL.md"

    # Register gtasks@local in installed_plugins.json so Claude Code loads it
    plugins_file="$HOME/.claude/plugins/installed_plugins.json"
    install_path="$plugin_dir"
    mkdir -p "$(dirname "$plugins_file")"
    if [ ! -f "$plugins_file" ]; then
      printf '%s\n' '{"version":1,"plugins":{}}' > "$plugins_file"
    fi
    now="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
    ${pkgs.jq}/bin/jq --arg path "$install_path" \
      --arg version "$plugin_version" --arg now "$now" \
      '.plugins = (.plugins // {})
       | .plugins["gtasks@local"] = [{
           "scope":"user",
           "installPath":$path,
           "version":$version,
           "installedAt":(.plugins["gtasks@local"][0].installedAt // $now),
           "lastUpdated":$now
         }]' \
      "$plugins_file" > "$plugins_file.tmp"
    mv "$plugins_file.tmp" "$plugins_file"
  '';

  # direnv for per-project Node/tooling versions
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
