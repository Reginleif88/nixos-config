# Custom package overlays
{ ascii-vault-src, fenix, system, ... }:
final: prev:
let
  # ── Nightly Rust toolchain (for moonlight-web-stream) ──────────────
  fenixPkgs = fenix.packages.${system};
  nightlyManifest = fenixPkgs.toolchainOf {
    channel = "nightly";
    date = "2026-02-13";
    sha256 = "sha256-S4LusOItdSmt4Z+R5llNu9B3h1Lt+BXQuY9BUnl2xFg=";
  };
  nightlyToolchain = fenixPkgs.combine [
    nightlyManifest.cargo
    nightlyManifest.rustc
  ];
  nightlyRustPlatform = prev.makeRustPlatform {
    cargo = nightlyToolchain;
    rustc = nightlyToolchain;
  };

  # ── moonlight-web-stream sources ──────────────────────────────────
  moonlight-web-stream-src = prev.fetchFromGitHub {
    owner = "MrCreativ3001";
    repo = "moonlight-web-stream";
    rev = "v2.7";
    hash = "sha256-Fnl++Ij6eBqlnZMxxgsk6Q8SZSnik4ej2qBnsQ7jP34=";
    fetchSubmodules = true;
  };

  # C GameStream protocol library (submodule of moonlight-common-rust,
  # not fetched by Nix's cargo vendoring — injected in postConfigure)
  moonlight-common-c-src = prev.fetchFromGitHub {
    owner = "moonlight-stream";
    repo = "moonlight-common-c";
    rev = "62687809b1f7410c3db4be2527503a54ae408d70";
    hash = "sha256-UCWdo5AudWHE/cWmZGwk5hJSgLVRBdhrg8SPvswNisU=";
    fetchSubmodules = true; # moonlight-common-c has an enet submodule
  };
in
{
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

  winboat = prev.appimageTools.wrapType2 {
    pname = "winboat";
    version = "0.9.0";
    src = prev.fetchurl {
      url = "https://github.com/TibixDev/winboat/releases/download/v0.9.0/winboat-0.9.0-x86_64.AppImage";
      sha256 = "1xhf15ryad3zbm3d34gaj8n88cmmr610naxp4r00xvidpnv24lnk";
    };
    extraInstallCommands = let
      appimageContents = prev.appimageTools.extractType2 {
        pname = "winboat";
        version = "0.9.0";
        src = prev.fetchurl {
          url = "https://github.com/TibixDev/winboat/releases/download/v0.9.0/winboat-0.9.0-x86_64.AppImage";
          sha256 = "1xhf15ryad3zbm3d34gaj8n88cmmr610naxp4r00xvidpnv24lnk";
        };
      };
    in ''
      install -m 444 -D ${appimageContents}/winboat.desktop $out/share/applications/winboat.desktop
      substituteInPlace $out/share/applications/winboat.desktop \
        --replace-warn 'Exec=AppRun' 'Exec=winboat'
      cp -r ${appimageContents}/usr/share/icons $out/share/icons
    '';
  };

  # ── Moonlight Web Stream ──────────────────────────────────────────
  # WebRTC bridge: browser ←WebRTC→ web-server ←GameStream→ Sunshine
  moonlight-web-stream = nightlyRustPlatform.buildRustPackage {
    pname = "moonlight-web-stream";
    version = "2.7.0";
    src = moonlight-web-stream-src;

    cargoHash = "sha256-v98g6sXJgjNYtaXjz7iV4HYLVnpiA8y5TAeRQ/PF6KI=";

    nativeBuildInputs = with prev; [
      pkg-config
      cmake
      perl # openssl-sys vendored build needs perl for ./Configure
      nodejs_24
      npmHooks.npmConfigHook
      rustPlatform.bindgenHook
    ];

    buildInputs = with prev; [
      openssl
    ];

    npmDeps = prev.fetchNpmDeps {
      src = moonlight-web-stream-src;
      hash = "sha256-hT/RM9vdq5CYmZJm0kW0OUos/6uhCvxA8uVxkgFHqZI=";
    };

    # Nix's cargo vendoring doesn't recurse into git dependency submodules.
    # The moonlight-common-rust git dep has moonlight-common-sys which needs
    # moonlight-common-c compiled via cmake. Inject the C source here.
    postConfigure = ''
      for dir in $(find . -path "*/moonlight-common-sys" -type d 2>/dev/null); do
        if [ ! -f "$dir/moonlight-common-c/CMakeLists.txt" ]; then
          echo "Injecting moonlight-common-c into $dir/moonlight-common-c"
          rm -rf "$dir/moonlight-common-c"
          cp -r ${moonlight-common-c-src} "$dir/moonlight-common-c"
          chmod -R u+w "$dir/moonlight-common-c"
        fi
      done
    '';

    # Build TypeScript frontend before Rust compilation.
    # npm run build → generate-bindings (cargo test) → tsc → cpx static assets
    preBuild = ''
      npm ci
      patchShebangs node_modules
      npm run build
      mv dist static 2>/dev/null || true
    '';

    postInstall = ''
      mkdir -p $out/share/moonlight-web-stream
      cp -r static $out/share/moonlight-web-stream/
    '';

    doCheck = false;

    meta = with prev.lib; {
      description = "WebRTC bridge connecting browsers to Sunshine's GameStream protocol";
      homepage = "https://github.com/MrCreativ3001/moonlight-web-stream";
      license = licenses.gpl3Plus;
      platforms = platforms.linux;
      mainProgram = "web-server";
    };
  };
}
