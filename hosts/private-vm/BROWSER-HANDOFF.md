# private-vm GUI — browser bring-up handoff (fresh-session deliverable)

Status: **Zen/Gecko now renders through waypipe** with the locally built
`~/projects/cocoa-way` binary. Two cocoa-way fixes are required: wl_shm buffer
offset handling (all apps) and ARGB alpha/blending (Gecko's transparent wrapper
surface). The VM wrapper also keeps Gecko under waypipe with `--no-remote
--new-instance --profile`.

Date: 2026-06-24. Host: Apple M4 Pro, macOS 26.5.1 (25F80).

## 0. 2026-06-24 update — Gecko renders
Root causes found:
- Zen's normal/default profile launch could return from the process that waypipe
  tracks while Gecko child processes continued. waypipe then cleaned up its
  guest `WAYLAND_DISPLAY` socket; Gecko's Wayland proxy later ran
  `CheckWaylandDisplay()` and failed with `No such file or directory`.
- After that was fixed, Gecko still looked black because cocoa-way forced every
  ARGB8888 wl_shm buffer opaque and used a non-blending Metal blit pipeline.
  Gecko commits a larger transparent ARGB shell/decor surface after its actual
  1600x1200 content surface; forcing alpha made that transparent surface an
  opaque black cover.

Fix in `modules/private-vm/default.nix`:
- `vm gui zen` / `vm gui zen-beta` now add
  `--no-remote --new-instance --profile /home/igor/.config/zen/default` when no
  explicit profile is supplied.
- `vm gui-reset` now also reaps orphaned Zen/Firefox processes and removes the
  stale Zen `.parentlock`.

Fix in `~/projects/cocoa-way`:
- `src/render.rs` now forces alpha only for XRGB8888; ARGB8888 preserves client
  alpha.
- `src/metal_renderer.rs` enables blending for the texture blit pipeline.

Validation:
- waypipe stayed alive after 22s;
- cocoa-way saw 4 clients, 1 XDG toplevel, and steady ARGB8888 wl_shm buffers;
- no `Wayland Proxy` / `we don't have any display` error appeared.
- instrumentation showed the Gecko content surface has non-black opaque pixels
  and the larger wrapper surface is transparent once ARGB alpha is preserved.
- the corrected `vm gui-reset` leaves no guest browser/waypipe processes,
  `wayland-*` sockets, or Zen `.parentlock`.

---

## 1. What already works / is in place
- **Offset fix** committed at `~/projects/cocoa-way` (branch `macos-repro-harness`,
  commit `222cf440`), pushed to fork `IgorSukhinskii/cocoa-way` (remote `fork`;
  `upstream` = `J-x-Z/cocoa-way`). Built binary:
  `${CARGO_TARGET_DIR:-~/.cache/cargo-target}/release/cocoa-way` (4.4 MB).
- **`vm gui` uses that patched binary** (interim; `modules/private-vm/default.nix`
  `vmGui`: `COCOA_WAY_BIN` override, else local build, else brew fallback). See
  `WAYLAND-GUI.md` §8 for the durable nix-package follow-up (not yet done).
- **`vm gui-reset`** added: hard-resets the GUI stack (host waypipe+cocoa-way,
  ssh master, guest waypipe+sockets) when things wedge. `vmGui` also
  health-checks the ssh control master and resets it if stale.
- **`foot` renders correctly** through `vm gui foot`. Pipeline is proven good.

## 2. Browser status
`vm gui zen-beta` is expected to render when the local fixed cocoa-way binary has
been built at `${CARGO_TARGET_DIR:-~/.cache/cargo-target}/release/cocoa-way`.
If it regresses:
- `Wayland Proxy` / `we don't have any display` means the waypipe-tracked Gecko
  process exited early; check the `--no-remote --new-instance --profile` wrapper
  path and stale profile locks.
- A black window with steady `get_buffer_pixels: Argb8888` logs means cocoa-way
  is not the fixed build, or the ARGB alpha/blending patch regressed.

## 3. Test matrix (engine/toolkit coverage)
_(harness `/tmp/gui-matrix.sh`; logs `/tmp/mx-cw-*.log`, `/tmp/mx-app-*.log`. Run 2026-06-24.)_

| App | Engine/type | clients | toplevels | buffers | result |
|---|---|---|---|---|---|
| `foot` | raw wl_shm | 1 | 1 | 27 | **RENDERS ✓** (Argb8888 1593×1196, offset 128 MiB honored) |
| `zen-beta` | Gecko | 4 | **0** | 0 | connects, then **Gecko Wayland Proxy fails**: `CheckWaylandDisplay(): Failed to connect to '/run/user/1001/wayland-<random>' : No such file` → "we don't have any display" |
| `chromium` (no flag) | Blink/Ozone | 0 | 0 | 0 | **fell back to X11** (`ozone_platform_x11.cc: Missing X server`) — `NIXOS_OZONE_WL=1` alone didn't select Wayland here. Inconclusive. |
| `chromium --ozone-platform=wayland --no-sandbox` | Blink/Ozone | 2 | **1** | **15** | **RENDERS ✓** (Argb8888 1632×1242, offset 0). MESA `radv/amdgpu … failed to initialize device` → GPU attempt fails, **falls back to software/wl_shm**; 4 transient dmabuf frames = the 4 "nothing rendered" (cocoa-way has no dmabuf), then steady wl_shm. |

