-- VM display: the AMD Barcelo iGPU is the only DRM device in the VM
-- (Proxmox `vga: none` + PCIe passthrough). DP-1 is forced on via the
-- video= kernel cmdline, and Hyprland renders directly through amdgpu/
-- radeonsi. VAAPI H.264 encode is wired into wayvnc via -g.

-- Electron
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- GTK theming (match hyacinth/wisteria)
hl.env("GTK_THEME", "Gruvbox-Material-Dark")

-- Default terminal
hl.env("TERMINAL", "kitty")

-- Cursor size (standard logical 24, no HiDPI scaling on virtual output)
hl.env("XCURSOR_SIZE",    "24")
hl.env("HYPRCURSOR_SIZE", "24")
