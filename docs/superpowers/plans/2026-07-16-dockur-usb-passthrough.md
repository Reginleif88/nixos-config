# Dockur USB Passthrough Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the BitLocker-encrypted TWSC USB stick attach automatically to the Windows 11 VM (`dockur/windows`) whenever it is plugged in, including while the VM is already running.

**Architecture:** Two independent layers, implemented as two tasks so failures can be isolated. Layer 1 (Docker) exposes bus 2's usbfs nodes to the container as a live bind mount plus a device-cgroup rule. Layer 2 (QEMU) tells the in-container QEMU to claim the device by vendor/product ID using its auto-scan filter, which polls every ~2s and attaches/releases on plug/unplug.

**Tech Stack:** NixOS (`virtualisation.oci-containers`), Docker, QEMU 10.0.11 (inside `dockurr/windows`), Linux usbfs.

**Spec:** `docs/superpowers/specs/2026-07-16-dockur-usb-passthrough-design.md`

## Global Constraints

- Target device: vendor `31c0`, product `1234`, serial `241213091243SRSQSV`.
- Device lives on **bus 2, port 6** (`2-6`), SuperSpeed 5000 Mbps. It stays on this port.
- USB device nodes are char major **189**; minor = `(busnum-1)*128 + (devnum-1)`. Bus 2 spans minors 128–255.
- Only file modified: `hosts/hyacinth/configuration.nix` (the `containers.windows` block, lines 99–134).
- Rebuild command is always: `sudo nixos-rebuild switch --flake .#hyacinth` (run from repo root).
- **Windows must be shut down cleanly before any rebuild** that recreates the container. The VM's disk image lives in `/var/lib/windows`; an unclean kill risks corrupting it.
- Do **not** write to `/run/shm/monitor.sock`. It is dockur's HMP control channel and the quickshell `DockurPopup` shutdown path depends on it.
- `devnum` changes on every replug. Never hardcode a device node path — always recompute it.

### Shared helper: locate the stick's current device node

Several steps need the live node path. Use this exact snippet on the **host**:

```bash
usbnode() {
  for d in /sys/bus/usb/devices/*/; do
    [ -f "$d/idVendor" ] || continue
    [ "$(cat "$d/idVendor")" = "31c0" ] || continue
    [ "$(cat "$d/idProduct")" = "1234" ] || continue
    printf "/dev/bus/usb/%03d/%03d\n" "$(cat "$d/busnum")" "$(cat "$d/devnum")"
  done
}
usbnode
```

Expected output (devnum will vary): `/dev/bus/usb/002/004`

If this prints nothing, the stick is unplugged. If it prints a `/dev/bus/usb/001/...` path, the stick failed SuperSpeed link training and landed on bus 1 — **stop**, replug it, and re-run. The bus-2-scoped design cannot see bus 1.

---

### Task 1: Expose bus 2 usbfs to the container

Deliverable: the stick's device node is visible **and openable** inside the container, while bus 1 (keyboard, mouse, tablet, Bluetooth) remains invisible. QEMU does not claim the device yet — that is Task 2.

**Files:**
- Modify: `hosts/hyacinth/configuration.nix:124-132` (the `volumes` and `extraOptions` lists)

**Interfaces:**
- Consumes: nothing.
- Produces: `/dev/bus/usb/002/<devnum>` readable inside the container `windows`; consumed by Task 2's QEMU `usb-host` device.

- [ ] **Step 1: Establish the red state — confirm the node is NOT visible in the container**

With the stick plugged in and the container running:

```bash
docker exec windows ls /dev/bus/usb/002/ 2>&1
```

Expected: `ls: cannot access '/dev/bus/usb/002/': No such file or directory`

This is the failing test. If it instead lists device nodes, the change is already applied — stop and re-read the file before proceeding.

- [ ] **Step 2: Shut Windows down cleanly**

```bash
pkexec systemctl stop docker-windows.service
```

