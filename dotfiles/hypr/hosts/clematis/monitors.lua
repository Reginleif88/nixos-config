-- The Proxmox VM runs with `vga: none` and the AMD Barcelo iGPU passed
-- through via VFIO as the only DRM device. There is no monitor physically
-- attached to the iGPU's outputs, so `video=DP-1:1920x1080@60e` on the
-- kernel cmdline (see hosts/clematis/configuration.nix) spoofs DP-1 as
-- connected. Hyprland renders on amdgpu/radeonsi here, not llvmpipe, and
-- wayvnc captures DP-1 with VAAPI hardware H.264 encode.

hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "0x0", scale = 1.0 })
