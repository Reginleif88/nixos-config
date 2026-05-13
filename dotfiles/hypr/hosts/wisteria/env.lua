-- Laptop: PRIME offload (Intel iGPU primary)

-- Scope aquamarine to the Intel iGPU. The eDP panel is wired only to it;
-- without this, Hyprland can pick the dGPU (no connected outputs, asleep
-- under PRIME finegrained PM) and come up to a black screen.
--
-- Must use /dev/dri/cardN here, NOT the /dev/dri/by-path/ symlink:
-- aquamarine splits AQ_DRM_DEVICES on ':' for multi-card values, so any
-- path containing PCI colons (pci-0000:00:02.0) shatters into nonsense
-- fragments and DRM enumeration fails entirely.
--
-- On wisteria nvidia loads before i915, so the dGPU lands on card0 and
-- the Intel iGPU on card1. Verify after kernel/module changes with
-- `ls -l /dev/dri/by-path/`.
hl.env("AQ_DRM_DEVICES", "/dev/dri/card1")

-- Aquamarine 0.11 picks up DRM_CAP_SYNCOBJ_TIMELINE (which 0.10 ignored)
-- and uses timeline syncobjs to track page-flip completion. On this host
-- the first few commits fail with "Cannot commit when a page-flip is
-- awaiting" and the scanout pipeline parks waiting for a completion
-- event that never arrives: compositor stays alive (input, IPC, autostart
-- all fire) but the panel stays black and VT switching wedges. Same fix
-- and same root mechanism as commit b4ed1cb on hyacinth (NVIDIA-only) —
-- here it manifests even with Intel scanout, likely because nvidia-drm
-- is still loaded on card0 alongside i915 on card1. AQ_NO_ATOMIC=1 drops
-- aquamarine back to the legacy drmModeSetCrtc / drmModePageFlip path.
-- Costs: no DRM gamma adjustment (we don't use hyprsunset), no async
-- commits, no atomic test-commits.
hl.env("AQ_NO_ATOMIC", "1")

-- Electron
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- GTK theming
hl.env("GTK_THEME", "Gruvbox-Material-Dark")

-- Default terminal
hl.env("TERMINAL", "kitty")

-- HiDPI scaling
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- Cursor size (32 logical × 1.5 scale = 48 physical)
hl.env("XCURSOR_SIZE",    "32")
hl.env("HYPRCURSOR_SIZE", "32")
