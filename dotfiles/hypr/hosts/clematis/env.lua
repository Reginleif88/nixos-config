-- Headless VM: no real display, no GPU vendor overrides.
-- AMD Barcelo iGPU runs through generic Mesa/amdgpu drivers from
-- modules/amdgpu.nix; VAAPI used by wayvnc for H.264 encode.

-- Electron
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- GTK theming (match hyacinth/wisteria)
hl.env("GTK_THEME", "Gruvbox-Material-Dark")

-- Default terminal
hl.env("TERMINAL", "kitty")

-- Cursor size (standard logical 24, no HiDPI scaling on virtual output)
hl.env("XCURSOR_SIZE",    "24")
hl.env("HYPRCURSOR_SIZE", "24")
