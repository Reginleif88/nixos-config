{ pkgs, inputs, hostname, lib, ... }:

let
  mkt = pkgs.vscode-marketplace;
in

{
  home.packages = with pkgs; [
    google-chrome
    drawio
    vlc
    qbittorrent
    mousepad
    obsidian
    arduino-ide
    jre
    android-tools
    scrcpy
    escrcpy
    winboat
    ascii-vault
    blueman
    proton-vpn
    protonmail-desktop
    aseprite
    chromium
    playwright-driver.browsers
    playwright-test
    python3Packages.pip
    sops
    kdePackages.okular
    ghidra
    gtasks
  ]
  ++ lib.optionals (hostname == "hyacinth") [
    (pkgs.symlinkJoin {
      name = "moonlight-qt";
      paths = [ pkgs.moonlight-qt ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/moonlight \
          --set GDK_BACKEND x11 \
          --set QT_QPA_PLATFORM xcb \
          --set SDL_VIDEODRIVER x11
      '';
    })
  ]
  ++ lib.optionals (hostname == "clematis") [
    pkgs.xfce.xfce4-screenshooter
    pkgs.copyq
    pkgs.xfce.xfce4-whiskermenu-plugin
  ];

  # Point Playwright at Nix-managed browsers instead of downloading its own
  home.sessionVariables.PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";

  # VS Code with PlatformIO extension
  programs.vscode = {
    enable = true;
    profiles.default.extensions = [
      #mkt.anthropic.claude-code  # installed via npm instead
      mkt.davidanson.vscode-markdownlint
      mkt.donjayamanne.githistory
      mkt.github.copilot-chat
      mkt.github.vscode-github-actions
      mkt.mechatroner.rainbow-csv
      mkt.ms-azuretools.vscode-containers
      mkt.ms-python.debugpy
      mkt.ms-python.python
      mkt.ms-python.vscode-pylance
      mkt.ms-python.vscode-python-envs
      mkt.ms-vscode-remote.remote-ssh
      mkt.ms-vscode-remote.remote-ssh-edit
      mkt.ms-vscode.cpptools
      mkt.ms-vscode.live-server
      mkt.ms-vscode.remote-explorer
      mkt.platformio.platformio-ide
      mkt.tomoki1207.pdf
      mkt.yzane.markdown-pdf
    ];
  };

  # XDG MIME associations (Mousepad replaces Kate)
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "zen.desktop";
      "x-scheme-handler/https" = "zen.desktop";
      "x-scheme-handler/about" = "zen.desktop";
      "x-scheme-handler/unknown" = "zen.desktop";
      "text/plain" = "org.xfce.mousepad.desktop";
      "text/x-shellscript" = "org.xfce.mousepad.desktop";
      "text/x-python" = "org.xfce.mousepad.desktop";
      "text/x-csrc" = "org.xfce.mousepad.desktop";
      "text/x-chdr" = "org.xfce.mousepad.desktop";
      "text/x-c++src" = "org.xfce.mousepad.desktop";
      "text/x-c++hdr" = "org.xfce.mousepad.desktop";
      "text/html" = "zen.desktop";
      "text/xml" = "org.xfce.mousepad.desktop";
      "text/css" = "org.xfce.mousepad.desktop";
      "text/javascript" = "org.xfce.mousepad.desktop";
      "text/x-makefile" = "org.xfce.mousepad.desktop";
      "text/x-patch" = "org.xfce.mousepad.desktop";
      "text/x-diff" = "org.xfce.mousepad.desktop";
      "text/markdown" = "org.xfce.mousepad.desktop";
      "text/x-yaml" = "org.xfce.mousepad.desktop";
      "text/x-toml" = "org.xfce.mousepad.desktop";
      "text/x-log" = "org.xfce.mousepad.desktop";
      "application/json" = "org.xfce.mousepad.desktop";
      "application/x-shellscript" = "org.xfce.mousepad.desktop";
      "application/xml" = "org.xfce.mousepad.desktop";
      "application/pdf" = "org.kde.okular.desktop";
    };
  };

  # Custom desktop entries
  xdg.desktopEntries = {
    obsidian = {
      name = "Obsidian";
      exec = "obsidian %U";
      icon = "obsidian";
      comment = "Knowledge base";
      categories = [ "Office" ];
      mimeType = [ "x-scheme-handler/obsidian" ];
    };

    arduino-ide = {
      name = "Arduino IDE";
      exec = "env ELECTRON_OZONE_PLATFORM_HINT=x11 arduino-ide %U";
      icon = "arduino-ide";
      comment = "Arduino IDE";
      categories = [ "Development" "IDE" ];
    };
  };

  # Symlink ascii-vault config dir to repo for backup
  home.activation.ascii-vault = lib.hm.dag.entryAfter ["writeBoundary"] ''
    dir="$HOME/.config/ascii-vault"
    repo="/home/reginleif88/Documents/nixos-config/dotfiles/ascii-vault"
    rm -rf "$dir"
    ln -sfn "$repo" "$dir"
  '';

  # XFCE config files. On clematis (an XFCE host), xfconfd reads each
  # channel XML at session start, then writes its in-memory state back to
  # disk as a *regular file* — silently destroying any home-manager symlink
  # to the read-only Nix store. Worse, it merges its old cached state on
  # top, producing structurally invalid XML over successive logins.
  #
  # Workaround: kill xfconfd, then copy (not symlink) the files. xfconfd
  # restarts on demand and reads our fresh content; future GUI tweaks are
  # transient and get overwritten on the next home-manager activation.
  #
  # On hyacinth/wisteria (Hyprland hosts) xfconfd never runs, so a normal
  # symlink is fine and avoids the rsync overhead.
  xdg.configFile = lib.optionalAttrs (hostname != "clematis") {
    "xfce4" = {
      source = ../dotfiles/xfce4;
      recursive = true;
      force = true;
    };
  };

  home.activation.xfce4-config = lib.mkIf (hostname == "clematis") (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.procps}/bin/pkill -u $USER -f xfconfd 2>/dev/null || true
      sleep 0.5
      ${pkgs.rsync}/bin/rsync -rL --chmod=u+w --exclude='*.hm-backup' \
        ${../dotfiles/xfce4}/ "$HOME/.config/xfce4/"
    ''
  );
}
