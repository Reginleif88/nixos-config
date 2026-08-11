# Custom package overlays
{ inputs, ... }:
final: prev:

let
  hyprlandPackage = inputs.hyprland.packages.${final.stdenv.hostPlatform.system}.hyprland;
in
{
  # Upstream Hyprland workaround against HEAD commit ee58a513 (2026-05-09).
  # `--replace-fail` makes the build error if upstream changes the matched string,
  # so the patch announces itself when it can be dropped.
  # Patches a device-tags null deref when a keyboard has no explicit device block.
  hyprland-patched = hyprlandPackage.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/managers/input/InputManager.cpp \
        --replace-fail 'CVarList2(Config::mgr()->getDeviceString(devname, "tags"))' 'CVarList2(std::string(""))'
    '';
  });

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

  # escrcpy: GUI front-end for scrcpy (Android screen mirroring), distributed
  # only as an AppImage. Single source of truth — to update, bump `version` and
  # refresh `hash` (nix store prefetch-file <url>); the download URL and both
  # appimageTools passes derive from them. The asset name has tracked
  # `Escrcpy-<version>-linux-x86_64.AppImage` across releases — verify it still
  # holds at https://github.com/viarotel-org/escrcpy/releases when bumping.
  escrcpy =
    let
      version = "2.11.1";
      src = prev.fetchurl {
        url = "https://github.com/viarotel-org/escrcpy/releases/download/v${version}/Escrcpy-${version}-linux-x86_64.AppImage";
        hash = "sha256-JN+Int2G0ZnGY7XTl56pqTTdx9AX9369Ijbc+t504Pc=";
      };
      appimageContents = prev.appimageTools.extractType2 {
        pname = "escrcpy";
        inherit version src;
      };
    in
    prev.appimageTools.wrapType2 {
      pname = "escrcpy";
      inherit version src;
      extraInstallCommands = ''
        install -m 444 -D ${appimageContents}/escrcpy.desktop $out/share/applications/escrcpy.desktop
        substituteInPlace $out/share/applications/escrcpy.desktop \
          --replace-warn 'Exec=AppRun' 'Exec=escrcpy'
        cp -r ${appimageContents}/usr/share/icons $out/share/icons
      '';
    };

  # openwhispr: privacy-first voice-to-text dictation (whisper.cpp + sherpa-onnx
  # bundled in-app, so no runtime Python/pip needed), distributed only as an
  # AppImage. Same single-source-of-truth shape as escrcpy above — bump `version`
  # and refresh `hash` (nix store prefetch-file <url>) to update; the URL and both
  # appimageTools passes derive from them. The asset name has followed
  # `OpenWhispr-<version>-linux-x86_64.AppImage`; verify it still holds at
  # https://github.com/OpenWhispr/openwhispr/releases when bumping.
  openwhispr =
    let
      version = "1.7.5";
      src = prev.fetchurl {
        url = "https://github.com/OpenWhispr/openwhispr/releases/download/v${version}/OpenWhispr-${version}-linux-x86_64.AppImage";
        hash = "sha256-InmwYfIw+CfvCYx2DwZDIS9l/yj+MK5m7AUoT0TvbO4=";
      };
      appimageContents = prev.appimageTools.extractType2 {
        pname = "openwhispr";
        inherit version src;
      };
    in
    prev.appimageTools.wrapType2 {
      pname = "openwhispr";
      inherit version src;
      extraInstallCommands = ''
        install -m 444 -D ${appimageContents}/open-whispr.desktop $out/share/applications/open-whispr.desktop
        substituteInPlace $out/share/applications/open-whispr.desktop \
          --replace-warn 'Exec=AppRun' 'Exec=openwhispr'
        cp -r ${appimageContents}/usr/share/icons $out/share/icons
      '';
    };

  # sklauncher: third-party Minecraft launcher from https://skmedix.pl/downloads,
  # not in nixpkgs. Same single-source-of-truth shape as escrcpy/openwhispr above —
  # bump `version` and refresh `hash` to update.
  #
  # Getting the URL on a bump: the download page is a Nuxt SPA, so the link is not
  # in the served HTML. It is assembled from `l.siteUrl` inside a /_nuxt/*.js chunk,
  # which conveniently carries the expected SHA-256 of every artifact inline next to
  # it (`universal_hash` is the one for this jar). Grep the chunks for
  # `/binaries/skl/`, then cross-check with `nix store prefetch-file <url>`.
  #
  # This pins only a BOOTSTRAP: the jar's manifest is
  # `Main-Class: pl.skmedix.bootstrap.Main` and it downloads the real launcher at
  # runtime. So the running launcher drifts ahead of `version` by design, and there
  # is no version-lag treadmill here (contrast Proton Mail, where the shipped
  # version *was* the product and nixpkgs lag broke the server-side minimum).
  #
  # LD_LIBRARY_PATH is the entire reason modded Minecraft works under this wrapper.
  # Mojang ships prebuilt LWJGL natives (libglfw.so, libopenal.so) that are
  # perfectly good binaries but cannot resolve their own libX11.so.6 / libGL.so.1,
  # because NixOS has no /usr/lib. The game runs as a CHILD of the launcher and
  # inherits this variable, so the deps resolve and the vendored natives load — no
  # FHS sandbox and no -Dorg.lwjgl.*.libname overrides needed. The library list is
  # copied deliberately from nixpkgs' own prismlauncher wrapper
  # (pkgs/by-name/pr/prismlauncher/package.nix), which is already validated against
  # real Minecraft native loading; keep it in sync rather than hand-rolling.
  #
  # `addDriverRunpath.driverLink` must stay FIRST: it is how libGL finds the NVIDIA
  # driver on this host. Without it the game falls back to software GL or dies.
  #
  # Both the launcher UI (Swing/FlatLaf) and the game render via XWayland — JDK 21
  # ships no Wayland toolkit and the vendored GLFW is X11-only. Expected, not a bug.
  sklauncher =
    let
      version = "3.2.18";
      runtimeLibs = with prev; [
        (lib.getLib stdenv.cc.cc)
        # native versions of what LWJGL would otherwise vendor
        glfw3-minecraft
        openal
        # openal backends
        alsa-lib
        libjack2
        libpulseaudio
        pipewire
        # glfw
        libGL
        libx11
        libxcursor
        libxext
        libxrandr
        libxxf86vm
        wayland
        udev # oshi
        vulkan-loader # VulkanMod's lwjgl

        # Beyond nixpkgs' prismlauncher list, on purpose. LWJGL ships a portable
        # libglfw.so with almost no DT_NEEDED entries — it dlopen()s nearly
        # everything by soname at runtime, so `ldd` reports it as fully resolved
        # while it is not. Dumping its dlopen sonames and checking each against the
        # search path shows these four unaccounted for, all needed by the X11
        # backend (libXi is XInput2, i.e. mouse look).
        #
        # Prism survives without them only by accident: the JVM's AWT pulls libXi
        # and libXrender in as DT_NEEDED of libawt_xawt.so via the JDK's own RPATH,
        # so a later dlopen finds an already-loaded soname and never hits the
        # filesystem. That is load-order luck, not a contract. Four extra store
        # paths in LD_LIBRARY_PATH cost nothing, so pin them.
        libxi
        libxinerama
        libxkbcommon
        libxrender

        # Knowingly NOT added, after the same dlopen audit on libopenal.so:
        # libportaudio.so.2 (a redundant alternative backend — ALSA, Pulse, JACK
        # and PipeWire above all resolve) and libdbus-1.so.3 (gates only OpenAL's
        # RTKit realtime-priority hint). Audio works without either; they were
        # considered, not missed.
      ];
    in
    prev.stdenvNoCC.mkDerivation {
      pname = "sklauncher";
      inherit version;

      src = prev.fetchurl {
        url = "https://skmedix.pl/binaries/skl/${version}/SKlauncher-${version}.jar";
        hash = "sha256-Jac+N3Ch2NFLzlPokg4uiTqsw8cV0Psi+HjvIJDQOGM=";
      };

      dontUnpack = true;
      nativeBuildInputs = [ prev.makeWrapper ];

      installPhase = ''
        runHook preInstall
        install -Dm444 $src $out/share/sklauncher/SKlauncher.jar
        makeWrapper ${prev.jdk21}/bin/java $out/bin/sklauncher \
          --add-flags "-jar $out/share/sklauncher/SKlauncher.jar" \
          --set LD_LIBRARY_PATH "${prev.addDriverRunpath.driverLink}/lib:${prev.lib.makeLibraryPath runtimeLibs}"
        runHook postInstall
      '';

      meta = with prev.lib; {
        description = "SKlauncher — third-party Minecraft launcher (self-updating bootstrap)";
        homepage = "https://skmedix.pl/downloads";
        license = licenses.unfree;
        platforms = [ "x86_64-linux" ];
        mainProgram = "sklauncher";
      };
    };

  # neoforge-install: installs the NeoForge 1.21.1 client profile into
  # ~/.minecraft so `sklauncher` can see it. Run it once by hand after a rebuild;
  # re-running is safe.
  #
  # Deliberately NOT a home-manager activation script. That would push a ~121 MB
  # network install into every nixos-rebuild, break offline rebuilds, and write
  # into a tree the game mutates constantly. ~/.minecraft is inherently mutable
  # state — Nix owns the version pin, the JDK and the procedure, not the tree.
  #
  # The launcher_profiles.json stub is REQUIRED, not defensive tidying: run against
  # a directory without one, the installer aborts with "There is no minecraft
  # launcher profile in <dir>, you need to run the launcher first!". A 27-byte stub
  # satisfies it, after which the install injects its own profile. Only written when
  # absent, so a real launcher's file is never clobbered.
  #
  # To bump: change `neoforgeVersion` and refresh the hash. Pick a version from
  # https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml
  # — the 21.1.x line is the one that targets Minecraft 1.21.1. NeoForge 1.21.1
  # requires Java 21, hence jdk21 rather than the default jdk.
  neoforge-install =
    let
      neoforgeVersion = "21.1.248";
      installer = prev.fetchurl {
        url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/${neoforgeVersion}/neoforge-${neoforgeVersion}-installer.jar";
        hash = "sha256-aO6rdwWbpT3xgS8a+lv1MKslZqPNzV+SSqbnG+QuQQw=";
      };
    in
    prev.writeShellScriptBin "neoforge-install" ''
      set -euo pipefail

      mc="''${MINECRAFT_DIR:-$HOME/.minecraft}"
      mkdir -p "$mc"

      if [ ! -e "$mc/launcher_profiles.json" ]; then
        printf '%s' '{"profiles":{},"version":3}' > "$mc/launcher_profiles.json"
        echo "neoforge-install: wrote stub $mc/launcher_profiles.json"
      fi

      # cd first: the installer writes its <jar>.log next to the CWD, and the jar
      # itself lives in the read-only store.
      cd "$mc"
      echo "neoforge-install: installing NeoForge ${neoforgeVersion} into $mc"
      ${prev.jdk21}/bin/java -jar ${installer} --install-client "$mc"
      echo "neoforge-install: done — pick 'neoforge-${neoforgeVersion}' in your launcher"
    '';

  # gruvbox-material-gtk-theme: removed from nixpkgs on 2026-07-22 as collateral
  # damage from the gtk-engine-murrine removal (murrine is a GTK *2* engine that
  # was unmaintained upstream). Only the theme's `gtk-2.0/main.rc` ever
  # referenced murrine — the GTK3 and GTK4 halves are plain CSS — so the theme
  # is re-vendored here with the GTK2 variant pruned. GTK2 apps fall back to
  # Raleigh, which costs nothing on a host that installs no GTK2 apps.
  # To update: bump `rev`, then refresh `hash`
  # (nix-prefetch-git https://github.com/TheGreatMcPain/gruvbox-material-gtk).
  gruvbox-material-gtk-theme = prev.stdenvNoCC.mkDerivation {
    pname = "gruvbox-material-gtk-theme";
    version = "0-unstable-2025-01-16";

    src = prev.fetchFromGitHub {
      owner = "TheGreatMcPain";
      repo = "gruvbox-material-gtk";
      rev = "bb306ae972273cbfcbf78f8b772662e8b0678d82";
      hash = "sha256-F3jVvibeov/3ZlIu+m0SmNsX6l1UwunTFKy+CnAOwok=";
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/themes
      cp -r themes/* $out/share/themes/
      # Same self-announcing spirit as `--replace-fail` above: the unquoted glob
      # is left literal when it matches nothing, so `rm` fails the build the day
      # upstream stops shipping gtk-2.0 and this pruning can be deleted.
      rm -r $out/share/themes/*/gtk-2.0
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Gruvbox Material GTK theme (GTK3/GTK4 only, murrine-free)";
      homepage = "https://github.com/TheGreatMcPain/gruvbox-material-gtk";
      license = licenses.gpl3Only;
      platforms = platforms.all;
    };
  };
}
