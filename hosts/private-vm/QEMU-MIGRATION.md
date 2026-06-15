# private-vm: vz → qemu migration

This document is a staged execution plan for migrating the private-vm Lima
instance from `vmType: vz` to `vmType: qemu`. It is written to be executed
by an agent starting with no prior conversation context.

## Goal & motivation

We want **demand-driven host memory** for the private-vm: when the guest
frees memory (browser closed, cache dropped, build finished), the macOS
host should reclaim those physical pages. Today, with `vmType: vz`, the
host RSS for the VM is pinned near its configured ceiling regardless of
guest behavior, because:

1. Apple's Virtualization.framework exposes only the *traditional* virtio
   balloon device (no Free Page Reporting), AND
2. Lima 2.1.2 doesn't surface the balloon device knob on vz at all.

Switching to `vmType: qemu` enables `virtio-balloon-pci` with the
`free-page-reporting=on` feature, which makes the guest proactively
report newly-freed page frame numbers to the host; qemu then madvise's
them. On Linux that's `MADV_DONTNEED` (immediate RSS drop). On macOS
it's `MADV_FREE_REUSABLE`: the pages stay attributed to the qemu
process's RSS but are flagged "reclaim me without I/O when you need
to" — they show up as `vm_stat` purgeable. From a real-host-pressure
standpoint that's the same outcome; only the accounting metric
differs. No polling daemon required; no `drop_caches` cron needed.

This migration is split into phases. **This document covers Phase 1
only.** Phase 2 (custom qemu build with virglrenderer + native GL
window + retiring RDP) is deferred until Phase 1 is stable.

### Empirical baseline (from before this plan)

With `vmType: vz`, `memory: "4GiB"`, idle guest:

- Host RSS of `com.apple.Virtualization.VirtualMachine`: **~4.6 GiB**
- Guest `MemAvailable`: 3.4 GiB free out of 3.9 GiB total
- Guest `Cached + Buffers + SReclaimable`: 2.2 GiB (page cache)
- After `echo 3 > /proc/sys/vm/drop_caches` inside the guest:
  - Guest reclaim: −2146 MB (worked as expected)
  - **Host RSS change: +13 MB (no reclaim — proves the vz limitation)**

We expect Phase 1 to make the equivalent test show host RSS dropping
meaningfully after FPR ships freed PFNs back.

## Pre-flight checks

Before making any changes, verify these still hold (the plan assumes
them; if any fails, stop and re-evaluate):

1. **Lima version** is 2.1.x:
   ```
   limactl --version
   ```
   The escape hatch we depend on is the `QEMU_SYSTEM_AARCH64` env var
   honored in `pkg/driver/qemu/qemu.go` function `Exe()`. Still present
   as of 2.1.2. Verify with:
   ```
   nix-src-search lima '*.go' 'QEMU_SYSTEM_'
   ```
   Expect: a hit in `pkg/driver/qemu/qemu.go` around line 1107.

2. **Default nixpkgs qemu has balloon**:
   ```
   qemu-system-aarch64 -device help 2>&1 | grep virtio-balloon-pci
   ```
   Expect: `name "virtio-balloon-pci", bus PCI, alias "virtio-balloon"`.

3. **The VM's bootstrap qcow2 was built with `qemu-efi`** (it's already
   qemu-bootable; no rebuild needed for vmType switch):
   ```
   ls -lh ~/.local/share/private-vm/images/bootstrap/
   ```
   Expect: a symlink resolving to
   `/nix/store/<hash>-nixos-disk-image/nixos-image-efi-qcow2-*.qcow2`.

4. **VM is currently running under vz** (so we have a known-good
   starting state to roll back to):
   ```
   limactl --tty=false list private-vm 2>/dev/null || \
     LIMA_HOME="$HOME/.local/state/private-vm/lima" limactl list private-vm
   ```
   Expect: STATUS=Running, VMTYPE=vz.

5. **Current host RSS of the VM** (record the number — used later for
   the before/after comparison):
   ```
   ps -o rss -p $(pgrep -f "com.apple.Virtualization.VirtualMachine" | head -1) \
     | awk 'NR==2 {printf "vz host RSS: %.0f MB\n", $1/1024}'
   ```