Then confirm it is stopped:

```bash
systemctl is-active docker-windows.service
```

Expected: `inactive`

- [ ] **Step 3: Add the bind mount and the device-cgroup rule**

In `hosts/hyacinth/configuration.nix`, change the `volumes` list (currently lines 124–128) from:

```nix
      volumes = [
        "/var/lib/windows:/storage"
        "/home/reginleif88/Documents:/shared"
        "${windowsOem}:/oem:ro"
      ];
```

to:

```nix
      volumes = [
        "/var/lib/windows:/storage"
        "/home/reginleif88/Documents:/shared"
        "${windowsOem}:/oem:ro"
        # Live devtmpfs bind of USB bus 2 so on-demand hotplugged nodes appear
        # inside the container. Must NOT be `devices` — Docker's --device
        # snapshots nodes at container start, so a stick plugged in later would
        # never show up. Scoped to bus 2 to keep bus 1 (keyboard, mouse) out.
        "/dev/bus/usb/002:/dev/bus/usb/002"
      ];
```

And change the `extraOptions` list (currently lines 129–132) from:

```nix
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--stop-timeout=120"
      ];
```

to:

```nix
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--stop-timeout=120"
        # Visibility is not permission: Docker's device cgroup only allows the
        # major:minor pairs known at container start, so hotplugged nodes would
        # be visible but return EPERM. Wildcard is unavoidable — Docker cannot
        # express minor ranges, and bus 2 needs 128-255.
        "--device-cgroup-rule=c 189:* rwm"
      ];
```

- [ ] **Step 4: Rebuild**

```bash
cd /home/reginleif88/Documents/nixos-config && sudo nixos-rebuild switch --flake .#hyacinth
```

Expected: builds and activates without error.

- [ ] **Step 5: Verify the cgroup rule survived systemd escaping**

The rule contains a space (`c 189:* rwm`), so confirm it reached `docker run` as one argument rather than being split:

```bash
systemctl cat docker-windows.service | grep -- "--device-cgroup-rule"
```

Expected: a single `--device-cgroup-rule=c 189:* rwm` argument, quoted as one unit (e.g. `"--device-cgroup-rule=c 189:* rwm"`).

If it appears split across arguments, the NixOS module escaped it wrongly — stop and report; do not work around it by guessing.

- [ ] **Step 6: Verify green — the node is visible in the container**

Wait for the container to come up, then:

```bash
docker exec windows ls -l /dev/bus/usb/002/
```

Expected: device nodes listed, including one matching the `usbnode` helper's output (e.g. `004`).

- [ ] **Step 7: Verify green — the node is openable (cgroup rule works)**

Self-contained (does not rely on the `usbnode` helper being defined in this shell):

```bash
NODE=$(for d in /sys/bus/usb/devices/*/; do
  [ -f "$d/idVendor" ] || continue
  [ "$(cat "$d/idVendor")" = "31c0" ] || continue
  [ "$(cat "$d/idProduct")" = "1234" ] || continue
  printf "/dev/bus/usb/%03d/%03d\n" "$(cat "$d/busnum")" "$(cat "$d/devnum")"
done)
echo "host node: $NODE"
docker exec windows sh -c "if : < '$NODE'; then echo OPENABLE; else echo DENIED; fi"
```

Expected: `OPENABLE`

`DENIED` (EPERM) means the bind mount worked but the cgroup rule did not — the two halves are independent, which is exactly why they are verified separately here.

- [ ] **Step 8: Verify the isolation actually holds**

```bash
docker exec windows ls /dev/bus/usb/
```

Expected: `002` only. Bus `001` must NOT be present — that is what keeps the keyboard and mouse out of the container's view.

- [ ] **Step 9: Verify the host is unharmed**

Confirm the keyboard and mouse still work, and that the host still sees the stick (QEMU has not claimed it yet):

```bash
lsblk -o NAME,FSTYPE,TRAN | grep -E "sdb|NAME"
```

