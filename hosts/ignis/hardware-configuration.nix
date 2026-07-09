{ lib, ... }:

# Hand-written for the OVH KVM VPS. Unlike the other hosts this is NOT the output
# of nixos-generate-config: disko (./disko.nix) owns all fileSystems/swap, so the
# only machine-specific facts left here are the initrd drivers needed to see the
# virtio-scsi root disk at boot and the host platform. The Proxmox qemu-guest
# PROFILE is deliberately not imported (the QEMU guest-agent is archived for this
# host); the virtio kernel modules it would have pulled in are listed explicitly
# instead — without them the machine cannot mount root and will not boot.
{
  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