`weston-simple-shm`/`weston-simple-egl`/`gtk4-demo` rows in `/tmp/gui-matrix.out`
are invalid (those binaries aren't shipped under those nixpkgs attrs — "No such
file or directory", not a pipeline result). A valid GTK-app row is still wanted
(e.g. `nix run nixpkgs#gnome-calculator`) — see step 1.

**Conclusion: the pipeline handles a full browser — the blocker is Gecko-specific.**
- **Chromium/Blink works** (with `--ozone-platform=wayland`; `--no-sandbox` used in
  test). So a Chromium-family browser (brave/chromium) is a **viable browser TODAY**,
  and it confirms the offset fix + pipeline are sound for real apps.
- **Gecko (zen/firefox) is the one failing**, at its **Wayland Proxy** (can't reach
  the display socket), before any window. That — not the pipeline — is the target.
- cocoa-way has **no dmabuf**, so GPU-accelerated paths fail and apps must fall to
  software/wl_shm. Chromium does this automatically (a few black frames during the
  transition). For zen, force software rendering (`modules/zen.nix` already does).

Columns: clients connected · toplevels created · buffer reads · dmabuf-format
warnings · "nothing rendered" warnings · first buffer format seen.

Interpretation key:
- **toplevels>0 + buffers>0 + nothing_rendered≈1** → renders fine (like foot).
- **clients>0 + toplevels=0** → connects but never makes a window (Gecko-proxy
  class failure).
- **dmabuf_warn>0 / unsupported** → app uses dmabuf/EGL → black (cocoa-way has no
  dmabuf); must force software/wl_shm.

## 4. Concrete next steps (fresh session)
The chromium-vs-Gecko branch is **already resolved**: Chromium renders, so the
pipeline is fine and the work is **narrowly the Gecko Wayland Proxy**.

0. **(Optional immediate win)** Confirm a Chromium browser as a usable option:
   `vm gui` runs the app verbatim, so `vm gui chromium --ozone-platform=wayland`
   (or package `brave`) should render today. Decide whether to (a) ship a Chromium
   browser in the guest as the daily driver, and/or (b) keep pushing on zen.
1. **Gecko Wayland Proxy is the bug.** The proxy sets `WAYLAND_DISPLAY=wayland-<rand>`
   and then "Failed to connect to '/run/user/1001/wayland-<rand>' : No such file".
   Capture the **upstream** display waypipe set (before the proxy) with a wrapper:
   `… env … sh -c 'echo "$WAYLAND_DISPLAY" >~/wd.txt; ls -la "$XDG_RUNTIME_DIR" >>~/wd.txt; exec zen-beta'`
   then read `~/wd.txt` via a separate `ssh -o ControlPath=none`. Determine: does
   waypipe's socket exist at `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`? (foot connects, so
   it should) — i.e. is the proxy mis-resolving the path, or racing it?
2. **Try disabling the proxy properly.** `MOZ_DISABLE_WAYLAND_PROXY=1` did NOT work.
   Try a zen/firefox **profile pref** `widget.wayland.use-proxy = false` (user.js in
   the guest profile), relaunch, verify the "Wayland Proxy" line is gone and a
   toplevel appears in `/tmp/cocoa-way.log`. Mozilla src: `widget/gtk/wayland/WaylandProxy.cpp`.
3. **Force software / wl_shm for zen** (cocoa-way has no dmabuf): `modules/zen.nix`
   already sets `gfx.webrender.software=true` + vaapi off — confirm via
   `about:support`. Watch buffers land via `get_buffer_pixels` under
   `RUST_LOG=cocoa_way=debug`. (Chromium needed no prefs — it auto-fell-back.)
4. If the proxy can't be tamed, consider the waypipe angle: the proxy creates its
   own socket in `$XDG_RUNTIME_DIR`; ensure that dir is writable in the non-login
   waypipe exec and there's no name collision with waypipe's socket.

## 5. How to drive things (commands)
- One-shot launch (what `vmGui` does), with debug compositor logging:
  ```sh
  export LIMA_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/private-vm/lima"
  ssh_cfg="$LIMA_HOME/private-vm/ssh.config"; rt="${TMPDIR%/}/cocoa-way"
  tgt="${CARGO_TARGET_DIR:-$HOME/.cache/cargo-target}/release"
  vm gui-reset   # clean slate
  RUST_LOG=cocoa_way=debug "$tgt/cocoa-way" >/tmp/cocoa-way.log 2>&1 &
  until [ -S "$rt/wayland-1" ]; do sleep 0.2; done
  env XDG_RUNTIME_DIR="$rt" WAYLAND_DISPLAY=wayland-1 \
    /opt/homebrew/bin/waypipe --compress=zstd ssh -F "$ssh_cfg" -l igor \
      -o ControlPath="$LIMA_HOME/private-vm/ssh-igor.sock" -o ControlMaster=auto \
      -o ControlPersist=600 -o StreamLocalBindUnlink=yes lima-private-vm \
      env PATH=/etc/profiles/per-user/igor/bin:/home/igor/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin:/bin \
        MOZ_ENABLE_WAYLAND=1 NIXOS_OZONE_WL=1 zen-beta
  ```
- **Cannot screenshot** from the agent (Screen Recording permission not granted);
  rely on `/tmp/cocoa-way.log` (toplevels / `get_buffer_pixels` / "nothing
  rendered") + the app's stderr, and have the user eyeball the window.
- `vm gui-reset` between attempts; a plain non-multiplexed guest shell is
  `ssh -F "$ssh_cfg" -l igor -o ControlPath=none lima-private-vm '<cmd>'`.

## 6. Out of scope here (separate follow-ups, see WAYLAND-GUI.md)
- **HiDPI/Retina scaling** (foot renders tiny): cocoa-way advertises a fixed
  output + integer scale, not tracking the Retina backing scale. **Separate
  cocoa-way PR candidate** (§7a). Independent of the browser issue.
- **Nix-from-source cocoa-way package** to replace the brew/local-build interim
  (§8).
- Decorations off, audio.