## What this plan changes

Three pieces, all in `~/etc/`:

1. **New file `modules/private-vm/qemu-wrapper.nix`** — a tiny nix module
   that produces a wrapper shell script. The wrapper is invoked by Lima
   as if it were qemu; it rewrites the argv to inject the balloon
   device, then execs the real qemu.

2. **`hosts/private-vm/lima.yaml`** — change `vmType: vz` → `vmType: qemu`.
   Memory stays at 8GiB (or whatever the file currently has; do not
   change it as part of Phase 1).

3. **`modules/private-vm/default.nix`** — in `vmStart` (and only there),
   export `QEMU_SYSTEM_AARCH64=<wrapper>` before invoking `limactl start`.

`hosts/private-vm/full.nix` also contains a now-pointless `drop_caches`
systemd timer added in an earlier session. **Leave it in place for
Phase 1.** It does no harm; we'll remove it as part of Phase 2 cleanup
to keep this change minimal and easy to revert.

## Step 1: Write the qemu wrapper module

Create `~/etc/modules/private-vm/qemu-wrapper.nix`:

```nix
{ inputs, ... }:
{
  flake.homeManagerModules.private-vm-qemu-wrapper =
    { pkgs, lib, ... }:
    let
      # Wrapper installed as `qemu-system-aarch64` on a private prefix.
      # Lima resolves QEMU via `exec.LookPath("qemu-system-aarch64")` after
      # consulting $QEMU_SYSTEM_AARCH64 (see Lima pkg/driver/qemu/qemu.go
      # Exe()). We point that env var at this wrapper, so Lima invokes it
      # exactly as it would the real qemu — same argv shape, same probes
      # (--version, -accel help, etc. — pass through unchanged).
      #
      # On real VM start, Lima passes a long argv. We inject one extra
      # device:
      #   -device virtio-balloon-pci,free-page-reporting=on
      # which the Linux guest's virtio_balloon driver negotiates and uses
      # to proactively report freed PFNs to qemu; qemu MADV_DONTNEEDs the
      # backing host pages. No polling required.
      #
      # We detect "real start" by presence of `-machine virt` (Lima always
      # uses it for aarch64). Probe invocations (--version, -accel help,
      # -netdev help, etc.) don't carry -machine virt, so they pass
      # through cleanly.
      realQemu = "${pkgs.qemu}/bin/qemu-system-aarch64";
      wrapper = pkgs.writeShellApplication {
        name = "qemu-system-aarch64";
        runtimeInputs = [ ];
        text = ''
          # If invoked as a probe (e.g., --version, -accel help), just
          # exec the real qemu unchanged. Lima runs several such probes
          # during start to inspect capabilities and version.
          is_start=0
          for arg in "$@"; do
            if [[ "$arg" == "virt" ]]; then
              is_start=1
              break
            fi
          done

          if (( is_start == 0 )); then
            exec ${realQemu} "$@"
          fi

          # Real VM start: inject the balloon device. virtio-balloon-pci
          # with free-page-reporting=on is the FPR-capable form. Order
          # doesn't matter to qemu; we append at the end.
          exec ${realQemu} "$@" \
            -device virtio-balloon-pci,free-page-reporting=on
        '';
      };
    in
    {
      home.packages = lib.optionals pkgs.stdenv.isDarwin [ wrapper ];
    };
}
```

Then wire the new module into the existing `home.packages` for the
private-vm home-manager profile. Look in `modules/private-vm/default.nix`
for where `home.packages = [ vm ]` is set. We need to either:

- Add the wrapper to the same `home.packages` list (move the wrapper
  derivation into `default.nix` next to `vm`), OR
- Make sure the new module is imported alongside the existing one.

The simpler path: **fold the wrapper directly into the existing
`modules/private-vm/default.nix`** rather than making a separate module.
Put the `realQemu` / `wrapper` `let` bindings next to the existing
`vmBuild` / `vmStart` bindings, and add `wrapper` to the `home.packages`
list. Skip writing `qemu-wrapper.nix` as a separate file. (The split was
shown above for clarity of intent only.)

