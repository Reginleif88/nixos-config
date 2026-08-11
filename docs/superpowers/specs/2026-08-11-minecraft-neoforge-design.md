# Minecraft: Prism Launcher (official) + SKlauncher with NeoForge 1.21.1 (hyacinth)

**Date:** 2026-08-11
**Host:** hyacinth
**Files touched:** `modules/gaming.nix`, `overlays/default.nix`, `home/apps.nix`

## Problem

Two goals, one host:

1. Play official Minecraft (Microsoft account) with NeoForge 1.21.1.
2. Make NeoForge 1.21.1 available to SKlauncher, the launcher distributed from
   <https://skmedix.pl/downloads>.

Neither works today. `pkgs.minecraft` no longer exists, SKlauncher is not in
nixpkgs, and `~/.minecraft` does not exist on this machine at all.

## Environment facts (verified, not assumed)

- **`pkgs.minecraft` was removed from nixpkgs.** In the pinned tree it is a
  `throw` in `pkgs/top-level/aliases.nix:1603`: *"'minecraft' has been removed
  because the package was broken. Consider using 'prismlauncher' instead"*
  (added 2025-09-06). The official Mojang launcher is therefore not a
  one-line addition; it would require owning a custom derivation.
- **`sklauncher` is not in nixpkgs** either (no such attr; not an alias).
- Available and relevant: `prismlauncher-11.0.3`, `prismlauncher-unwrapped`,
  `glfw3-minecraft`, `openal-soft-1.24.3`, `openjdk-21.0.12+8` (`jdk21`).
  `glfw-wayland-minecraft` was renamed to `glfw3-minecraft` (aliases.nix:966).
- **Latest NeoForge for Minecraft 1.21.1 is `21.1.248`**, from
  `maven.neoforged.net` `maven-metadata.xml`. NeoForge 1.21.1 requires Java 21.
- **Prism's NixOS fix is `LD_LIBRARY_PATH`, nothing more.**
  `pkgs/by-name/pr/prismlauncher/package.nix:129` sets
  `--set LD_LIBRARY_PATH ${addDriverRunpath.driverLink}/lib:${makeLibraryPath runtimeLibs}`.
  It does **not** inject `-Dorg.lwjgl.*.libname`, and
  `prismlauncher-unwrapped` carries no native-library patch (its only patch
  rewrites `QApplication::applicationFilePath()` for the wrapper). The
  mechanism: Mojang's vendored `libglfw.so` / `libopenal.so` are valid
  binaries that merely cannot resolve their own `libX11.so.6` / `libGL.so.1`
  because NixOS has no `/usr/lib`. `LD_LIBRARY_PATH` is inherited by the game
  process the launcher spawns, so the deps resolve and the vendored natives
  load. **No FHS sandbox is required.**
- **The SKlauncher jar is pinnable with a vendor-published hash.** The download
  page is a Nuxt SPA; the real URL is built from `l.siteUrl` in a `_nuxt`
  chunk, which also carries the expected digests inline:

  | Property | Value |
  |---|---|
  | URL | `https://skmedix.pl/binaries/skl/3.2.18/SKlauncher-3.2.18.jar` |
  | Published SHA-256 | `25a73e3770a1d8d14bce53e8920e2e893aacc3c715d0fb22f878ef2090d03863` |
  | Downloaded SHA-256 | identical (verified) |
  | SRI | `sha256-Jac+N3Ch2NFLzlPokg4uiTqsw8cV0Psi+HjvIJDQOGM=` |
  | Size | 1 401 788 bytes |

- **The jar is a self-updating bootstrap.** Its manifest is
  `Main-Class: pl.skmedix.bootstrap.Main`, `Implementation-Version: 3.2.18`,
  `Multi-Release: true`; `Main.class` is major version 52 (Java 8 bytecode, so
  any modern JDK runs it). It fetches the real launcher at runtime. Pinning the
  bootstrap therefore does **not** create a version-lag treadmill — contrast
  Proton Mail, where the shipped version was the product.
- The jar bundles FlatLaf (`libflatlaf-linux-x86_64.so`), but **that is a red
  herring** — it styles only the bootstrap's own progress window. The launcher
  the bootstrap downloads renders through **JavaFX 22.0.2**, which SKlauncher
  fetches itself into `~/.minecraft/sklauncher/javafx/` (six jars:
  base/controls/graphics/media/swing/web). Discovered by running the wrapper,
  not by reading the jar: it died with `UnsatisfiedLinkError:
  libgthread-2.0.so.0: cannot open shared object file` out of
  `libglassgtk3.so`, JavaFX's GTK3 backend.
