# private-vm GUI — cocoa-way + waypipe (Wayland), handover

Status: **ROOT-CAUSED & FIXED (2026-06-24).** It was **NOT** a waypipe-darwin
transport bug. The general black-window bug was cocoa-way reading wl_shm buffers
from the pool base instead of `BufferData.offset`; Gecko also needed cocoa-way to
preserve ARGB alpha and use a blending blit pipeline. Both fixes are implemented
and verified in the source clone at `~/projects/cocoa-way`. See §3 for the
corrected diagnosis; the original "transport bug" reasoning below it is
preserved but was **wrong**.

Date of handover: 2026-06-24. Host: Apple **M4 Pro**, **macOS 26.5.1 (25F80)**.

---

## 0. RESOLUTION (read this first)

**Root cause:** cocoa-way's `src/render.rs::get_buffer_pixels` read wl_shm pixels
from the **start of the pool**, ignoring `BufferData.offset` (the buffer's byte
offset within the pool). smithay's `with_buffer_contents` hands back a pointer to
the *pool* base plus `data.offset`; the offset MUST be applied. Simple clients
(and the `render-test` harness) put their buffer at offset 0, so they rendered
fine — which is exactly what made this masquerade as a transport bug. Real apps
(foot, Firefox/zen, anything on wlroots' shm allocator) sub-allocate many buffers
from one large pool: foot used a **512 MiB pool with the buffer at a 128 MiB
offset**. cocoa-way then read the zero-filled region *before* the pixels → a
fully black (all-zero) buffer.

**Why the original handover blamed waypipe:** the buffer DID arrive over waypipe
as a live `NewBuffer`, `get_buffer_pixels` WAS called, and it read all-zero
content — which looks like "the transport delivered an empty buffer". It didn't;
cocoa-way was reading the wrong slice of a correctly-delivered pool.

**The first fix** (in `~/projects/cocoa-way/src/render.rs`, inside
`get_buffer_pixels`):
apply `data.offset` before building the pixel slice —
`from_raw_parts(ptr.add(offset), len - offset)` (with an `offset >= len` guard).
One self-contained change; popups benefit too since they share the same reader.

**The Gecko fix:** preserve alpha for ARGB8888 buffers, force alpha only for
XRGB8888, and enable blending for cocoa-way's Metal texture blit pipeline.
Without this, Gecko's transparent shell/decor surface is drawn as an opaque black
surface over the actual browser content.

**The scaling fix:** cocoa-way advertised HiDPI support but started in its
unchecked "Normal 1x" mode. On Retina that made clients see the 1600x1200 backing
surface as 1600x1200 logical pixels, so browser UI appeared tiny inside an
800x600 point macOS window. The local build now starts with the window's macOS
scale factor, keeps the menu item checked, and advertises 1600x1200 physical /
scale 2 / 800x600 logical to Wayland clients.

**The Gecko overlay fix:** cocoa-way ignored toplevel
`xdg_surface.set_window_geometry`. Gecko uses a larger transparent root surface
for margins/shadows around the real window geometry; drawing that root at the
tile origin made the transparent decoration rectangle appear offset over the
left sidebar. The local build now crops the root toplevel buffer to the xdg
window geometry and draws the cropped pixels at the tile origin, keeping pixels
and pointer coordinates aligned.

**The popup scaling fix (2026-06-24):** the toplevel render path honours
`wp_viewporter`'s destination size (`viewport_dst.w * scale`), but the popup
render path in `main.rs` did **not** — it always used
`tex_w / buffer_scale * scale`. Gecko/zen scales via
`wp_fractional_scale_manager_v1` + `wp_viewporter` (both advertised by cocoa-way),
keeping `buffer_scale = 1` and putting the real logical size in the viewport
destination. So a popup (e.g. zen's extensions/settings panel) was drawn at
`full_physical_buffer_px × scale` ≈ **2× oversized** on Retina while the toplevel
was correct. Fix: the popup loop now reads `ViewportCachedState.dst` and prefers
it exactly like the toplevel path. Built at
`~/.cache/cargo-target/release/cocoa-way`; `vm gui` already prefers that local
build.

**Known remaining browser gap:** Chromium/Ozone is still not correct after the
Zen fixes. It renders, but content does not conform to the Cocoa-Way window, a
small background/root surface appears behind the main one, and pointer
coordinates are badly offset. Since Zen works and Chromium fails differently, do
not treat this as part of the Zen bring-up. Future Chromium work should focus on
Ozone's xdg geometry / viewport / HiDPI interaction with Cocoa-Way.

**Verified** (instrumentation since reverted; clean diff is just the fix):
| Scenario | Before fix | After fix |
|---|---|---|
| `render-test` (native, offset 0) | red ✓ | red ✓ |
| `render-test-offset` (native, 512MiB pool / 128MiB offset) | **black (0% non-zero)** | **red (100%)** |
| waypipe → `foot` | **black (0% non-zero)** | **renders; center pixel = foot bg #242424** |

`test-client/src/bin/render-test-offset.rs` (new) is the standalone regression
repro: it reproduces the black window with **no waypipe at all**, proving the bug
is cocoa-way-side.

---

## 1. Goal & why this approach

We want to launch a **guest GUI app (primarily the zen browser)** in the Lima
NixOS VM and see it as a **native macOS window** on the host. The old approach
(xpra) is dead: it broke on macOS Tahoe (GTK3's Cocoa menu integration mutates
NSMenu off the main thread → `NSInternalInconsistencyException`).

### Selection criteria (from the original request)
1. Clean text rendering (no blur)
2. Good mac screen scaling (HiDPI/Retina)
3. One host window = one guest window
4. Closing host window = closing guest window
5. No guest window decorations / traffic lights
6. Wayland compatibility
7. GPU compatibility (when rutabaga lands upstream)
8. No persistent open VM window (headless)
9. CLI ergonomics (one command opens a host window)

Hard requirement: **launch guest browser, see it on host.**

### Why cocoa-way (research conclusion)
Remote-display tools split into (a) **buffer/protocol transports** (ssh -X,
xpra, **waypipe**, wprs) that need a host-side compositor to turn surfaces into
native windows, and (b) **whole-desktop pixel streamers** (VNC, RDP,
Sunshine/Moonlight) which are structurally wrong for per-window seamlessness.

On macOS the missing piece was always a **native Wayland→Cocoa compositor**.
That changed in 2026 with **cocoa-way** (https://github.com/J-x-Z/cocoa-way) — a
native macOS Wayland compositor written in Rust (Smithay) that renders each
guest Wayland toplevel as its own **Metal-backed NSWindow**, fed by
**waypipe-darwin** (https://github.com/J-x-Z/waypipe-darwin, a macOS-patched
waypipe). It is the only option that natively satisfies the headline goal and
fixes xpra's two big gaps (crisp text, Wayland). Alternatives (wprs, weston-RDP,
Sunshine) either still need cocoa-way underneath or are whole-desktop. Both
cocoa-way and waypipe-darwin are by the **same single developer (J-x-Z)** and
are early/experimental — maturity was the known risk, now realized.

### The pipeline
```
guest Wayland app  →  waypipe server (guest, NixOS)  →  SSH  →
waypipe-darwin client (mac)  →  cocoa-way compositor  →  native NSWindow (Metal)
```
`waypipe` IS the compositor from the app's POV — **no guest-side compositor /
Xserver is needed.** cocoa-way does the real compositing on the Mac.

---

## 2. What was implemented (committed in this repo)

All in the commit that adds this file. Migration xpra → cocoa-way+waypipe:

- **`modules/private-vm/default.nix`**
  - `darwinModules.private-vm`: dropped the `xpra` cask; added `homebrew.taps =
    [{ name = "j-x-z/tap"; trusted = true; }]` and `homebrew.brews` now has
    `cocoa-way` + `waypipe-darwin` (+ existing `age-plugin-se`).
    - `trusted = true` is required because **Homebrew 6.0** refuses non-official
      taps unless trusted; the nix-darwin tap `trusted` option emits
      `tap "...", trusted: true` in the Brewfile. **This needed a nix-darwin
      bump** (flake.lock: nix-darwin → 2026-06-18) — the option is post-2026-06.
  - `vmGui` (`vm gui [app]`) fully rewritten: starts cocoa-way once (background,
    reused; logs `/tmp/cocoa-way.log`), finds its socket at
    `$TMPDIR/cocoa-way/wayland-1` (clears stale socket on relaunch to avoid an
    ECONNREFUSED race), then `exec waypipe --compress=zstd ssh <args>
    lima-private-vm env PATH=… MOZ_ENABLE_WAYLAND=1 NIXOS_OZONE_WL=1 <app>`.
    - The `env PATH=…` is essential: waypipe execs the app in a **non-login SSH
      session** whose PATH lacks the home-manager per-user profile. zen lives at
      `/etc/profiles/per-user/igor/bin` (useUserPackages). Without the explicit
      PATH, `vm gui zen` fails with "No such file or directory".
    - The **zen binary is `zen-beta`**, not `zen`. `vm gui` defaults to
      `firefox` (a debug browser) when no arg is given.

- **`hosts/private-vm/full.nix`**
  - systemPackages: dropped `xpra`; added `waypipe`, plus debug tools `foot`
    (minimal SHM client) and `wayland-utils` (`wayland-info`). `firefox` kept as
    a debug browser (zen is the real target, installed via the `browser` HM
    profile).
  - Added `environment.sessionVariables = { MOZ_ENABLE_WAYLAND=1;
    NIXOS_OZONE_WL=1; }`.
  - Removed the entire headless-xpra systemd user unit + xauth seeding +
    `DISPLAY=:100`.
  - pipewire kept but **inert** for host audio (waypipe carries no audio).

- **`modules/zen.nix`** (`!isDarwin` branch): `gfx.webrender.software = true` +
  `media.ffmpeg.vaapi.enabled = false`. The guest has no real GPU (software
  llvmpipe) and cocoa-way advertises **no `zwp_linux_dmabuf`** (only wl_shm
  XRGB8888/ARGB8888), so zen must render into wl_shm, not dmabuf. (Correct
  regardless of the transport bug.)

- **`flake.lock`**: nix-darwin `2026-05-17 → 2026-06-18` (only that input).

### Host one-time step (already done, declarative now)
The tap trust is declarative via `trusted = true`. If a fresh machine ever
errors with "Refusing to load formula … untrusted tap", run once:
`/opt/homebrew/bin/brew trust j-x-z/tap`.

---

## 3. Diagnostic journey & the conclusion

Every app over `vm gui` shows a **black window**. We ruled out, in order:

| Hypothesis | Test | Result |
|---|---|---|
| Client/toolkit-specific | `foot`, `firefox`, `zen-beta` | all black |
| GPU/dmabuf buffers | `gfx.webrender.software=true` (wl_shm) | still black; WebRender confirmed compositing frames via `MOZ_LOG` |
| Buffer format | `wayland-info`: cocoa-way offers wl_shm `XR24`/`AR24`, no dmabuf | format is supported |
| waypipe **wire version** skew | guest waypipe **0.11.0** AND pinned upstream **0.10.5** | both black |
| Redraw-only-on-window-event | resize/move the cocoa-way window | still black |
| Fixed in newer cocoa-way | cocoa-way **1.0.1** changelog | no renderer changes (PATH/dylib/container only) |

cocoa-way logs (with `RUST_LOG=cocoa_way=debug`):
`RENDER: N tiles present but nothing rendered — likely unsupported buffer
format or no committed buffer yet` (src/main.rs:594), and **never** the
"unsupported buffer format … not wl_shm" branch (src/main.rs:497).

### THE decisive test (renderer vs transport)
We built cocoa-way from source and wrote a **minimal native macOS wl_shm
client** (`render-test`, see §4) that creates an xdg_toplevel and commits a
solid-red ARGB8888 buffer **directly to cocoa-way, bypassing waypipe entirely**.

Result — cocoa-way log:
```
New client connected
New XDG Toplevel Created
get_buffer_pixels: Argb8888  1600x1200  stride=6400
```
`get_buffer_pixels` (src/render.rs:11) **was called**, no "nothing rendered"
warning → cocoa-way **renders the buffer (red window).**

### Conclusion (SUPERSEDED — see §0)
> ⚠️ The conclusion below was **wrong**. Re-instrumenting cocoa-way's commit
> handler showed the waypipe-forwarded buffer DID arrive as a live `NewBuffer`
> and `get_buffer_pixels` WAS called every frame — it just read **all-zero**
> content. The real cause is cocoa-way ignoring the wl_shm buffer offset (§0).
> The decisive `render-test` only "proved" the renderer worked because it placed
> its buffer at offset 0. `render-test-offset` (same compositor, no waypipe,
> buffer at a 128 MiB offset) reproduces the black window — localizing the bug to
> cocoa-way, not the transport.

~~**cocoa-way's renderer works. The bug is in the waypipe-darwin transport.**~~
~~Through waypipe, the committed buffer never reaches `get_buffer_pixels`~~ — this
turned out to be false; see §0 for what actually happens.

---

## 4. The repro harness (already built)

Cloned at **`~/projects/cocoa-way`** (a clone of upstream + our additions, on a
local branch — see `git log`):

- `flake.nix` — dev shell: `rustc`/`cargo` (1.95, satisfies edition 2024),
  `pkg-config`, `libxkbcommon`, `pixman`. (cocoa-way's `build.rs` only
  pkg-config-probes `xkbcommon` + `pixman-1`; Metal/AppKit come from the SDK.)
- `test-client/src/bin/render-test.rs` — the native wl_shm client above.
- `test-client/src/bin/connect-test.rs` — tiny `UnixStream::connect` probe.
- `test-client/Cargo.toml` — added `wayland-protocols` + `tempfile` deps.

**Build note:** the user's env sets `CARGO_TARGET_DIR=~/.cache/cargo-target`
and `CARGO_HOME=~/.local/share/cargo`, so binaries land in
`~/.cache/cargo-target/release/`, NOT `./target`.

Build + run everything from inside the flake shell:
```sh
cd ~/projects/cocoa-way
nix develop --command cargo build --release            # builds cocoa-way + test-client
```

**Confirm cocoa-way's renderer works (expect a SOLID RED window):**
```sh
tgt="${CARGO_TARGET_DIR:-$HOME/.cache/cargo-target}/release"
rt="${TMPDIR%/}/cocoa-way"
pkill -f cocoa-way; sleep 1; rm -f "$rt/wayland-1"   # avoid stale-socket race
RUST_LOG=cocoa_way=debug "$tgt/cocoa-way" >/tmp/cw.log 2>&1 &
until [ -S "$rt/wayland-1" ]; do sleep 0.2; done; sleep 0.5
env XDG_RUNTIME_DIR="$rt" WAYLAND_DISPLAY=wayland-1 "$tgt/render-test"
# -> red window; /tmp/cw.log shows "get_buffer_pixels: Argb8888 ...".
```
Gotcha: cocoa-way is started fresh by `vm gui` via pgrep; a **stale
`wayland-1` socket** from a Cmd-Q'd instance causes ECONNREFUSED. Always
`rm -f "$rt/wayland-1"` before a fresh manual start. `connect_to_env`
returning `NoCompositor` from a rust wayland client = it hit a stale/dead
socket, not a real failure.

### cocoa-way internals worth knowing (source in ~/projects/cocoa-way/src)
- `render.rs::get_buffer_pixels` — reads a wl_shm buffer via smithay
  `with_buffer_contents`, copies BGRA, forces alpha. **Correct.**
- `main.rs` ~455–604 — the per-tile render loop. For each surface it inspects
  `current.buffer`: `NewBuffer` → cache/`get_buffer_pixels`→`draw_pixels`
  (`rendered_count++`); `None` → `draw_from_cache`; logs `594` if
  `rendered_count == 0`.
- `state.rs` — `CompositorHandler` (commit), `ShmHandler`, `delegate_shm!`,
  advertises wl_shm `Argb8888`/`Xrgb8888`. **This is where to instrument
  commits** (see §5 step 1).

---

## 5. NEXT STEPS — investigate waypipe-darwin (OBSOLETE — bug was in cocoa-way)

> ⚠️ This whole section chased the wrong layer. The bug was cocoa-way ignoring
> the wl_shm buffer offset (§0), already fixed. Kept only for the repro recipe in
> Step 2 (the manual `waypipe … ssh … foot` command), which is still the way to
> drive a controllable waypipe client by hand. Ignore Steps 3–4.

Goal: find why a buffer committed through waypipe-darwin doesn't become a live
`NewBuffer` in cocoa-way, then fix it (PR to waypipe-darwin if needed). The
same dev owns both repos, so a cocoa-way-side fix is also acceptable.

### Step 0 — reconfirm the split is still true
Run the §4 red-window test. If red → renderer still fine, proceed.

### Step 1 — pinpoint WHICH side drops the buffer (fastest, ~30 min)
We have cocoa-way source + build. **Instrument cocoa-way's commit handler** to
log every surface commit and whether a buffer was attached, then reproduce via
waypipe and read the log.

- In `~/projects/cocoa-way/src/state.rs`, find `impl CompositorHandler … fn
  commit(&mut self, surface)` and add a `log::info!` dumping the surface id and
  the `BufferAssignment` (NewBuffer/Removed/None) pulled from
  `cached_state.get::<SurfaceAttributes>().current().buffer`. (Mirror how
  main.rs reads it.)
- Rebuild: `nix develop --command cargo build --release`.
- Run that locally-built cocoa-way as the `vm gui` compositor. Either:
  - temporarily point `vm gui` at it (edit `cocoa_way=` in the `vmGui` script —
    rebuild host with `nix-rebuild`), **or** simpler: start the built cocoa-way
    manually (as in §4) and run the waypipe client by hand (Step 2 command).
- `vm gui foot` (or the Step 2 manual command) and read the log:
  - **NewBuffer IS logged for the content surface** but render still sees None →
    bug is **cocoa-way commit/render state timing** (e.g. a later
    buffer-less commit clears `current.buffer`; the initial NewBuffer frame
    isn't rendered/cached). Fix likely in cocoa-way main.rs/state.rs.
  - **NewBuffer is NEVER logged** (only buffer-less commits / no attach) → bug
    is **waypipe-darwin** not replaying attach/commit (or its SHM pool) to
    cocoa-way. Go to Step 3.

### Step 2 — reproduce the black with a controllable waypipe client
`vm gui` uses `/opt/homebrew/bin/waypipe` (waypipe-darwin 0.10.6). To get debug
logging and use a local build, run the client by hand against a running
cocoa-way (replicates what `vmGui` execs):
```sh
rt="${TMPDIR%/}/cocoa-way"
export LIMA_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/private-vm/lima"
ssh_cfg="$LIMA_HOME/private-vm/ssh.config"
~/etc-private-vm-helpers... # or just: vm start  (ensure VM up)
env XDG_RUNTIME_DIR="$rt" WAYLAND_DISPLAY=wayland-1 \
  /opt/homebrew/bin/waypipe --debug --compress=zstd ssh \
    -F "$ssh_cfg" -l igor \
    -o ControlPath="$LIMA_HOME/private-vm/ssh-igor.sock" \
    -o ControlMaster=auto -o ControlPersist=600 -o StreamLocalBindUnlink=yes \
    lima-private-vm \
    env PATH=/etc/profiles/per-user/igor/bin:/run/current-system/sw/bin:/usr/bin:/bin \
      foot
```
`--debug` (or `-d`) makes waypipe log its object/buffer tracking. The guest
side (`waypipe server`, nixpkgs 0.11.0) is auto-spawned by `waypipe ssh`. Note:
the guest-side "degenerate damage rectangle" ERRs are waypipe rejecting
zero-area damage from `foot` — a red herring (zen sends proper damage and is
also black).

### Step 3 — dig into waypipe-darwin source
```sh
git clone https://github.com/J-x-Z/waypipe-darwin.git ~/projects/waypipe-darwin
```
It's Rust (Cargo `version = 0.10.6`), built with meson+cargo like upstream
waypipe. Write a `flake.nix` dev shell (model on `~/projects/cocoa-way/flake.nix`
+ upstream nixpkgs `waypipe` build inputs: `meson ninja pkg-config cargo rustc
lz4 zstd` and optionally `ffmpeg vulkan-loader shaderc rust-bindgen`).

Prime suspects (the fork's stated patches): **"replaced `memfd_create` with
temporary file-based SHM for Darwin"** and "unnamed socket handling". The
**client side** (mac) creates the wl_shm pool/buffer on cocoa-way from a
tempfile fd. Look at:
- how the client creates the `wl_shm_pool` + `wl_buffer` and issues
  `attach`/`damage`/`commit` to the downstream (cocoa-way) compositor;
- whether the tempfile-backed pool is sized/mmapped/synced such that the buffer
  is valid at the moment `commit` is replayed;
- attach/commit **ordering** vs frame callbacks (could be committing before the
  buffer content is ready, or a buffer-less commit landing last).

Compare the client's emitted sequence against what our `render-test` does
(attach → damage → commit, once), which cocoa-way renders fine.

### Step 4 — fix & validate
Patch waypipe-darwin (or cocoa-way per Step 1), rebuild, rerun Step 2 with
`foot` → expect a rendered terminal, then `vm gui zen-beta`. If fixing
waypipe-darwin, build a bottle or point `vm gui`'s `waypipe=` at the local
build; upstream a PR to J-x-Z/waypipe-darwin.

### If we file instead of fix
Issue is essentially written in §3. File at **J-x-Z/waypipe-darwin** (or
cocoa-way), include the `render-test` harness as the repro, and the key line:
*cocoa-way renders direct native wl_shm clients (`get_buffer_pixels: Argb8888`)
but every waypipe-darwin-forwarded client is black ("tiles present but nothing
rendered") — buffers don't land as a live NewBuffer.* Tested guest waypipe
0.11.0 and 0.10.5; macOS 26.5 / M4 Pro; cocoa-way 1.0.0.

---

## 6. Versions / facts (pin these in any bug report)
- macOS 26.5.1 (25F80), Apple M4 Pro.
- cocoa-way: brew **1.0.0** (upstream tag 1.0.1 exists, no render changes).
- waypipe-darwin: brew, binary reports **`waypipe 0.10.6`** (fork's own version;
  there is **no upstream `v0.10.6` tag** — upstream goes 0.10.0..0.10.5, 0.10.7,
  0.11.0).
- guest waypipe: nixpkgs **0.11.0** (tested), also pinned **0.10.5** (tested).
- cocoa-way globals (`wayland-info`): wl_compositor v5, xdg_wm_base v6, wl_shm
  (XR24/AR24 only, **no dmabuf**), wp_viewporter, wp_fractional_scale_manager_v1,
  zxdg_decoration_manager_v1, seat, etc.

## 7. Loose ends

### 7a-bis. zen extensions / policies not applying (2026-06-24, root-caused + fixed)
After zen rendered, the user's **extensions never installed and locked prefs
never applied**, while profile-level config (userChrome, user.js, search) DID
land. `about:policies` (captured headlessly via
`zen-beta --headless --screenshot about:policies`) said: **"The Enterprise
Policies service is inactive."**

Root cause: the zen package on PATH (`…r065…-zen-beta`) ships the populated
`distribution/policies.json` (with `ExtensionSettings`, locked `Preferences`,
etc.) **only in its *wrapped* tree**. Its launcher execs the **unwrapped** binary
(`…-zen-beta-bin-unwrapped/lib/zen-bin-*/zen`), and Gecko resolves its GRE via
`/proc/self/exe` into that unwrapped store path — whose
`distribution/policies.json` is **`{"policies":{}}`**. So Gecko reads the empty
one; policies never activate (no force_installed extensions, no locked prefs).

The zen-browser flake DOES bake policies into the *unwrapped* tree
(`package.nix:111-112`, `${name}-unwrapped.override { policies = … }`) when the
package is built via the HM module's own default. But `modules/zen.nix` was
overriding `programs.zen-browser.package` with the stock
`inputs.zen-browser.packages.${system}.default`, whose unwrapped tree carries no
user policies. **Fix (committed): on Linux leave `package` unset
(`lib.mkIf isDarwin null`)** so the HM module builds its policy-baked default.
Verify after `vm rebuild`: `about:policies` → Active, and `force_installed`
uBlock/tridactyl appear (AMO is reachable from the guest — confirmed HTTP 302 to
the signed XPI). Note this build stores its profile at `~/.config/zen/`
(XDG), **not** `~/.zen/`.

### 7a. Post-offset-fix findings (2026-06-24) — what works, what doesn't
After the offset fix, **`foot` renders correctly through the full `vm gui`
pipeline** (the transport+render path is proven good). Three *separate* issues
remain, none of them the offset bug:

- **Browser bring-up: Chromium works, Gecko (zen/firefox) doesn't.** A test
  matrix (2026-06-24; harness `/tmp/gui-matrix.sh`, details in
  **`BROWSER-HANDOFF.md`**) showed: `foot` renders ✓; **`chromium
  --ozone-platform=wayland` RENDERS ✓** (creates a toplevel, 15 wl_shm buffers;
  GPU/dmabuf attempts fail → auto software fallback). So the pipeline handles a
  full browser — a Chromium-family browser is usable today. **Gecko is the
  specific blocker**, failing BEFORE any window via its **Wayland Proxy**.
  Firefox/zen connect to cocoa-way (waypipe forwards fine — ~4 "New client
  connected", Gecko is multiprocess) but create **0 toplevels / 0 buffers**, then
  die. The error is from Gecko's **Wayland Proxy**:
  `Wayland Proxy … CheckWaylandDisplay(): Failed to connect to Wayland display
  '/run/user/1001/wayland-<random>' : No such file or directory` →
  `we don't have any display, WAYLAND_DISPLAY='wayland-<random>'`. The
  `wayland-<random>` is the proxy's own socket; it never appears. Errors vary
  run-to-run (sometimes `no DISPLAY`), i.e. there's a **race / env-propagation**
  component on top. This is a firefox-over-waypipe problem, NOT cocoa-way. Next
  steps to try: (1) reliably disable Gecko's wayland proxy — `MOZ_DISABLE_WAYLAND_PROXY=1`
  did NOT take here, so verify the right knob for this build (possibly a profile
  pref `widget.wayland.use-proxy=false`); (2) ensure software rendering so any
  buffer is wl_shm not dmabuf (cocoa-way has no dmabuf) — `modules/zen.nix`
  already sets `gfx.webrender.software=true`+vaapi off for zen, but the `firefox`
  debug browser has no such prefs (so even if it starts it may go black via
  dmabuf); (3) the "black" the user saw earlier was the *render-succeeds-but-
  empty* mode from a run where the proxy DID come up — chase only after the proxy
  issue is resolved.
- **No HiDPI/Retina scaling (criterion #2): `foot` renders crisp but tiny.**
  cocoa-way advertises a fixed output (1920×1080, `Scale::Integer`) and a
  scale_factor that isn't tracking the Retina backing scale, so guest apps render
  at ~1× into a 2× window → tiny. This is cocoa-way-side scale wiring
  (`state.rs` output/`fractional_scale` + the NSWindow backing scale in the
  renderer). Separate from the offset fix; revisit in cocoa-way.
- **"Apps stop launching after a few attempts" (race / stale state).** Confirmed
  real: stale **waypipe-server** procs + leftover `/run/user/1001/wayland-*`
  sockets on the guest, and a lingering **ssh ControlPersist=600 master** on the
  host, accumulate across runs and cause hangs / connect failures (the blueish
  cocoa-way bg = compositor up, no client). **PARTLY ADDRESSED (2026-06-24):**
  `vmGui` now health-checks the ssh control master (`ssh -O check`) and resets it
  if stale before launching (safe for live windows), and a new **`vm gui-reset`**
  command hard-resets the whole stack (host waypipe+cocoa-way, ssh master, guest
  waypipe+sockets) — use it when wedged. The half-dead-master edge case may still
  slip past `-O check`; `vm gui-reset` is the catch-all.

### 7a-ter. Polish round (2026-06-25) — fixed / addressed
After zen worked end-to-end, a batch of UX issues. Fixed:
- **Second window rendered oversized until a resize.** `new_toplevel`
  (cocoa-way `state.rs`) sent a *full-window*-sized configure AFTER
  `add_tile`→`relayout` had already configured the new tile with its (half)
  tile size — the full-size configure won, so a tiled window rendered full-width
  into a half tile until the next resize forced a relayout. Fix: `new_toplevel`
  no longer sends a size; it sets Activated + fractional scale, then lets the
  layout's `request_size` own the size in a single configure.
- **New window didn't get keyboard focus (needed a click).** `new_toplevel` now
  calls `keyboard.set_focus(self, Some(surface), serial)` so a freshly created
  toplevel (e.g. Ctrl+Shift+P private window) is typable immediately.
- **`vm gui` blocked the terminal but didn't control the app.** The foreground
  `waypipe ssh` was never load-bearing (ssh ControlPersist master keeps the
  window alive; Ctrl-C left zen+cocoa-way running). `vmGui` now backgrounds it
  (`nohup … & disown`, logs to `/tmp/vm-gui-<app>.log`) and returns immediately.
  Supersedes the "post-quit hang" item below.
- **Decorations off (criterion #5).** cocoa-way `main.rs` honours
  `COCOA_WAY_DECORATIONS=0/false/off` → `WindowBuilder::with_decorations(false)`
  (no macOS titlebar / traffic lights; manage via host window shortcuts).
  `vmGui` sets `COCOA_WAY_DECORATIONS=0` on the (long-lived, reused) cocoa-way
  launch — so it only takes effect after cocoa-way is **restarted**
  (`vm gui-reset`). Upstream default stays decorated.
- **Browser was light despite "follow system".** No XDG portal in the guest, so
  Gecko falls back to GtkSettings (default `gtk-application-prefer-dark-theme`
  = false → light). `hosts/private-vm/full.nix` now writes
  `~/.config/gtk-{3,4}.0/settings.ini` with that hint = true (no gtk HM module
  → no dconf/dbus). Needs `vm rebuild`.

**To activate this round:** `nix-rebuild` (host: vmGui detach + decorations env —
done) · `vm rebuild` (guest: dark mode) · `vm gui-reset` then relaunch (restart
cocoa-way to pick up the new binary + decorations env; closes open windows).

### 7c. Still open (deferred)
- **One macOS NSWindow per guest toplevel (criterion #3).** cocoa-way is a
  single-window *tiling* compositor (`layout.rs`): extra toplevels tile inside one
  NSWindow rather than spawning a new native window. Making each toplevel its own
  NSWindow is a real architectural change (per-window winit window + renderer +
  seat focus routing). Acknowledged "may have to live with it." The initial-size
  + focus fixes above make the tiled case behave; true multi-window is a separate
  effort.
- **Host window title follows the guest toplevel title.** cocoa-way hardcodes
  "Cocoa-Way". Plumbing `xdg_toplevel.set_title` → `NSWindow.set_title` is small,
  but ambiguous under tiling (N toplevels, 1 window) — would track the focused
  tile. Lower value once decorations are off (no visible title); still shows in
  the macOS app switcher / Mission Control. Deferred.

### 7b. Pre-existing
- **Audio:** waypipe carries none. pipewire kept in the guest as the future
  capture point (forward `auto_null.monitor` to a host PulseAudio over SSH).

---

## 8. DELIVERY — getting the fixed cocoa-way in front of `vm gui`

The fix lives in the source clone (`~/projects/cocoa-way`), built at
`~/.cache/cargo-target/release/cocoa-way`. `vm gui`
(`modules/private-vm/default.nix` → `vmGui`) now prefers that local build, then
falls back to Homebrew with a warning. Durable options:

1. **Upstream it (preferred, but outward-facing — needs a decision).** PR the
   offset fix to `J-x-Z/cocoa-way`, then `brew upgrade cocoa-way`. Clean diff is
   just the `get_buffer_pixels` change; `render-test-offset.rs` is a ready-made
   regression test/repro to attach. The fork author is responsive (owns both
   repos). Filing the PR publishes the repro + diagnosis — get the go-ahead first.
2. **Interim: point `vm gui` at the local build.** In `vmGui`, set the
   `cocoa_way=` path to the built binary (or a wrapper) instead of
   `/opt/homebrew/bin/cocoa-way`, then `nix-rebuild`. Fast; fragile (depends on
   the clone + `cargo build`). Good for using the VM today while the PR lands.
3. **Local bottle / overlay.** Build a patched Homebrew bottle or a nix package
   so the fix is declarative in this repo. More work; most reproducible.

Verify any path with: `vm gui foot` (terminal renders) then `vm gui zen-beta`.

Once rendering is confirmed end-to-end, revisit §7 (decorations off, post-quit
hang, audio).
