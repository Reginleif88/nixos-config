{ pkgs, inputs, ... }:

let
  system = "x86_64-linux";
  baseQs = inputs.quickshell.packages.${system}.default;

  # Patch quickshell for WebEngine support (upstream PR #351, not yet merged):
  # 1. Fix argv[0] passthrough — WebEngine/Chromium crashes without it
  # 2. Disable jemalloc — conflicts with Chromium's memory allocator
  patchedUnwrapped = baseQs.passthru.unwrapped.overrideAttrs (prev: {
    postPatch = (prev.postPatch or "") + ''
      substituteInPlace src/launch/launch.cpp \
        --replace-warn 'auto qArgC = 0;' 'auto qArgC = 1;'
    '';
    cmakeFlags = builtins.filter (f: builtins.match ".*USE_JEMALLOC.*" f == null) prev.cmakeFlags
      ++ [ "-DUSE_JEMALLOC:BOOL=OFF" ];
    buildInputs = builtins.filter (dep: dep.pname or "" != "jemalloc") prev.buildInputs;
  });

  # Rebuild wrapper around patched binary, adding qtwebengine for QML imports
  quickshellPkg = patchedUnwrapped.stdenv.mkDerivation {
    inherit (patchedUnwrapped) version meta;
    pname = "${patchedUnwrapped.pname}-wrapped";
    nativeBuildInputs = patchedUnwrapped.nativeBuildInputs ++ [ pkgs.qt6Packages.wrapQtAppsHook ];
    buildInputs = patchedUnwrapped.buildInputs ++ [ pkgs.qt6Packages.qtwebengine ];
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out
      cp -r ${patchedUnwrapped}/* $out
    '';
  };
in
{
  home.packages = [
    quickshellPkg
    pkgs.fuzzel
    pkgs.grimblast
    pkgs.libnotify
    pkgs.cliphist
    pkgs.wl-clipboard
    pkgs.swayimg
    pkgs.networkmanager
    pkgs.iw
    pkgs.bluez
    pkgs.pulseaudio
    pkgs.swaynotificationcenter
  ];

  # Place Quickshell config (recursive for entire bar directory)
  xdg.configFile."quickshell/bar" = {
    source = ../dotfiles/quickshell/bar;
    recursive = true;
  };

  xdg.configFile."fuzzel/fuzzel.ini".source = ../dotfiles/fuzzel/fuzzel.ini;

  # SwayNC notification center config + Gruvbox theme
  xdg.configFile."swaync/config.json".source = ../dotfiles/swaync/config.json;
  xdg.configFile."swaync/style.css".source = ../dotfiles/swaync/style.css;
}