## Step 2: Update `vm-start` to set `QEMU_SYSTEM_AARCH64`

In `~/etc/modules/private-vm/default.nix`, find the `vmStart` shell
script binding. Near the top of its script (after `set -euo pipefail`
and before any `limactl` invocation), add:

```bash
# Point Lima at our qemu wrapper. Lima looks up qemu via this env var
# (see Lima's pkg/driver/qemu/qemu.go Exe()) before falling back to
# PATH. The wrapper injects -device virtio-balloon-pci,free-page-reporting=on
# so Linux's virtio_balloon driver can return freed pages to the host.
export QEMU_SYSTEM_AARCH64="${wrapper}/bin/qemu-system-aarch64"
```

Where `${wrapper}` refers to the wrapper derivation bound in the `let`
block. The `${...}` is nix interpolation, producing the absolute store
path at build time.

## Step 3: Switch `vmType` in `lima.yaml`

Edit `~/etc/hosts/private-vm/lima.yaml`. Change:

```yaml
vmType: vz
```

to:

```yaml
vmType: qemu
```

Do NOT change anything else. In particular, do not adjust:
- `memory:` (leave at whatever it currently is — likely "8GiB")
- `cpus:`
- `disk:`
- `additionalDisks:` (Lima's qemu driver supports named disks the same
  way as vz)
- `plain: true`
- `images:`
- `ssh.localPort: 60022`
- `user:`

## Step 4: Apply changes

```
nix-rebuild
```

This should produce no errors. If it does, fix them before proceeding.

## Step 5: Restart the VM under qemu

The current VM instance was started under vz; we need to stop it and
start fresh under qemu. The named disks (private-home, private-nix,
private-persistence) and the root disk (a sparse 40GiB qcow2 holding
~2.6 GiB of actual data) all persist across this — Lima associates them
with the instance name, not the vmType.

```
vm stop
```

Expected output: clean shutdown via `limactl stop private-vm`. If it
hangs, ctrl-C and use `limactl stop --force private-vm` from `$LIMA_HOME`.

Now start under qemu:

```
vm start
```

Expected behavior:
- Lima reads the updated `lima.yaml`, sees `vmType: qemu`, invokes our
  wrapper as qemu.
- Wrapper detects the `virt` machine argument, appends the balloon
  device, execs real qemu.
- VM boots (cold-start under qemu takes ~15–25s vs ~10–15s under vz).
- `vm start` waits for SSH on port 60022 and returns when reachable.

If `vm start` reports the VM did not become SSH-reachable in 90 s, give
it a second attempt (cold-start under qemu can be slower than the
heuristic):

```
sleep 30
vm start
```

If it still fails, see "Troubleshooting" below.

### What to ignore in this phase

**RDP behavior is explicitly out-of-scope for Phase 1.** Do not test
RDP, do not investigate RDP errors, do not adjust xrdp config. If
`vm rdp` is broken under qemu, that's fine — Phase 2 retires RDP
entirely. Phase 1's success criteria are SSH reachability and memory
reclaim, nothing else.

## Step 6: Verification

### 6a. Confirm qemu is running, vz is not

```
ps aux | grep -E "qemu-system-aarch64|com.apple.Virtualization" | grep -v grep | grep -v linux-builder
```

Expected: one `qemu-system-aarch64` process matching the private-vm
(distinguishable from linux-builder's qemu by working directory or
`-name nixos` arg — linux-builder uses `-name nixos`; ours should not).
No `com.apple.Virtualization.VirtualMachine` process for private-vm.

### 6b. Confirm the balloon device was actually attached

```
vm ssh "lspci | grep -i balloon"
```

Expected: a line like
`00:0X.0 Unclassified device [00ff]: Red Hat, Inc. Virtio memory balloon`.

If this line is absent, the wrapper didn't run or didn't inject the
device — debug by checking `ps aux | grep qemu-system` on the host and
inspecting the actual argv passed to qemu (look for
`virtio-balloon-pci` in the cmdline).

### 6c. Confirm FPR feature negotiated

```
vm ssh "dmesg | grep -i 'virtio_balloon\|free page'"
```

