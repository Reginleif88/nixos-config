# NixOS configuration audit

**Audit date:** 2026-07-12
**Scope:** both NixOS hosts, Home Manager, Hyprland, Quickshell, the Gruvbar plugin, overlays, secrets workflow, deployment scripts, live desktop state, and update/CI practices.

This was a read-only audit of the configuration. The only repository change made as part of it is this report.

## Executive summary

The configuration evaluates successfully, the running Hyprland Lua configuration has no reported configuration errors, and the flake lock is fully current as of the audit date. The most important work is not a broad package update; it is tightening secret handling, preventing expensive desktop workloads from starting unconditionally, separating the headless server from the desktop package stack, and replacing mutable activation-time deployments with reproducible builds.

The highest-impact findings are:

1. The live private SOPS age key is mode `0644`; it must be `0600` immediately. The setup script currently creates it without enforcing private permissions.
2. Quickshell creates one persistent Gemini `WebEngineView` per monitor, even while the sidebar is closed. The live Quickshell process was using about 505 MiB RSS.
3. The Windows Docker VM starts automatically with 16 GiB RAM and six vCPUs, and the FreeRDP client starts with every graphical session. At the observation point the container was using about 16.49 GiB RAM and approximately 493% CPU.
4. The headless `ignis` VPS inherits desktop media, GUI, Flatpak, font, development, Claude Desktop, and Kitty configuration. The module boundaries need to be split into minimal common, server, desktop, development, and media layers.
5. The public VPS disables CPU vulnerability mitigations, stores a password hash in the repository, binds unauthenticated code-server to all interfaces, opens an unnecessary port 443, and builds mutable application source during NixOS activation.
6. Desktop-only secrets are declared on both hosts, and the GitHub clone module persists the SOPS-provided PAT using `gh --insecure-storage`.
7. The desktop has TTY autologin but no declarative screen lock or idle/DPMS policy.
8. The CI update workflow was removed, the README still documents it and retired hosts, and several inputs, overlays, modules, scripts, and encrypted secret entries are now orphaned.

## Audit evidence and validation

### Successful checks

- `nix flake check --no-build --show-trace` evaluated both NixOS configurations successfully.
- `nix flake update --output-lock-file /tmp/nixos-config-audit.lock` produced a byte-identical lock file. There was no flake input update available on 2026-07-12.
- The running Hyprland build exactly matches the locked input: v0.55.0 development state at commit `f4b9c1a`, dated 2026-07-12.
- The running Quickshell build exactly matches the locked input: v0.3.0 at commit `4df562d`.
- `hyprctl configerrors` reported no errors. Hyprland identified Lua as the active configuration provider and loaded Gruvbar successfully.
- No failed system or user systemd units were present during the live check.
- Quickshell loaded without QML type or binding failures. Its warnings were mainly duplicated WebEngine/Gemini messages, GPU fallback messages, and the unavailable UPower service.
- The Git worktree was otherwise clean. `main` was one commit ahead of `origin/main` at audit time.

### Limits of the live measurements

Process and container measurements are snapshots, not controlled idle benchmarks. The Windows container and active desktop applications were doing real work. They are useful for finding obvious resource consumers, but compositor changes should be compared through repeatable A/B tests after the large consumers have been addressed.

No full system closure was built during this audit. The successful flake check proves evaluation, not that every package will build locally.

## Priority 0: immediate security and resource actions

### 1. Repair the SOPS age key permissions

