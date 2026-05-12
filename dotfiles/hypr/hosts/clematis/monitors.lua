-- Proxmox exposes the VM display as a normal KMS output through VirtIO/QEMU.
-- Keeping Hyprland on this real virtual monitor is more reliable than the
-- Aquamarine headless-output path, and wayvnc captures this output directly.

hl.monitor({ output = "Virtual-1", mode = "1920x1080@60", position = "0x0", scale = 1.0 })
