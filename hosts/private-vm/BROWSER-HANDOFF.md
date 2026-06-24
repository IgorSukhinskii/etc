# private-vm GUI — browser bring-up handoff (fresh-session deliverable)

Status: **the transport/black bug is FIXED** (see `WAYLAND-GUI.md` §0 — cocoa-way
wl_shm buffer-offset bug; `foot` renders end-to-end). This doc is the
self-contained plan to get a **guest browser (target: `zen-beta`)** rendering on
the host. Written for a fresh session — assume no prior context beyond this file
and `WAYLAND-GUI.md`.

Date: 2026-06-24. Host: Apple M4 Pro, macOS 26.5.1 (25F80).

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

## 2. The browser problem (what to fix)
`vm gui firefox` / `vm gui zen-beta` do **not** show content. Two layered
symptoms observed:
- **Primary (reproduced, consistent): Gecko Wayland Proxy fails before any
  window.** Firefox/zen connect to cocoa-way through waypipe (cocoa-way logs ~4
  "New client connected" — Gecko is multiprocess) but create **0 xdg_toplevels /
  0 buffers**, then exit with:
  ```
  [NNN] Wayland Proxy [0x..] Error: CheckWaylandDisplay(): Failed to connect to
        Wayland display '/run/user/1001/wayland-<random>' : No such file or directory
  Error: we don't have any display, WAYLAND_DISPLAY='wayland-<random>' DISPLAY='(null)'
  ```
  The `wayland-<random>` is Gecko's *own* proxy socket, which never gets created.
  `MOZ_DISABLE_WAYLAND_PROXY=1` did **not** suppress it in testing. Errors vary
  run-to-run (sometimes `no DISPLAY`) → there's also an env/timing component.
- **Secondary (seen earlier, not currently reproducible): black window.** On a
  run where the proxy DID come up, the window rendered black — likely dmabuf/EGL
  (cocoa-way has **no** `zwp_linux_dmabuf`, only wl_shm) or scaling. Chase only
  after the proxy issue is resolved.

This is a **client-toolkit problem layered on a working pipeline**, NOT a
cocoa-way render bug.

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