- **The NeoForge installer supports a headless client install.**
  `--install-client [File]` defaults to `/home/reginleif88/.minecraft`.
  Installer URL
  `https://maven.neoforged.net/releases/net/neoforged/neoforge/21.1.248/neoforge-21.1.248-installer.jar`,
  SRI `sha256-aO6rdwWbpT3xgS8a+lv1MKslZqPNzV+SSqbnG+QuQQw=`, 6 972 104 bytes.
- **The installer hard-fails on a directory with no launcher profile.** Run
  against an empty dir it printed *"There is no minecraft launcher profile in
  … you need to run the launcher first!"* / *"There was an error during
  installation"*. Writing a 27-byte `launcher_profiles.json` containing
  `{"profiles":{},"version":3}` was sufficient; the install then reported
  *"Successfully installed client into launcher"* and produced
  `versions/1.21.1` + `versions/neoforge-21.1.248` (121 MB total). Those are
  ordinary vanilla-format profiles, which is exactly what SKlauncher
  enumerates.
- `~/.minecraft` does not exist yet, and neither does `~/.sklauncher` or
  `~/.local/share/SKlauncher`. Nothing to migrate or preserve.
- `modules/gaming.nix` is imported only by `hosts/hyacinth/configuration.nix:64`,
  so it needs no `hostname` guard. It already carries `bolt-launcher`, a game
  launcher, in `environment.systemPackages` — direct precedent.

## Design

Two independent tracks. Prism keeps its own instance directories; SKlauncher
uses `~/.minecraft`. They share no state, so neither can break the other.

### Track 1 — official Minecraft via Prism Launcher

Add `prismlauncher` to `environment.systemPackages` in `modules/gaming.nix`.

Microsoft-account login and NeoForge 21.1.248 instance creation are both
in-app, so there is nothing further to configure. The wrapped `prismlauncher`
attr (not `-unwrapped`) is required — the wrapper is what supplies
`LD_LIBRARY_PATH` and `PRISMLAUNCHER_JAVA_PATHS`.

This replaces packaging the removed Mojang launcher. Rejected because nixpkgs
dropped it as broken and we would own that maintenance for a UI difference.

### Track 2 — SKlauncher, three pieces

**(a) `sklauncher` derivation** in `overlays/default.nix`, following the
existing `escrcpy` / `openwhispr` pattern: `version` + `hash` as the single
source of truth, with a comment stating what must be re-checked on a bump.

- `fetchurl` the pinned universal jar (URL and SRI above).
- Wrap `jdk21`'s `java -jar` via `makeWrapper`, setting `LD_LIBRARY_PATH` to
  `${addDriverRunpath.driverLink}/lib` followed by the **same library set
  nixpkgs validated for Prism**: `glfw3-minecraft`, `openal`, `alsa-lib`,
  `libjack2`, `libpulseaudio`, `pipewire`, `libGL`, `libx11`, `libxcursor`,
  `libxext`, `libxrandr`, `libxxf86vm`, `wayland`, `udev`, `vulkan-loader`,
  `lib.getLib stdenv.cc.cc`.
- The `driverLink` prefix is load-bearing on this host: it is how `libGL`
  finds the NVIDIA driver (GTX 1080 / 580.142).
- Reusing the nixpkgs list rather than hand-rolling one means the set is
  already proven against real Minecraft native loading.
- **Plus four libraries nixpkgs' Prism list omits**, found by auditing the
  vendored natives directly (see below): `libxi`, `libxinerama`,
  `libxkbcommon`, `libxrender`.

#### Why the list intentionally diverges from Prism's

LWJGL 3.3.3 ships a portable `libglfw.so` with almost no `DT_NEEDED` entries —
it `dlopen`s nearly everything by soname at runtime. `ldd` therefore reports it
as fully resolved even when it is not, and cannot be used to validate the
library set. Dumping its dlopen sonames and checking each against the wrapper's
search path found 13 unaccounted for:

| Soname(s) | Verdict |
|---|---|
| `libc`, `libm`, `libdl`, `libpthread`, `librt` | benign — glibc, always on the loader's default path |
| `libOSMesa.so.6/8`, `libGLES_CM.so.1`, `libdecor-0.so.0` | optional — software-GL fallback, a legacy GLES1 soname, and Wayland client-side decorations (unused; we run X11) |
| `libXi.so.6`, `libXinerama.so.1`, `libXrender.so.1`, `libxkbcommon.so.0` | **real gaps in the X11 path** — added |