Expected: `sdb` present with `sdb1` = `BitLocker`. Task 2 is what makes this disappear.

- [ ] **Step 10: Commit**

```bash
cd /home/reginleif88/Documents/nixos-config
git add hosts/hyacinth/configuration.nix
git commit -m "feat(dockur): expose USB bus 2 to the Windows container

Bind-mounts /dev/bus/usb/002 as a volume (not devices) so on-demand
hotplugged nodes appear live inside the container, plus a device-cgroup
rule for usbfs major 189 to make them openable.

Scoped to bus 2 so the container cannot see bus 1, where the keyboard
and mouse live.

Claude-Session: https://claude.ai/code/session_01Y9q4QG2WmtfNiTp2hMSSnE"
```

---

### Task 2: Make QEMU claim the stick automatically

Deliverable: the stick attaches to the running Windows VM on plug and releases on unplug, with no container restart. Windows prompts for the BitLocker password.

**Files:**
- Modify: `hosts/hyacinth/configuration.nix:112` (the `ARGUMENTS` environment variable)

**Interfaces:**
- Consumes: `/dev/bus/usb/002/<devnum>` openable inside the container (Task 1).
- Produces: nothing downstream.

- [ ] **Step 1: Establish the red state — the host owns the device**

With the stick plugged in and the VM running:

```bash
ls -l /sys/bus/usb/devices/2-6/2-6:1.0/driver
```

Expected: a symlink pointing at `usb-storage`.

This is the failing test. The host's `usb-storage` driver currently owns the stick, which is why `/dev/sdb` exists and Windows sees nothing. When QEMU claims the device via libusb, it detaches this kernel driver — so this symlink disappearing is the signal that passthrough took effect.

- [ ] **Step 2: Shut Windows down cleanly**

```bash
pkexec systemctl stop docker-windows.service
systemctl is-active docker-windows.service
```

Expected: `inactive`

- [ ] **Step 3: Tell QEMU to claim the device by ID**

In `hosts/hyacinth/configuration.nix`, change line 112 from:

```nix
        ARGUMENTS = "-rtc base=localtime";
```

to:

```nix
        # usb-host with vendorid/productid registers a QEMU auto-scan filter:
        # it polls ~every 2s and attaches/releases the stick on plug/unplug
        # with the VM running. Matching by ID (not hostbus/hostaddr) is what
        # survives devnum changing on every replug.
        ARGUMENTS = "-rtc base=localtime -device usb-host,vendorid=0x31c0,productid=0x1234";
```

- [ ] **Step 4: Rebuild**

```bash
cd /home/reginleif88/Documents/nixos-config && sudo nixos-rebuild switch --flake .#hyacinth
```

Expected: builds and activates without error.

- [ ] **Step 5: Verify QEMU started and did not error on the USB device**

```bash
docker logs windows 2>&1 | grep -iE "usb|libusb" | head -20
```

Expected: no `libusb` claim failures, no `could not open host usb device`, and no QEMU startup abort. QEMU must start cleanly even if the stick is absent — the auto-scan filter is designed for exactly that.

- [ ] **Step 6: Verify green — QEMU took the device from the host**

Give QEMU ~5s to poll, then:

```bash
basename "$(readlink -f /sys/bus/usb/devices/2-6/2-6:1.0/driver)"
lsblk -o NAME,FSTYPE,TRAN | grep -E "sdb|NAME"
```

Expected: driver is **`usbfs`** (not `usb-storage`), and `sdb` no longer appears
in `lsblk`. Both confirm libusb detached `usb-storage` and QEMU now owns the
device.

Note: the `driver` symlink does **not** disappear — libusb *rebinds* the
interface to `usbfs`, the kernel's "userspace owns this" state. Testing for the
symlink's absence gives a false negative. Verified 2026-07-16.

- [ ] **Step 7: Verify Windows sees the drive**