The live key at `~/.config/sops/age/keys.txt` was owned by the user but had mode `0644`, allowing every local user to read the private decryption identity. [`scripts/target-setup.sh`](scripts/target-setup.sh#L30) decrypts or generates the file without `umask 077`, `install -m 0600`, or a final `chmod`.

Immediate one-time repair:

```sh
chmod 600 ~/.config/sops/age/keys.txt
```

Permanent repair:

- Put `umask 077` near the start of the setup script.
- Create the key directory with mode `0700`.
- Write the key through `install -m 0600`, or apply `chmod 600` after both the decrypt and generate paths.
- Add a validation that aborts if the key is group/world-readable.
- Never print private key contents in diagnostics.

### 3. Stop loading Gemini once per monitor at startup

[`GeminiSidebar.qml`](dotfiles/quickshell/bar/sidebar/GeminiSidebar.qml#L63) uses `Variants` to create a window per screen, and its loader becomes active whenever the shared profile exists rather than when that screen owns an open sidebar. On a two-monitor desktop this creates two persistent Chromium/WebEngine instances while the sidebar is visually closed.

The live Quickshell process used about 505 MiB RSS and the log showed duplicate Gemini WebEngine warnings, consistent with the duplicate instances.

Recommended order:

1. Instantiate the sidebar only for its target screen.
2. Use Quickshell `LazyLoader` so the window and WebEngine view do not exist before first use and can be unloaded after a suitable idle period.
3. Keep only one shared profile/view unless multi-screen simultaneous sidebars are intentional. => i only need this on the screen with workspace 1 only + only on workspace 1
4. Consider isolating the WebEngine sidebar in a separate Quickshell process or browser app. The WebView support is still carried as an unmerged Quickshell patch, so a WebEngine crash should not have to take down the core bar.

Quickshell explicitly documents `LazyLoader` for components and windows that should not consume memory before they are needed: [Quickshell LazyLoader documentation](https://quickshell.org/docs/v0.3.0/types/Quickshell/LazyLoader/). The WebView work remains an open upstream change: [Quickshell PR #351](https://github.com/quickshell-mirror/quickshell/pull/351).


### 5. Re-enable CPU governor  on `ignis`

The `performance` CPU governor on the KVM guest is likely ineffective and may only add a failing/no-op cpufreq unit. Remove it unless the guest exposes a real controllable governor and measurements justify it.

### 6. Tighten code-server and firewall exposure

[`modules/code-server.nix`](modules/code-server.nix#L39) still describes an old topology in which Cloudflare ran on another host. It now binds unauthenticated code-server to `0.0.0.0`, while the tunnel runs on the same machine.

- Bind code-server to `127.0.0.1`.
- Keep it out of the public firewall.
- Remove TCP 443 from [`hosts/ignis/configuration.nix`](hosts/ignis/configuration.nix#L59) unless an actual local service is verified to listen there. A Cloudflare tunnel is outbound and does not require this inbound opening.
- Update comments so future maintenance reflects the current OVH topology.

### 7. Move the console password hash into SOPS

[`hosts/ignis/configuration.nix`](hosts/ignis/configuration.nix#L75) commits a SHA-512 password hash. A public repository exposes it to unlimited offline cracking and the history retains it after removal.

Use a SOPS secret with `neededForUsers = true` and set `hashedPasswordFile` to the rendered secret. This is the documented sops-nix early-user-creation pattern: [sops-nix README](https://github.com/Mic92/sops-nix/blob/master/README.md).

Cleanup if possible repository history.

### 8. Make SSH defaults secure rather than host-overridden

[`modules/ssh-server.nix`](modules/ssh-server.nix#L4) defaults `PasswordAuthentication` to true, while `ignis` force-overrides both password and keyboard-interactive authentication off.

Set the shared module defaults to:

```nix
PasswordAuthentication = false;
KbdInteractiveAuthentication = false;
PermitRootLogin = "no";
```

Any future host that deliberately needs passwords should explicitly opt in.

## Priority 1: Hyprland modernization

### What is healthy

- The Lua migration is valid and active; no configuration errors were reported.
- The custom `hl.dsp(...)` dispatch expressions are supported by the pinned Hyprland Lua implementation.
- Gruvbar is ABI-matched and loaded successfully.
- The proprietary Nvidia module choice is appropriate for the Pascal GTX 1080; do not switch to the open kernel modules, which do not support Pascal.
- `LIBVA_DRIVER_NAME=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, and `NVD_BACKEND=direct` match current Hyprland/Nvidia guidance. See the [current Hyprland Nvidia guide](https://wiki.hypr.land/Nvidia/).
- `cursor.no_hardware_cursors = true` is a reasonable local Nvidia workaround. The modern default is automatic, so test before changing it rather than deleting it blindly.

### 12. Let Home Manager own the Lua configuration and session integration

[`home/hyprland.nix`](home/hyprland.nix#L15) disables Home Manager’s systemd integration to prevent a generated `hyprland.lua` collision, then manually recreates `hyprland-session.target`. Current Home Manager Lua support has `extraLuaFiles` and plugin configuration that can own the entry point while preserving hand-written modules.

Recommended migration:

- Configure the Lua entry through Home Manager.
- Map the existing files through `extraLuaFiles` rather than parallel `xdg.configFile` ownership.
- Declare Gruvbar through the module’s plugin support.
- Re-enable `wayland.windowManager.hyprland.systemd.enable`.
- Remove the manual target from [`home/hyprland.nix`](home/hyprland.nix#L103) and manual session bootstrap from [`autostart.lua`](dotfiles/hypr/autostart.lua#L5) after verifying the generated startup hook.

This reduces custom glue and ensures graphical user services are tied correctly to the compositor lifecycle.

### 13. Move autostarts to systemd user services

[`dotfiles/hypr/autostart.lua`](dotfiles/hypr/autostart.lua#L18) launches the keyring, hyprpaper, Quickshell, four clipboard watchers, swaync, Proton Mail, and Claude Desktop as fire-and-forget processes.

Create user services bound to `graphical-session.target` for long-running components. This provides restart policy, logging, ordering, duplicate prevention, and cleanup on compositor exit. Combine the clipboard watchers into a clearly named service or target. Remove the duplicate `gsettings` call because Home Manager already owns the dconf theme preference.

### 14. Disable normal-operation debug logs

[`dotfiles/hypr/look_and_feel.lua`](dotfiles/hypr/look_and_feel.lua#L54) sets `debug.disable_logs = false`, overriding Hyprland’s quiet default. The live rolling log recorded every title change and frequent Quickshell IPC activity.

Remove the override or set it to true. Enable verbose logs only in a temporary diagnostic generation.

### 15. Add hyprlock and hypridle

There is no declarative screen locking, suspend lock, or idle monitor power policy, while the desktop also uses TTY autologin. Add:

- `hyprlock` configuration. with SUPER + L for lock
- `hypridle` as a user service. but not auto idle, let user do lock + idle with SUPER + I
- Lock before suspend.
- A short idle lock followed by monitor DPMS off.
- Resume/DPMS-on handling.

The current listener and suspend coordination model is documented in the [Hypridle documentation](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/).

### 16. Re-test Nvidia workarounds one at a time

[`modules/nvidia.nix`](modules/nvidia.nix#L40) sets `AQ_NO_ATOMIC=1` as a black-screen workaround. Keep it until a controlled test proves it unnecessary; removing it without a rollback path could lose the graphical session. Test in a separate generation with a TTY and prior generation available.

The live DP-3 output reported VRR capability, contradicting the stale comment in [`settings.lua`](dotfiles/hypr/hosts/hyacinth/settings.lua#L17). After testing atomic KMS independently, test `misc.vrr = 2` (fullscreen-only) on DP-3 and verify frame pacing, cursor behavior, and multi-monitor stability.

[`env.lua`](dotfiles/hypr/hosts/hyacinth/env.lua#L5) globally sets `GDK_DEBUG=no-dmabuf`, disabling zero-copy DMA-BUF paths for every GTK application. Scope it to known broken applications or A/B test removing it with the current Nvidia stack. Avoid the global `GTK_THEME` override for GTK4/libadwaita; Home Manager GTK/dconf configuration is the more reliable owner.

Only after those changes are stable, consider testing `render.direct_scanout = auto` for fullscreen games/RDP. Gruvbar and overlays may prevent or complicate direct scanout, so measure it rather than assuming a win.

### 17. Harden and optimize Gruvbar

The plugin works, but its implementation has several maintainability/performance issues:

- [`bar.cpp`](plugins/gruvbar/bar.cpp#L185) treats every alignment other than `left` as centered, even though [`main.cpp`](plugins/gruvbar/main.cpp#L163) advertises `left|center|right`. Implement true right alignment or stop exposing it.
- Configuration reload only dirties button textures. Font, font size, text color, title enablement, and alignment changes do not reliably rebuild the title texture until a window title/size changes.
- Every title change recreates a Cairo/Pango render and GPU texture. Rapidly changing titles such as progress spinners amplify compositor work.
- Quickshell already displays the active title, so decide which bar owns this feature. If Gruvbar keeps it, debounce/rate-limit title texture rebuilds and add a configuration revision/dirty flag.

## Priority 2: Quickshell architecture and performance

### What is healthy

- The configuration uses modern native Quickshell services for Hyprland, MPRIS, PipeWire, NetworkManager, and BlueZ rather than parsing every subsystem through shell commands.
- The active configuration matches its pinned v0.3 target.
- No QML type/binding errors appeared in the live log.

### 18. Lazily create hidden popups and centralize shared state

Network, audio, music, system monitor, Gemini, and other popup objects are created for every screen even when hidden. Use `LazyLoader` for expensive, infrequently opened content.

[`NetworkPopup.qml`](dotfiles/quickshell/bar/network/NetworkPopup.qml#L98) binds the same global Bluetooth discovery and Wi-Fi scanner properties from each per-screen popup instance. With two monitors, those bindings can compete. Keep scanning/discovery state in one singleton/controller and render one popup on the selected screen.

### 19. Replace polling and subprocess churn

[`shell.qml`](dotfiles/quickshell/bar/shell.qml#L355) updates a clock every second even though it displays only hours and minutes. Use minute precision.

CPU and RAM each spawn an `awk` process every two seconds. Consolidate `/proc` reads into one sampler, use a QML file view/reload path where practical, or at least one packaged helper process.

Other improvements:

- Replace the Obsidian window-status `hyprctl`/shell polling with `Hyprland.toplevels`, which is already available in the process.
- Watch the Claude provider state file rather than polling it every 30 seconds.
- Merge the weather timers so startup cannot issue overlapping stale-cache fetches.
- Rewrite `weather.sh` to parse the response with one `jq` program rather than many subprocesses.
- Use fixed Massy coordinates if automatic IP geolocation is not valuable; periodic IP geolocation has a privacy cost.
- Package script helpers with `writeShellApplication` and explicit `runtimeInputs` rather than relying on a broad session `PATH`.

### 20. Remove dead Quickshell compatibility scripts and packages

The native QML migration left scripts with no QML references, including `bluetooth_panel.sh`, `wifi_panel.sh`, and `music_panel.sh`. Remove them after a final reference check. Then remove CLI dependencies that existed only for those scripts, such as `iw` or PulseAudio CLI tools, if no other consumer remains.

The only graphical host is a desktop and the live log reports that UPower cannot be activated. Remove the UPower import/battery widget or condition it on a laptop host. Do not enable a system daemon solely for a permanently absent battery.

### 21. Keep the WebEngine patch isolated and documented

The local Quickshell WebEngine wrapper patch is not stale: the upstream PR remains open, the `qArgC` workaround is still relevant, and the jemalloc interaction is still discussed upstream. Keep the patch if Gemini remains embedded, but:

- Document the exact upstream PR and why each patch hunk exists.
- Add an easy path to remove it when upstream merges an equivalent implementation.
- Prefer a separate process boundary for the unsupported WebEngine portion.
- Treat Gemini CSP console errors as site behavior unless they correspond to a broken feature; they are not QML configuration failures.

## Priority 2: Nix performance and lifecycle

### 22. Add automatic garbage collection

[`modules/common.nix`](modules/common.nix#L23) enables incremental store optimization but no automatic garbage collection. Add a host-appropriate policy, for example weekly deletion of generations older than 30 days, while retaining enough rollback history. A server may use a different window than the desktop.

Keep `auto-optimise-store` if desired; it remains supported. A scheduled optimization job can reduce latency during builds, but changing this is lower priority than GC and module splitting.

### 23. Scope Nix daemon tuning by host

The idle CPU/IO scheduling in [`modules/common.nix`](modules/common.nix#L34) is sensible for keeping the desktop responsive during local compiles, but on a server it can starve deployment work whenever other load exists. Move it to the desktop host or make it an option.

The global 256 MiB download buffer is large for an 8 GiB VPS. Measure whether it improves real transfers and tune per host; the default is safer if there is no demonstrated need.

### 25. Disable the systemd-boot editor

The evaluated desktop configuration leaves `boot.loader.systemd-boot.editor = true`. Set it to false near [`hosts/hyacinth/configuration.nix`](hosts/hyacinth/configuration.nix#L25). Editing a kernel command line at the boot menu can permit an `init=/bin/sh` physical-console root bypass.

### 26. Close unused Steam firewall ports

[`modules/gaming.nix`](modules/gaming.nix#L8) enables firewall openings for both Steam Remote Play and dedicated servers. The evaluated rules include multiple TCP/UDP ports and a UDP range. Disable each flag

## Priority 2: reproducibility, updates, and cleanup

### 27. Remove obsolete overlays, inputs, and modules

- The Jedi language server relaxation in [`overlays/default.nix`](overlays/default.nix#L36) is now redundant: the current root nixpkgs derivation already relaxes `jedi`.
- The patched `neatvnc` and rebuilt `wayvnc` overlay in [`overlays/default.nix`](overlays/default.nix#L20) has no remaining consumer after retired hosts were removed.
- The `nixos-hardware` input in [`flake.nix`](flake.nix#L38) is unused.
- `modules/amdgpu.nix` and `modules/nvidia-prime.nix` are orphaned. Remove them or clearly archive/document their intended future use.
- Remove other references to retired hosts and legacy remote-desktop paths after checking Git history for anything intentionally retained.

Every global overlay affects package evaluation for every host, so dead overrides are not merely cosmetic.

### 28. Update OpenWhispr

[`overlays/default.nix`](overlays/default.nix#L107) pins OpenWhispr 1.7.3. The current release is [OpenWhispr v1.7.5](https://github.com/OpenWhispr/openwhispr/releases/latest).

For the official x86_64 AppImage asset, the audit calculated:

```nix
version = "1.7.5";
hash = "sha256-InmwYfIw+CfvCYx2DwZDIS9l/yj+MK5m7AUoT0TvbO4=";
```

Verify the release notes and build before switching. The custom `escrcpy` 2.11.1 and `gtasks` 0.13.0 pins were current at audit time.
Verify why these are not updated with flake update or find a flake?

### 30. Fix non-reproducible Home Manager activations

[`home/ai.nix`](home/ai.nix#L27) says Claude/Codex settings must remain writable because the applications modify them, but every Home Manager activation unconditionally overwrites those files. Choose one model:

- Repository-authoritative: manage immutable/symlinked files and accept that app writes are not retained.
- User-authoritative: initialize only when missing, or merge known declarative keys without replacing application state.

Additional issues:

- Use an XDG cache/state directory rather than shared `/tmp/playwright-mcp`.
- The gtasks installer only registers the plugin if `installed_plugins.json` already exists; initialize a valid file for fresh installations or use the supported plugin mechanism.
- Avoid hardcoded 2026 timestamps and the literal `latest` directory/version as persistent plugin metadata.

# Stale applications

Check if there's any stale appimage

### 32. Refresh documentation

[`README.md`](README.md) still describes a ThinkPad and remote VM that no longer exist, lists PRIME/TLP/fingerprint and wayvnc/archive paths that are no longer present, and claims a CI update workflow that was deleted. It also links to a missing `LICENSE`.

Rewrite it from the evaluated configuration:

- Current hosts: `hyacinth` desktop and `ignis` OVH VPS.
- Current install paths, including disko/nixos-anywhere and host-specific SOPS key delivery.
- Current Hyprland Lua/Home Manager ownership model.
- Current update and validation commands.
- Windows workspace lifecycle.
- Recovery instructions for Nvidia/Hyprland failures.
- Add the intended license file or remove the link.

## Static quality findings

- `nixfmt --check` reported 22 Nix files not in canonical format.
- Statix primarily reported style/repeated-attribute-set opportunities, not a confirmed semantic defect.
- Deadnix’s meaningful result after suppressing lambda-pattern noise was the unused `pyfinal` argument in the Jedi overlay; removing that obsolete overlay resolves it.
- ShellCheck found the unused `WORKER_NAME` and risky cleanup expression in `scripts/horde-worker.sh`.
- The flake currently has no repository-native formatter, checks, dev shell, or pre-commit configuration.

Recommended baseline commands:

```sh
nix fmt
nix flake check --no-build --show-trace
statix check .
deadnix --fail .
shellcheck scripts/*.sh dotfiles/quickshell/bar/scripts/*.sh
```

Introduce formatting as its own mechanical commit so functional reviews remain readable.

## Configuration that should not be “updated” blindly

### State versions

`system.stateVersion = "25.11"` and `home.stateVersion = "25.11"` are migration compatibility settings, not package-version pins. Do not change them during ordinary upgrades. The official guidance is to leave them at the installation-era value unless a specific state migration is deliberately understood: [NixOS stateVersion FAQ](https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion).

### Nvidia atomic KMS workaround

Do not remove `AQ_NO_ATOMIC=1` in the same generation as other Nvidia, VRR, or rendering changes. Test one variable at a time with a TTY and known-good boot generation available.

### Hyprland/Quickshell input strategy

The lock is current. Hyprland tracking a development branch and Quickshell carrying a custom patch are intentional risk choices, not evidence that `flake update` was missed. If stability matters more than features, separately consider pinning release tags, but do not mix that policy decision into routine updates.


## Final assessment

The core configuration is in better shape than its accumulated comments and legacy scaffolding suggest: it evaluates, is fully updated, the Hyprland Lua migration works, and the modern native Quickshell integrations are sound. The main problem is boundary erosion. Desktop packages and secrets leak into the VPS, mutable app deployment leaks into Nix activation, per-screen UI construction leaks expensive WebEngine/global state into every monitor, and temporary compatibility code remains after its consumers disappear.

Addressing those boundaries will produce larger reliability, security, closure-size, and responsiveness gains than micro-tuning Hyprland. Once that work is complete, the Nvidia/VRR/direct-scanout experiments can be measured against a clean baseline instead of being obscured by a 16 GiB Windows VM and duplicate Chromium views.