Prism survives the same four gaps only by accident: the JVM's AWT loads `libXi`
and `libXrender` as `DT_NEEDED` of `libawt_xawt.so` through the JDK's own
RPATH, so a later `dlopen` finds an already-loaded soname and never touches the
filesystem. That is load-order luck, not a contract, and `libXi` is XInput2 —
Minecraft's mouse look. Four extra store paths cost nothing, so they are pinned
explicitly.

The same audit on `libopenal.so` found `libportaudio.so.2` (a redundant
alternative backend; ALSA/Pulse/JACK/PipeWire all resolve) and `libdbus-1.so.3`
(gates only OpenAL's RTKit realtime-priority hint). Both are **deliberately
omitted** — audio works without them.

#### Plus the launcher's own JavaFX/GTK3 stack

Separate from the game's natives, the launcher UI needs its own libraries. Taking
the union of unresolved `DT_NEEDED` entries across all 22 `.so` files in the
downloaded JavaFX jars gives: `glib` (libglib/libgio/libgmodule/libgobject/
libgthread), `gtk3` (libgtk-3/libgdk-3), `gdk-pixbuf`, `pango` (libpango/
libpangocairo/libpangoft2), `cairo` (libcairo/libcairo-gobject), `atk`,
`freetype`, `fontconfig`, `libxtst`. All are added.

Excluded from that union:

- `libavcodec` / `libavformat` at soversions 54, 56, 57, 58, 59 and 60 — the
  optional media `avplugin`s. Pinning six ffmpeg ABIs is not worth it; the cost
  is video inside the launcher's WebView, not the launcher.
- `libgstreamer-lite.so` and `libjvm.so` — shipped in the same jar and already
  present in the running JVM respectively, so they resolve unaided.

`GDK_BACKEND=x11` is set on the wrapper as well: JavaFX 22's glass backend is
GTK3-based but X11-only, so on Hyprland it would otherwise select GDK's Wayland
backend and fail. Same workaround, for the same reason, as the existing
`moonlight-qt` wrapper at `home/apps.nix:100`.

**(b) `neoforge-install` command**, also in `overlays/default.nix` so the
version pin sits alongside the other pinned sources. A single
`neoforgeVersion = "21.1.248"` variable drives the URL. The script:

1. `mkdir -p ~/.minecraft`
2. writes the `launcher_profiles.json` stub **only if absent** (never
   clobbers a real one)
3. runs the pinned installer with `jdk21`: `--install-client ~/.minecraft`

Idempotent and re-runnable. Bumping NeoForge is one string plus one hash.

**(c) Desktop entry** for SKlauncher in the hyacinth-only
`xdg.desktopEntries` block of `home/apps.nix`, mirroring `boosteroid`. A bare
jar ships no `.desktop` file.

### Rejected: a Home Manager activation script for the NeoForge install

Superficially more declarative, but it would run a 121 MB network install on
every `nixos-rebuild`, break offline rebuilds, and write into a tree the game
mutates constantly. `~/.minecraft` is inherently mutable state. Nix owns the
version pin, the JDK, and the procedure; it does not own the tree.

## Known, accepted caveats

- Both the SKlauncher UI and the game render through **XWayland**: JavaFX 22's
  GTK3 glass backend is X11-only (hence the forced `GDK_BACKEND=x11`), and
  Mojang's vendored GLFW is an X11 build. `glfw3-minecraft` is present for setups
  that can use it, but the vendored natives take precedence. Expected, not a
  defect.
- Video inside the launcher's WebView will not play, by choice (see the excluded
  ffmpeg ABIs above). The launcher itself is unaffected.
- SKlauncher self-updates its inner launcher at runtime, so the running version
  will drift above the pinned bootstrap version. That is the intended design.

## Verification

1. `nix fmt`, `statix check .`, `deadnix --fail .`,
   `nix flake check --no-build --show-trace` (the repo's documented gate).
2. `nix build` the two new overlay attrs.
3. `sudo nixos-rebuild switch --flake .#hyacinth`.
4. Run `neoforge-install`; assert `~/.minecraft/versions/neoforge-21.1.248`
   exists.
5. Launch `sklauncher`, confirm the `neoforge-21.1.248` profile is listed, and
   start the game. **Reaching the main menu is the only real proof the vendored
   natives loaded** — steps 1–4 cannot demonstrate it.
6. Launch `prismlauncher` and confirm it starts and offers NeoForge 1.21.1.