Connect to the VM (RDP, or the web viewer on `127.0.0.1:8006`). In Windows, confirm the drive appears and prompts for the BitLocker password. Unlock it and confirm the contents are readable.

Expected: BitLocker prompt appears; drive unlocks and reads.

- [ ] **Step 8: Verify hotplug — the whole point of the feature**

With the VM still running, physically unplug the stick. Confirm Windows shows the removal. Then plug it back into the **same bus-2 port**.

```bash
for d in /sys/bus/usb/devices/*/; do
  [ -f "$d/idVendor" ] || continue
  [ "$(cat "$d/idVendor")" = "31c0" ] || continue
  printf "/dev/bus/usb/%03d/%03d (speed %s)\n" \
    "$(cat "$d/busnum")" "$(cat "$d/devnum")" "$(cat "$d/speed")"
done
```

Expected: prints a `/dev/bus/usb/002/...` path with a **new** devnum, at speed `5000`.

Then within ~5s:

```bash
lsblk -o NAME,TRAN | grep sdb
```

Expected: no output. On replug the kernel binds `usb-storage` first, so `sdb` may flicker into existence for a second or two before QEMU's auto-scan detaches it — that brief window is expected. What matters is that it does not persist.

Confirm the drive reappears in Windows and prompts for BitLocker again, **without any container restart**.

- [ ] **Step 9: Verify the host is still unharmed**

Confirm the keyboard, mouse, tablet, and Bluetooth all still work on the host — none of them are on bus 2, so none should have been touched.

- [ ] **Step 10: Commit**

```bash
cd /home/reginleif88/Documents/nixos-config
git add hosts/hyacinth/configuration.nix
git commit -m "feat(dockur): auto-attach the BitLocker USB stick to the Windows VM

QEMU's usb-host auto-scan filter matches the stick by vendor/product ID
and attaches it on plug, releases on unplug, with the VM running. Matching
by ID rather than hostbus/hostaddr survives devnum changing on replug.

BitLocker rules out the SAMBA /shared alternative: the host cannot decrypt
the volume, so there is nothing to share.

Claude-Session: https://claude.ai/code/session_01Y9q4QG2WmtfNiTp2hMSSnE"
```

---

## Troubleshooting

Symptom-to-layer mapping, ordered by likelihood. The two-task split exists so these can be told apart.

| Symptom | Layer | Cause |
|---|---|---|
| `usbnode` prints a `/dev/bus/usb/001/...` path | Hardware | Stick failed SuperSpeed training and landed on bus 1. The bus-2 bind mount cannot see it. Replug into the bus-2 port. |
| `usbnode` prints nothing | Hardware | Stick is unplugged or dead. |
| Node not visible in container (Task 1 Step 6) | Docker | Bind mount missing or the container was not recreated. Check `docker inspect windows` for the mount. |
| Node visible but `DENIED` (Task 1 Step 7) | Docker | The cgroup rule did not apply. Check Step 5's escaping check. |
| Node openable but driver still `usb-storage` (Task 2 Step 6) | QEMU | `ARGUMENTS` typo, or QEMU has no USB controller to attach to. Check `docker logs windows`. Driver `usbfs` means QEMU *did* claim it — that is success, not failure. |
| Windows never shows the drive but host lost `sdb` | Windows | QEMU claimed it successfully; the problem is inside the guest. |
| A second identical stick gets grabbed too | Design limit | `31c0:1234` is a generic ID. Documented in the spec; no fix within the auto-scan approach. |

## Deferred (not in this plan)

`--cap-drop=MKNOD`. Docker grants `CAP_MKNOD` by default, so a root process in the container could fabricate its own bus-1 device node and bypass the bind-mount scoping. This makes the bus-2 scoping defense-in-depth rather than a hard boundary. Dropping the capability may break dockur's entrypoint, so it needs testing on its own rather than being coupled to landing working passthrough. See the spec's "Known limitations".
