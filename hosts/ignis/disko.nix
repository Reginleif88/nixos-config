{ ... }:

# Declarative disk layout for the `ignis` OVH KVM VPS, consumed by disko during
# the nixos-anywhere install. The box boots in LEGACY BIOS mode (no
# /sys/firmware/efi), so this is a GPT disk carrying a 1 MiB BIOS-boot partition
# (type EF02 / bios_grub) for GRUB's core image, plus a single ext4 root filling
# the rest. No ESP: nothing here boots via UEFI. Swap is provided by zram in the
# host config, not a disk partition.
#
# The disk is addressed by its stable /dev/disk/by-id path (the QEMU virtio-scsi
# serial) rather than /dev/sda, so a kernel reorder can never point the install
# at the wrong device.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0-0-0-0";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02"; # BIOS boot partition — GRUB core.img on GPT
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
