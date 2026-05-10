-- NVIDIA-specific
hl.env("LIBVA_DRIVER_NAME",          "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME",  "nvidia")
hl.env("NVD_BACKEND",                "direct")
hl.env("GDK_DEBUG",                  "no-dmabuf")

-- Electron
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- GTK theming
hl.env("GTK_THEME", "Gruvbox-Material-Dark")

-- Default terminal
hl.env("TERMINAL", "kitty")

-- Cursor size
hl.env("XCURSOR_SIZE",   "24")
hl.env("HYPRCURSOR_SIZE", "24")
