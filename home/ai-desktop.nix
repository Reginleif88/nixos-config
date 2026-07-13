{ config, inputs, lib, pkgs, ... }:

# Graphical-only AI tooling. The CLI half lives in ./ai.nix and is imported on
# every host; anything here needs a desktop session or a real browser, so it is
# gated behind `isGraphical` in ./default.nix.

let
  system = pkgs.stdenv.hostPlatform.system;
  playwrightDataDir = "${config.xdg.cacheHome}/playwright-mcp";
in
{
  # Claude Desktop (via claude-cowork-nix home-manager module)
  programs.claude-desktop = {
    enable = true;
    # Wire CLAUDE_CODE_LOCAL_BINARY into the Electron wrapper so the in-app
    # Code section's LOCAL sub-mode can spawn claude-code directly (bypasses
    # CCD's Linux-incompatible getHostPlatform download path).
    # Same flake input as ai.nix's home.packages — deduplicated in the store.
    claudeCodePackage = inputs.claude-code.packages.${system}.default;
  };

  # Playwright MCP plugin: keep browser state in the XDG cache, not /tmp.
  # Written as a real file (not symlink) via activation — Claude Desktop rejects symlinks.
  home.activation.install-playwright-mcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mcp_dir="$HOME/.claude/plugins/cache/claude-plugins-official/playwright/unknown"
    mkdir -p "$mcp_dir"
    rm -f "$mcp_dir/.mcp.json"
    cat > "$mcp_dir/.mcp.json" << 'MCPEOF'
    ${builtins.toJSON {
      playwright = {
        command = "npx";
        args = [
          "@playwright/mcp@latest"
          "--user-data-dir"
          "${playwrightDataDir}"
        ];
      };
    }}
    MCPEOF
  '';
}
