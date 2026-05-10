-- Laptop: PRIME offload (Intel iGPU primary)

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
