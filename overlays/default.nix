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

  # ── neatvnc: FFmpeg 8 compatibility ────────────────────────────────
  # Patches the H.264 encoder's libavfilter buffer-source init to use
  # a non-HW placeholder pix_fmt. Without this, neatvnc 0.9.6 against
  # ffmpeg 8 logs "BufferSourceContext.pix_fmt to a HW format requires
  # hw_frames_ctx" and falls back to Tight. Drop this override once
  # neatvnc tags a release that handles FFmpeg 8 cleanly.
  neatvnc = prev.neatvnc.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./patches/neatvnc-ffmpeg8-placeholder-pixfmt.patch
    ];
  });

  # wayvnc is the only consumer of neatvnc here; rebuild it against
  # the patched library so the linked /nix/store path actually changes.
  wayvnc = prev.wayvnc.override { neatvnc = final.neatvnc; };

  # ── jedi-language-server: tolerate jedi 0.20 ───────────────────────
  # nixpkgs (pinned 15f4ee45) ships jedi 0.20.0, but jedi-language-server
  # 0.46.0 — the latest upstream — still pins `jedi>=0.19.2,<0.20`, so
  # pythonRuntimeDepsCheckHook rejects the build. The cap is upstream
  # caution, not a real break: the relaxed derivation builds, passes its
  # own test suite, and substitutes straight from cache.nixos.org (nixpkgs
  # HEAD already relaxed it the same way). Pulled in transitively by the
  # ms-python VSCode extension (nix-vscode-extensions). Drop this once
  # nixpkgs advances past the fix or jedi-language-server widens its pin.
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (pyfinal: pyprev: {
      jedi-language-server = pyprev.jedi-language-server.overridePythonAttrs (o: {
        pythonRelaxDeps = (o.pythonRelaxDeps or [ ]) ++ [ "jedi" ];
      });
    })
  ];

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
  escrcpy = let
    version = "2.11.1";
    src = prev.fetchurl {
      url = "https://github.com/viarotel-org/escrcpy/releases/download/v${version}/Escrcpy-${version}-linux-x86_64.AppImage";
      hash = "sha256-JN+Int2G0ZnGY7XTl56pqTTdx9AX9369Ijbc+t504Pc=";
    };
    appimageContents = prev.appimageTools.extractType2 {
      pname = "escrcpy";
      inherit version src;
    };
  in prev.appimageTools.wrapType2 {
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
  openwhispr = let
    version = "1.7.3";
    src = prev.fetchurl {
      url = "https://github.com/OpenWhispr/openwhispr/releases/download/v${version}/OpenWhispr-${version}-linux-x86_64.AppImage";
      hash = "sha256-590A9noHhuHtBt0lEGBoohS8SJItOtD9xUMsDLAwa4E=";
    };
    appimageContents = prev.appimageTools.extractType2 {
      pname = "openwhispr";
      inherit version src;
    };
  in prev.appimageTools.wrapType2 {
    pname = "openwhispr";
    inherit version src;
    extraInstallCommands = ''
      install -m 444 -D ${appimageContents}/open-whispr.desktop $out/share/applications/open-whispr.desktop
      substituteInPlace $out/share/applications/open-whispr.desktop \
        --replace-warn 'Exec=AppRun' 'Exec=openwhispr'
      cp -r ${appimageContents}/usr/share/icons $out/share/icons
    '';
  };
}
