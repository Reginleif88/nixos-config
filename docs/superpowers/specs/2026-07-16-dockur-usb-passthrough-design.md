# Auto-attach BitLocker USB stick to the dockur/windows VM (hyacinth)

**Date:** 2026-07-16
**Host:** hyacinth
**File touched:** `hosts/hyacinth/configuration.nix`

## Problem

A BitLocker-encrypted USB stick should appear in the Windows 11 VM
(`dockur/windows`) automatically whenever it is plugged in, including while the
VM is already running. It is plugged in on demand, not left connected.

Linux cannot unlock a BitLocker volume, so the host sees only an opaque
encrypted blob (`sdb1`, `FSTYPE=BitLocker`, never mounted). Sharing the stick
through the existing `SAMBA = "Y"` / `/shared` volume is therefore impossible —
the host has nothing readable to share. Raw USB passthrough is the only option
that lets Windows' own BitLocker driver perform the unlock.

## Target device

| Property | Value |
|---|---|
| Vendor:Product | `31c0:1234` (TWSC, generic controller) |
| Serial | `241213091243SRSQSV` |
| Physical port | bus 2, port 6 (`2-6`), SuperSpeed 5000 Mbps |
| Host block device | `/dev/sdb`, partition `sdb1` = BitLocker, unmounted |

The stick stays on this port. Bus 2 carries only the USB 3 root hub and the
Corsair ST100 USB 3.1 hub — no input devices. Bus 1 carries the keyboard,
mouse, tablet, and Bluetooth adapter.

## Environment facts (verified, not assumed)

- QEMU inside the container is **10.0.11**, which supports the `usb-host`
  auto-scan filter.
- The container currently has **no** `/dev/bus/usb` at all.
- dockur exposes an HMP monitor socket at `/run/shm/monitor.sock`; the
  quickshell `DockurPopup` shutdown path depends on it. This design does not
  touch that socket.
- USB device nodes are major **189**; minor = `(busnum-1)*128 + (devnum-1)`, so
  bus 2 spans minors 128–255.

## Design

Three changes to the `virtualisation.oci-containers.containers.windows` block.

### 1. QEMU claims the device by ID

```nix
ARGUMENTS = "-rtc base=localtime -device usb-host,vendorid=0x31c0,productid=0x1234";
```

Matching by vendor/product ID rather than `hostbus`/`hostaddr` is what makes
this automatic: QEMU registers an auto-scan filter and polls on a ~2s timer,
attaching the stick when it appears and releasing it on unplug. No udev rule, no
helper script, no container restart. The existing `-rtc base=localtime` is
preserved; dockur already instantiates a USB controller (it passes
`-device usb-tablet`), so `usb-host` has a bus to attach to.

### 2. Bus 2 exposed as a live bind mount

```nix
volumes = [
  # ...existing...
  "/dev/bus/usb/002:/dev/bus/usb/002"
];
```

This must be a `volume`, **not** `devices`. Docker's `--device` on a directory
expands to the device nodes present *at container creation*; a stick plugged in
later gets a new node that was never mapped, so it would stay invisible forever.
A volume bind-mounts the live devtmpfs directory, so hotplugged nodes appear
immediately.

Scoping to `002` rather than all of `/dev/bus/usb` keeps bus 1 — keyboard,
mouse, tablet, Bluetooth — outside the container's view.

### 3. usbfs major permitted

```nix
extraOptions = [
  # ...existing...
  "--device-cgroup-rule=c 189:* rwm"
];
```

Visibility is not permission. Docker's device cgroup allows only the major:minor
pairs known at container start, so a hotplugged node would be visible but return
`EPERM` without this rule. The wildcard is unavoidable: Docker cannot express
minor *ranges*, and bus 2 needs 128–255. The narrow bind mount in (2) is what
actually constrains reach.

## Known limitations

- **Bind mount is defense-in-depth, not a boundary.** Docker grants `CAP_MKNOD`
  by default, so a root process inside the container could create its own node
  for a bus-1 device and open it. `--cap-drop=MKNOD` would close this, but must
  be tested — dockur's entrypoint may rely on `mknod`. Deferred; not part of the
  initial change.
- **Generic ID.** `31c0:1234` is a no-name controller ID. A second identical
  stick would also be claimed. The serial is the more precise key but QEMU's
  auto-scan filter cannot match on it.
- **Bus-2 dependence.** If the stick ever fails SuperSpeed link training it
  enumerates on bus 1, and passthrough silently will not see it. This was
  observed once mid-investigation (`1-1 @ 480Mbps`), on a different physical
  port. Symptom: stick appears on the host but never in Windows.
- **Host driver contention.** The host binds `usb-storage` to the stick.
  QEMU's libusb backend detaches the kernel driver when claiming the interface;
  this normally resolves itself but is the most likely failure point.
- **Container recreation.** Applying this recreates the container, restarting
  the Windows VM. Shut Windows down cleanly first.
- **Never plug in during Windows Setup.** Upstream warns a mass-storage device
  present during setup can be formatted as the system disk. Setup is long
  complete here, so this is a non-issue, but it is why the stick must never be
  connected on a fresh `/var/lib/windows`.

## Verification

1. Rebuild; confirm the container starts and Windows boots.
2. With the VM running and the stick unplugged, plug it in.
3. Host: confirm the node appears under `/dev/bus/usb/002/`.
4. Container: confirm the same node is visible and openable (not `EPERM`).
5. QEMU: confirm it attached (no `libusb` claim errors in container logs).
6. Windows: confirm the drive appears and prompts for the BitLocker password.
7. Unplug; confirm QEMU releases it and Windows shows the removal.
8. Confirm keyboard and mouse remain functional on the host throughout.

## Rejected alternatives

- **SAMBA / `/shared` volume.** Impossible: the host cannot decrypt BitLocker,
  so there is nothing to share.
- **udev rule + `device_add` over the monitor socket.** Would allow matching the
  serial number exactly, but adds imperative machinery and contends with
  dockur's own monitor socket, which the DockurPopup shutdown path uses.
- **VFIO passthrough of a whole USB controller.** Requires clean IOMMU group
  isolation and removes every port on that controller from the host.
  Disproportionate for one flash drive.