Expected: lines indicating virtio_balloon initialized, ideally
mentioning `free page reporting` or feature flag `0x6` (the FPR bit).
If virtio_balloon loaded but FPR not negotiated, qemu may not have
advertised the feature — verify the wrapper's argv includes
`free-page-reporting=on` not `free_page_reporting=on` (hyphen vs
underscore — qemu wants hyphen).

### 6d. The reclaim test (the whole point)

**macOS caveat — read first.** On Linux, qemu's free-page-reporting handler
unmaps freed pages via `madvise(MADV_DONTNEED)` and host RSS drops
immediately. On macOS qemu uses the equivalent `MADV_FREE_REUSABLE`
semantics: freed pages stay attributed to the process's RSS (so `ps -o
rss` does NOT decrease after `drop_caches`), but the kernel can reclaim
them instantly without swap I/O whenever memory pressure arises. The
pages are accounted as **purgeable** in `vm_stat`. From the host's
perspective those pages are "not really used" — yours until someone
else needs them.

So on macOS the right proof of FPR working is **the low idle baseline**,
not the post-drop_caches delta. Specifically: at vm-start time the guest
reports its huge initial free pool, qemu MADV_FREE's it, those pages
never get faulted in on the host. Idle host RSS settles at a fraction
of the configured ceiling.

Reference numbers (4-CPU aarch64 NixOS image, 8 GiB ceiling):
- vz baseline (before migration, 4 GiB ceiling): host RSS ~4.6 GiB at idle.
- qemu+FPR (8 GiB ceiling): host RSS ~1.25 GiB at idle.

Two-axis improvement: bigger ceiling, much smaller actual footprint.


Record baseline:

```
echo "=== BEFORE allocation ==="
vm ssh "grep -E '^(MemFree|MemAvailable|Cached|Buffers|SReclaimable):' /proc/meminfo"
ps -o rss -p $(pgrep -f "qemu-system-aarch64" | xargs -n1 ps -o pid,command -p 2>/dev/null | grep private-vm | awk '{print $1}' | head -1) \
  | awk 'NR==2 {printf "Host RSS: %.0f MB\n", $1/1024}'
