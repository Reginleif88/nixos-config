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
    blueman
    # protonmail-desktop — moved to Flatpak (me.proton.Mail) to escape nixpkgs
    # packaging lag; Flathub tracks Proton's forced-minimum bumps via weekly
    # services.flatpak.update.auto. See modules/core.nix flatpak packages.
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

    # Boosteroid cloud gaming. There is no native NixOS package; the official
    # "client" is just Chromium-over-WebRTC anyway, so we run the web player as
    # a dedicated fullscreen PWA via google-chrome (which ships proprietary
    # H.264 — required, since Boosteroid streams H.264).
    #
    # NOTE: video decode here is SOFTWARE, and that is not fixable. Chromium
    # hardcodes "Should skip nVidia device named: nvidia-drm" in vaapi_wrapper.cc
    # and refuses to enumerate NVIDIA DRM devices for VA-API, upstream of any
    # flag — so --ignore-gpu-blocklist / VaapiIgnoreDriverChecks do nothing on
    # this Pascal box (verified 2026-06-19: nvidia-smi `dec` stayed 0 while Chrome
    # played 1080p H.264). Software H.264 decode is light at 1080p, so this is
    # fine. The browser that CAN HW-decode on NVIDIA is Firefox (no nvidia-drm
    # skip) + nvidia-vaapi-driver, if it ever becomes worth switching for.
    #
    # Flags, by purpose:
    #   --app / --start-fullscreen  chromeless fullscreen window → direct scanout
    #   --class=boosteroid          deterministic app_id for the Hyprland rule
    #   --ozone-platform=wayland    native Wayland (GPU compositing confirmed OK);
    #                               swap to x11 if the compositor ever misbehaves
    (pkgs.writeShellScriptBin "boosteroid" ''
      exec ${pkgs.google-chrome}/bin/google-chrome-stable \
        --app=https://cloud.boosteroid.com/ \
        --class=boosteroid \
        --ozone-platform=wayland \
        --start-fullscreen \
        "$@"
    '')
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
  } // lib.optionalAttrs (hostname == "hyacinth") {
    boosteroid = {
      name = "Boosteroid";
      exec = "boosteroid";
      icon = "applications-games";
      comment = "Boosteroid cloud gaming (fullscreen PWA, HW decode)";
      categories = [ "Game" ];
      # Must equal the launcher's --class so the .desktop maps to the window.
      settings.StartupWMClass = "boosteroid";
    };
  };

  # thunar-volman removable-media handling (the plugin is enabled system-side in
  # modules/services.nix). These xfconf toggles are the equivalent of Thunar >
  # Preferences > Advanced > "Configure" > Volume Management. On insert of a USB,
  # thunar-volman asks udisks2 to mount it; for a BitLocker/LUKS volume that
  # unlock request surfaces the gvfs password dialog first, then autobrowse opens
  # a Thunar window on the freshly-mounted filesystem. Unlike dconf (see gtk.nix),
  # xfconf's D-Bus service ships in the xfce.xfconf package itself, so this needs
  # no system-side service — only that this module is on a graphical host, which
  # apps.nix already is (imported under isGraphical in home/default.nix).
  xfconf.settings."thunar-volman" = {
    "automount-media/enabled" = true;  # mount removable media when inserted
    "automount-drives/enabled" = true; # mount removable drives when hot-plugged
    "autobrowse/enabled" = true;       # open a Thunar window after mounting
  };

}
