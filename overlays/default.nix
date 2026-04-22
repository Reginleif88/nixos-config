# Custom package overlays
{ ascii-vault-src, ... }:
final: prev:
{
  gtasks = prev.buildGoModule {
    pname = "gtasks";
    version = "0.13.0";
    src = prev.fetchFromGitHub {
      owner = "BRO3886";
      repo = "gtasks";
      rev = "v0.13.0";
      hash = "sha256-MoBlKuv8Use1VRQkJizsLfsZ4F2eFsWmWElY6KwmDH0=";
    };
    # Run `nix build .#nixosConfigurations.<host>.config.home-manager.users.reginleif88.home.packages`
    # and replace with the hash from the error output.
    vendorHash = "sha256-bgg1ZAJya0NfWLLYB10egUhQXIP+A2oaQfh+CdQOOow=";
    meta = with prev.lib; {
      description = "CLI client for Google Tasks";
      homepage = "https://github.com/BRO3886/gtasks";
      license = licenses.mit;
      mainProgram = "gtasks";
    };
  };

  ascii-vault = prev.rustPlatform.buildRustPackage {
    pname = "ascii-vault";
    version = "1.0.0";
    src = ascii-vault-src;
    cargoHash = "sha256-+j+Si7Uafg6dv/emPtEhQxJoKz0ti9ibaRgugFM35HA=";
  };

  escrcpy = prev.appimageTools.wrapType2 {
    pname = "escrcpy";
    version = "2.6.2";
    src = prev.fetchurl {
      url = "https://github.com/viarotel-org/escrcpy/releases/download/v2.6.2/Escrcpy-2.6.2-linux-x86_64.AppImage";
      sha256 = "0mg37z9yhc5yvpf28zsr5d0m4xdm9x057s58fnvww4x7p4wclczv";
    };
    extraInstallCommands = let
      appimageContents = prev.appimageTools.extractType2 {
        pname = "escrcpy";
        version = "2.6.2";
        src = prev.fetchurl {
          url = "https://github.com/viarotel-org/escrcpy/releases/download/v2.6.2/Escrcpy-2.6.2-linux-x86_64.AppImage";
          sha256 = "0mg37z9yhc5yvpf28zsr5d0m4xdm9x057s58fnvww4x7p4wclczv";
        };
      };
    in ''
      install -m 444 -D ${appimageContents}/escrcpy.desktop $out/share/applications/escrcpy.desktop
      substituteInPlace $out/share/applications/escrcpy.desktop \
        --replace-warn 'Exec=AppRun' 'Exec=escrcpy'
      cp -r ${appimageContents}/usr/share/icons $out/share/icons
    '';
  };

  # ── KasmVNC ────────────────────────────────────────────────────────
  # Modern VNC server with built-in WebSocket web client (WebP/H.264
  # encoding). Upstream only provides a Docker-based build, so we
  # repackage their prebuilt .deb — same approach as nixpkgs draft
  # PR #363943. The `noble` build (Ubuntu 24.04) is what we need:
  # jammy ships libssl3 1.1 which would force a legacy openssl dep.
  kasmvnc = prev.stdenv.mkDerivation rec {
    pname = "kasmvnc";
    version = "1.4.0";

    src = prev.fetchurl {
      url = "https://github.com/kasmtech/KasmVNC/releases/download/v${version}/kasmvncserver_noble_${version}_amd64.deb";
      sha256 = "sha256-ErrGAUFJxf3udfDUA3haqj5d1OoiLecyU6XUGBvJVn4=";
    };

    nativeBuildInputs = with prev; [
      autoPatchelfHook
      dpkg
      makeWrapper
    ];

    # Runtime libraries the Xkasmvnc/kasmvncpasswd/etc. ELF binaries
    # link against. autoPatchelfHook rewrites RPATHs to find them.
    buildInputs = with prev; [
      (perl.withPackages (pp: with pp; [
        Switch
        YAMLTiny
        HashMergeSimple
        ListMoreUtils
        TryTiny
        DateTime
        DateTimeTimeZone
      ]))
      freetype
      libgcrypt
      libpng
      libunwind
      libwebp
      libxcrypt-legacy # provides libcrypt.so.1 (libxcrypt ships .so.2)
      mesa             # libgbm
      libGL
      openssl
      pixman
      stdenv.cc.cc.lib # libstdc++
      systemdLibs
      xorg.libX11
      xorg.libXau
      xorg.libXcursor
      xorg.libXdmcp
      xorg.libXext
      xorg.libXfixes
      xorg.libXfont2
      xorg.libXrandr
      xorg.libXtst
      xorg.libxshmfence
    ];

    # dpkg-deb's default unpackPhase leaves us with usr/{bin,lib,share}
    unpackPhase = ''
      runHook preUnpack
      mkdir -p unpacked
      dpkg-deb -x $src unpacked
      runHook postUnpack
    '';

    # Move files into Nix layout. The perl wrapper ships as
    # `kasmvncserver`; Debian's postinst normally symlinks it to
    # `vncserver` via update-alternatives, so we replicate that here.
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/lib $out/share
      cp -r unpacked/usr/bin/*   $out/bin/
      cp -r unpacked/usr/lib/*   $out/lib/
      cp -r unpacked/usr/share/* $out/share/

      # update-alternatives equivalents — the perl wrapper invokes
      # "Xvnc" and "kasmvncpasswd" from its own dir, and downstream
      # tools expect a "vncserver" entry point.
      ln -s $out/bin/Xkasmvnc      $out/bin/Xvnc
      ln -s $out/bin/kasmvncserver $out/bin/vncserver
      ln -s $out/bin/kasmvncpasswd $out/bin/vncpasswd
      ln -s $out/bin/kasmxproxy    $out/bin/xproxy

      runHook postInstall
    '';

    # Upstream hardcodes several /usr paths. Rewrite them to the Nix
    # store: the perl wrapper's defaults-config path + both branches
    # of its select-de.sh lookup (IsThisSystemBinary returns false
    # when $0 is under /nix/store, so the LocalSelectDePath branch
    # is the one actually taken), and the defaults YAML's www dir.
    postFixup = ''
      substituteInPlace $out/bin/kasmvncserver \
        --replace-fail '/usr/share/kasmvnc/kasmvnc_defaults.yaml' \
                       "$out/share/kasmvnc/kasmvnc_defaults.yaml" \
        --replace-fail '"/usr/lib/kasmvncserver/select-de.sh"' \
                       "\"$out/lib/kasmvncserver/select-de.sh\"" \
        --replace-fail '"$dirname/../builder/startup/deb/select-de.sh"' \
                       "\"$out/lib/kasmvncserver/select-de.sh\""

      substituteInPlace $out/share/kasmvnc/kasmvnc_defaults.yaml \
        --replace-fail '/usr/share/kasmvnc/www' "$out/share/kasmvnc/www"

      patchShebangs $out/bin/kasmvncserver $out/lib/kasmvncserver/select-de.sh

      # PERL5LIB: script uses `use KasmVNC::...` — modules live in
      # $out/share/perl5. Runtime PATH: xauth/hostname/xkbcomp are
      # required dependencies the perl wrapper searches for at startup.
      wrapProgram $out/bin/kasmvncserver \
        --prefix PERL5LIB : $out/share/perl5 \
        --prefix PATH : ${prev.lib.makeBinPath (with prev; [
          coreutils
          gawk
          gnused
          gnugrep
          procps
          nettools       # hostname
          xorg.xauth
          xorg.xkbcomp
          xkeyboard_config
          which
        ])}
    '';

    meta = with prev.lib; {
      description = "Modern web-based VNC server with WebP encoding and built-in HTTPS/WebSocket client";
      homepage = "https://github.com/kasmtech/KasmVNC";
      license = licenses.gpl2Only;
      platforms = [ "x86_64-linux" ];
      mainProgram = "vncserver";
      sourceProvenance = [ sourceTypes.binaryNativeCode ];
    };
  };
}