```

(If pgrep matches multiple qemu processes — linux-builder's qemu may
also be running — use `pgrep -af qemu-system-aarch64` to identify which
PID is the private-vm one. The private-vm qemu will have a
working-directory or argv containing `private-vm`.)

Force the guest to fill its page cache. The point is to push host RSS up
so we have something to reclaim:

```
vm ssh "dd if=/dev/zero of=/tmp/fill bs=1M count=3000 && sync"
```

Re-record:

```
echo "=== AFTER allocation ==="
vm ssh "grep -E '^(MemFree|MemAvailable|Cached|Buffers|SReclaimable):' /proc/meminfo"
ps -o rss -p <private-vm qemu PID> | awk 'NR==2 {printf "Host RSS: %.0f MB\n", $1/1024}'
```

Expected:
- Guest `Cached` jumps by ~3 GB (the file is cached).
- Host RSS jumps proportionally (~+3 GB).

Now free the cache:

```
vm ssh "rm /tmp/fill && echo 3 | sudo tee /proc/sys/vm/drop_caches"
sleep 5
```

Wait for FPR to report the freed pages and qemu to MADV_DONTNEED them
(typically near-instant, but allow a few seconds for the reporting
queue to drain):

```
echo "=== AFTER drop ==="
vm ssh "grep -E '^(MemFree|MemAvailable|Cached|Buffers|SReclaimable):' /proc/meminfo"
ps -o rss -p <private-vm qemu PID> | awk 'NR==2 {printf "Host RSS: %.0f MB\n", $1/1024}'
top -l 1 | grep PhysMem
```

**Success criterion (macOS)**: idle host RSS sits well below the
configured memory ceiling (target: under 25% of the ceiling at idle on
a freshly-booted VM). `ps -o rss` will NOT drop after `drop_caches`
because of MADV_FREE_REUSABLE semantics — this is expected, not a
failure. Cross-check via `vm_stat | grep purgeable`: those pages are
the ones FPR returned to the host and the OS can reclaim instantly
under pressure.

If idle host RSS is anywhere near the ceiling (say, >50%):
- Verify the balloon device is present (step 6b).
- Verify FPR is negotiated (step 6c).
- Inspect the running qemu argv to confirm
  `virtio-balloon-pci,free-page-reporting=on` made it through the
  wrapper (`ps -ww -o command= -p <pid> | grep balloon`). If it didn't,
  the wrapper's argv heuristic didn't fire — see Troubleshooting.

### 6e. Idle baseline after settling

After all tests, let the VM sit idle for ~2 minutes, then capture the
new baseline:

```
sleep 120
ps -o rss -p <private-vm qemu PID> | awk 'NR==2 {printf "Idle host RSS: %.0f MB\n", $1/1024}'
vm ssh "free -h"
```

Record this number alongside the original vz baseline (~4.6 GB at
4 GiB ceiling). The new idle floor should be substantially lower
relative to the 8 GiB ceiling than the vz idle floor was relative to
its 4 GiB ceiling.

## Troubleshooting

**VM does not boot under qemu.** Lima may complain about state from a
prior vmType. If `~/.local/state/private-vm/lima/private-vm/` contains
`vz-efi`, `vz-identifier`, or `vz.pid`, those are vz-specific state
files. They're harmless but Lima 2.x sometimes refuses to start a qemu
VM in an instance dir that has vz state. If `vm start` fails with a
state-related error:

```
rm -f ~/.local/state/private-vm/lima/private-vm/vz-* ~/.local/state/private-vm/lima/private-vm/vz.pid
vm start
```

Do NOT delete `disk`, `cidata.iso`, `lima.yaml`, `ssh.config`, or any
`.sock` files — those are needed.

**Wrapper not being invoked.** Sanity check the env var path:

```
ls -l "$(vm ssh true; cat /Users/igor.sukhinskii/.local/state/private-vm/lima/private-vm/ha.stdout.log | grep QEMU_SYSTEM 2>/dev/null)"
```

Or more directly: temporarily add `echo "WRAPPER CALLED: $*" >&2` at
the top of the wrapper text in `default.nix`, rebuild, restart, and
check `ha.stderr.log` for the message.

**qemu argv missing `virt`.** The wrapper's heuristic for "this is a
real start, not a probe" is presence of the literal string `virt` in
argv. Confirmed for Lima 2.1.2 (aarch64 always uses `-machine virt`).
If a future Lima version changes the machine type, the wrapper will
silently pass through without injection. Detect this by step 6b
showing no balloon device, then update the heuristic (e.g., look for
`-machine` more carefully).

## Rollback

Reverting Phase 1 is fully local — no host state changes outside the
Lima instance dir:

```
cd ~/etc
git diff hosts/private-vm/lima.yaml modules/private-vm/default.nix
# review the diff
git checkout hosts/private-vm/lima.yaml modules/private-vm/default.nix
nix-rebuild
vm stop
# If the qemu start left vz-incompatible state, clean that too:
# rm -f ~/.local/state/private-vm/lima/private-vm/qemu.pid ~/.local/state/private-vm/lima/private-vm/qmp.sock
vm start
```

VM disks survive intact. The same root qcow2 boots under either vmType
(it's the upstream `qemu-efi` image).

## What this does NOT do (and why)

- **Does not change memory ceiling.** Currently 8 GiB per `lima.yaml`.
  Phase 1's purpose is to make that ceiling cheap to keep high; the
  ceiling itself was set in an earlier session.
- **Does not enable GPU acceleration / virgl.** Requires a custom qemu
  build (`pkgs.qemu.override { virglSupport = true; ... }`) and is
  Phase 2.
- **Does not change the guest's `virtio_balloon` kernel module load.**
  Already added to `full.nix` in an earlier session as guest-side prep.
  Phase 1 just activates the host-side device to match.
- **Does not retire RDP / xrdp / openbox.** Phase 2 work.
- **Does not remove the `private-vm-drop-caches` systemd timer in
  `full.nix`.** Still useful under qemu+FPR — FPR only returns
  guest-free pages, not page cache, so something has to force the
  guest to reclaim cache periodically. The comment in `full.nix` is
  updated to explain the timer's role under the new model.

## Definition of done for Phase 1

All of:

- [ ] `nix-rebuild` succeeds after the changes.
- [ ] `vm start` brings up the VM under qemu (verified via step 6a).
- [ ] `vm ssh` works.
- [ ] Balloon device is present in guest (`lspci | grep balloon`).
- [ ] FPR is negotiated (dmesg check, step 6c).
- [ ] Step 6d's macOS success criterion holds: idle host RSS sits well
      below the configured memory ceiling (<25% on a fresh boot).
      `vm_stat | grep purgeable` reports a non-trivial pool — those are
      the FPR-reported pages the OS can reclaim under pressure.
- [ ] Idle host RSS (step 6e) is recorded for reference.

Once all checked: commit the three changed files
(`hosts/private-vm/lima.yaml`, `modules/private-vm/default.nix`) as a
single commit titled along the lines of:
`feat(private-vm): switch to qemu with FPR balloon for host memory reclaim`.

Phase 2 will be planned in a separate document once Phase 1 has run for
long enough to surface any operational issues.

## Phase 3 (deferred): rethink the impermanence story

Phase 1 surfaced a coupling that's worth capturing now so we don't lose
sight of it later. The current architecture is not classical NixOS
impermanence — it's "rootfs is durably mutable but discardably mutable":
rootfs lives long in normal operation, can be wiped as a recovery op.
/nix is external (private-nix) so bootstrap-image rebuilds stay cheap.

The coupling: **/boot lives on rootfs, but boot entries point at
closures on /nix (private-nix).** Either side wiped without the other
breaks cold boot:

- Wipe rootfs → lose /boot → gen 1 (re-baked into fresh bootstrap)
  still boots; gens 2..N entries gone until `vm rebuild` regenerates
  them against the existing /nix closures.
- Wipe private-nix → /boot entries point at non-existent closures →
  emergency mode for everything except gen 1.

For this to work cleanly at all, the initrd must mount /nix in stage-1,
i.e. `fileSystems."/nix" = { … neededForBoot = true; }` in full.nix.
This is the Phase 1 fix that unblocks cold boots. Without it, the live
`nixos-rebuild switch` path masks the bug: gens 2..N are user-space
activations and never actually cold-boot until something forces a stop
(vmType switch, host reboot under wrong conditions, crash). Phase 1
made this observable for the first time.

With that fix in place the design works, but it's asymmetric: rootfs
durability and /nix durability are different tiers, and the user has
to remember "wipe rootfs is fine, recovery is `vm rebuild`."

A classical-impermanence rework would make rootfs *always* ephemeral
(tmpfs, or snapshot-wiped each boot) and put /boot on a durable tier
(/persistence or private-nix). Then "rootfs discard inexpensive and
lossless" becomes a per-boot invariant, not a recovery operation.
Things to think through in Phase 3:

- Move /boot off rootfs. Candidates: /persistence (smaller, fits the
  "config + state" role), or private-nix (already durable, but mixing
  /boot with /nix in one volume conflates lifecycles).
- Rootfs as tmpfs vs snapshot-revert vs current "durable but
  discardable." Trade-offs: tmpfs needs explicit bind-mount lists for
  things that survive; snapshot-revert needs a base snapshot mechanism
  Lima doesn't natively provide; status quo needs the user to remember
  recovery is `vm rebuild`.
- /var/lib/private-vm/ (passwd hash, lima pubkey, user pubkey) is
  currently re-pushed by `vm rebuild` — good, already aligned with
  "rootfs is discardable." Anything else on rootfs that isn't?
- Re-evaluate the `private-vm-drop-caches` systemd timer. It's NOT
  redundant under qemu+FPR (FPR only reports buddy-allocator-free
  pages; page cache pages don't qualify until something forces the
  guest to reclaim them — drop_caches is what does that, converting
  cache → free → FPR-reported → MADV_FREE on the host). Question for
  Phase 3 is whether to keep the 15-min cadence, tune it under
  observed pressure patterns, or replace with a pressure-driven
  trigger (e.g. only drop when host PSI-equivalent indicates demand).
- Retire xrdp/openbox if Phase 2 ships native GL.

Defer until Phase 1+2 have run long enough to know what we actually
want from the impermanence model.
