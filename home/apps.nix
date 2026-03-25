{ pkgs, inputs, ... }:

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
  ];

  # VS Code with PlatformIO extension
  programs.vscode = {
    enable = true;
    profiles.default.extensions = [
      mkt.anthropic.claude-code
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
      "text/plain" = "org.xfce.mousepad.desktop";
      "text/x-shellscript" = "org.xfce.mousepad.desktop";
      "text/x-python" = "org.xfce.mousepad.desktop";
      "text/x-csrc" = "org.xfce.mousepad.desktop";
      "text/x-chdr" = "org.xfce.mousepad.desktop";
      "text/x-c++src" = "org.xfce.mousepad.desktop";
      "text/x-c++hdr" = "org.xfce.mousepad.desktop";
      "text/html" = "org.xfce.mousepad.desktop";
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

  # Thunar XML config
  xdg.configFile."xfce4" = {
    source = ../dotfiles/xfce4;
    recursive = true;
  };
}
