# Profile system — design & migration plan

Status: **implemented** (2026-06-20)

Notes from implementation (where reality diverged from the plan above):
- `isDarwin` was consumed by only two HM modules (`zen`, `homebrew`). Swapping a
  whole-module `lib.optionalAttrs pkgs.stdenv.isDarwin` guard caused infinite
  recursion (under `useGlobalPkgs`, `pkgs` is config-derived, so gating option
  *paths* on it forces config eval during option discovery). Use `lib.mkIf`,
  which defers the condition, for whole-module guards.
- `flake.lib` needed an explicit option declaration (`options.nix`) so the
  resolver/wiring helpers and the private-vm launcher can both contribute to it
  without a merge collision.
- The `private-vm` modules are the **mac-side** control plane (the `vm` CLI
  drives Lima; the casks install xpra/age-plugin-se on the Mac), so the HM
  launcher is appended host-locally to **mac**, not to the guest. It is exposed
  as `flake.lib.privateVmHm` (off the registry) since it closes over `inputs`.
- Phase 5 (DRY) landed as `flake.lib.mkHmModule { profiles; extra; }`, which
  emits the whole `home-manager.{backupFileExtension,useGlobalPkgs,
  useUserPackages,sharedModules}` block; hosts keep only the per-platform
  `home-manager.{darwin,nixos}Modules.home-manager` import.
- Dropping the redundant `darwinDesktop` guards is a behavioral no-op on mac
  (verified: all home-file *contents* byte-identical). The mac system store hash
  still changes because `modules/hammerspoon` copies its own directory into the
  store via `"${./.}/…"`, so editing `hammerspoon.nix` rehashes that path — a
  benign pre-existing pattern, not a config change.

## Why

This config began life as a single nix-darwin host and later grew two more
(`wsl`, `private-vm`) without rethinking the module layer. Today every host does:

```nix
home-manager.sharedModules = builtins.attrValues inputs.self.homeManagerModules;
```

i.e. **all ~26 home-manager modules load on every host**, and differentiation
happens through ~17 hand-written `mkIf isDarwin` / `mkIf stdenv.isDarwin` guards
scattered across individual module files. Consequences:

- You can't tell what a host actually gets without reading 25+ files.
- Every module must self-guard on platform; the platform logic is nowhere
  central.
- There's no way to express any axis other than darwin-vs-not (e.g. GUI vs
  headless, "I ssh in" vs "I sit in front of it").
- Latent cruft: `wezterm` (`mkIf !isDarwin`) loads on `private-vm` too and writes
  a `wezterm.lua` for a terminal that host doesn't have.

## Goal

A host file should be a one-line statement of **intent** ("base + ai + browser"),
the module→profile taxonomy should live in **one readable place**, and a module
should only load where it belongs instead of loading-then-guarding.

## Architecture — three layers

### Layer 1: modules (unchanged)

`import-tree ./modules` keeps registering each module as
`flake.homeManagerModules.<name>` / `flake.darwinModules.<name>`. No module
*files* move (except host-singular ones, see below). The only in-module change is
removing **whole-module** platform guards — see the splitting rule.

### Layer 2: profile registry (new, central)

One file, `modules/profiles.nix`, is the single source of truth for the
taxonomy. Direction is `profile → [module names]` (reads best for host
composition):

```nix
{ ... }:
{
  flake.profiles.hm = {
    base = [ "shell" "tools" "neovim" "starship" "tmux" "tmuxLayout"
             "nix-dev" "dev" "themes" ];
    ai   = [ "claude" "codex" "opencode" "playwright" ];
    browser = [ "zen-browser" "zen" ];   # external module + our config
    darwinDesktop = [ "sketchybar" "hammerspoon" "ical" "jira" "openwhispr"
                      "tridactyl" "copilot" "homebrew" "terminal" "ghostty-themes" ];
  };
}
```

### Layer 3: host composition + resolver (new helper)

A resolver defined once (e.g. `modules/lib.nix`) turns a profile list into the
`sharedModules` list:

```nix
{ lib, config, ... }:
{
  flake.lib.mkHmSharedModules = profiles:
    let
      names = lib.unique (lib.concatMap (p: config.flake.profiles.hm.${p}) profiles);
    in
      map (n: config.flake.homeManagerModules.${n}) names;
}
```

Hosts then declare intent and append any one-offs:

```nix
# hosts/mac/flake-module.nix
home-manager.sharedModules =
  inputs.self.lib.mkHmSharedModules [ "base" "ai" "browser" "darwinDesktop" ];

# hosts/private-vm
home-manager.sharedModules =
  inputs.self.lib.mkHmSharedModules [ "base" "ai" "browser" ]
  ++ [ ./home.nix ];                # host-local extras (one-off packages etc.)

# hosts/wsl
home-manager.sharedModules =
  inputs.self.lib.mkHmSharedModules [ "base" "ai" ]
  ++ [ ./wezterm.nix ];             # WSL-singular terminal, host-local
```

This resolver also subsumes the wiring-duplication: the whole
`home-manager.useGlobalPkgs / useUserPackages / sharedModules` block can be
produced by one shared helper instead of being copy-pasted across three host
flake-modules.

## Design decisions

1. **Central manifest, not self-tagging.** Membership lives in `profiles.nix`,
   not in each module. Self-tags would re-scatter exactly the composition data
   the refactor exists to centralize, and they'd require a second `flake.*` attr
   per module anyway (membership can't live inside the HM module body — that's
   only evaluated in the HM context). The manifest also makes completeness
   *checkable*:

   ```nix
   # assertion (in a flake-module): every registered module is classified
   classified = lib.unique (lib.concatLists (lib.attrValues config.flake.profiles.hm));
   orphans    = lib.subtractLists classified (lib.attrNames config.flake.homeManagerModules);
   # assert orphans == []   (minus any deliberately host-local modules)
   ```

2. **Multi-membership allowed, rare by design.** Host resolution takes the union
   (`lib.unique ∘ concatMap`), so a module listed in two profiles dedups to one
   import — free. But needing it often means the profiles aren't orthogonal;
   treat frequent multi-membership as a signal to re-cut the axes, not as normal.

3. **Profiles + host-local extras compose.** `mkHmSharedModules` returns a list
   you append to. Rule of thumb: **profiles are for things that repeat; host
   files are for things that don't.** Reusable bundle → profile (manifest).
   Singular to one host (a one-off package, a machine-specific module like the
   WSL terminal) → `hosts/<h>/home.nix` or a host-local module, never the
   registry. `pkgs` is in scope in a host-local HM module, so ad-hoc packages
   belong there, not in the flake-level wiring.

## The splitting rule

Most modules are already single-concern; the work is *classifying*, not
splitting. For any conditional, decide where it goes:

- **Whole-module platform guard → profile membership.** If the entire module is
  darwin-only (`sketchybar`, `hammerspoon`, `ical`, `jira`, `openwhispr`,
  `tridactyl`, `copilot`, ghostty `terminal`), delete the `mkIf`/`optionalAttrs`
  wrapper and express the fact via the `darwinDesktop` profile.
- **Intra-module platform branch → stays inline.** If the module runs everywhere
  but one *part* differs (`dev` adds colima on darwin; `claude` picks a different
  binary path; `zen`'s `package` source), keep the branch inline. Test: "does
  this module do anything at all off its native platform?" Yes → inline branch.
- **Install mechanism is a separate axis from config.** A module's *config* (HM)
  and how its *app is installed* (homebrew cask via a `darwinModule`, vs a nix
  package on linux) are different concerns and must not collapse into one guard.
  See the zen worked example.

## Module → profile taxonomy

| module            | profile / location        | notes |
|-------------------|---------------------------|-------|
| shell, tools, neovim, starship, tmux, tmuxLayout, nix-dev, dev, themes | `base` | dev adds colima inline on darwin |
| claude, codex, opencode, playwright | `ai` | claude has inline binary-path branch |
| zen-browser (external), zen | `browser` | see worked example |
| sketchybar, hammerspoon, ical, jira, openwhispr, tridactyl, copilot, homebrew | `darwinDesktop` | all currently whole-darwin-guarded → drop guards |
| terminal (ghostty), ghostty-themes | `darwinDesktop` | ghostty is mac's terminal (macos-* settings, ghostty-bin) |
| wezterm           | **host-local → hosts/wsl/** | WSL-singular: writes `wezterm.lua` to `/mnt/c`. Remove from global registry; fixes the private-vm stray-config bug. |
| private-vm (hm + darwin) | **host-local → hosts/private-vm/** | host-specific config leaking into the global registry today; move it out |

Notes:
- `terminalEmulator` is intentionally **not** a profile. ghostty and wezterm are
  host-singular and don't co-vary; a shared terminal profile would be a premature
  abstraction. Revisit only if WSLg lands and a *cross-platform* ghostty is
  wanted on multiple hosts (see Open questions).
- `copilot` depends on a Homebrew cask (`/opt/homebrew/bin/copilot` wrapper), so
  it's genuinely darwin-only → `darwinDesktop`. Revisit if a cross-platform CLI
  becomes available.

## Host profile lists

| host        | profiles                                   | terminal |
|-------------|--------------------------------------------|----------|
| mac         | base, ai, browser, darwinDesktop           | ghostty (in darwinDesktop) |
| private-vm  | base, ai, browser                          | none — ssh from host |
| wsl         | base, ai                                   | wezterm (host-local) |
| wsl + WSLg (future) | base, ai, browser                  | + a cross-platform terminal, TBD |

## Worked example: zen on the aarch64 private-vm

**Confirmed viable.** Zen ships `zen.linux-aarch64.tar.xz` /
`zen-aarch64.AppImage` upstream, and
`inputs.zen-browser.packages.aarch64-linux.default` resolves to `zen-beta-1.21.3b`
with `aarch64-linux` in `meta.platforms`.

`modules/zen.nix` today wraps its *entire* HM config in `lib.optionalAttrs
isDarwin` — so zen is effectively darwin-only. That one guard conflates three
jobs; the refactor teases them apart:

1. **"Should it load?" → profile.** Delete the `optionalAttrs isDarwin` wrapper;
   `browser` membership decides. The policies / userChrome theming / search
   engines are all platform-agnostic and apply on both mac and private-vm.
2. **Install mechanism → two paths, not one guard.**
   - darwin: app comes from the Homebrew cask. Keep `flake.darwinModules.zen`
     (`homebrew.casks = ["zen"]`), pulled only by the mac host. HM sets
     `package = null` so it doesn't also install.
   - linux: no Homebrew → package comes from the flake. The one genuine inline
     branch:
     ```nix
     { inputs, ... }:                       # outer scope already has inputs
     flake.homeManagerModules.zen-browser = inputs.zen-browser.homeModules.beta;
     flake.homeManagerModules.zen = { pkgs, lib, config, ... }:
       let inherit (pkgs.stdenv) isDarwin; in {
         programs.zen-browser = {
           enable = true;
           package = if isDarwin then null
                     else inputs.zen-browser.packages.${pkgs.system}.default;
           # policies / profiles.default / search — unchanged, platform-agnostic
         };
       };
     ```
     Registering the external `zen-browser` homeModule into the `browser` profile
     removes the hand-appended `inputs.zen-browser.homeModules.beta` from
     `hosts/mac/flake-module.nix` — both hosts get it automatically.
3. **Genuinely mac-only prefs → inline.** A handful stay guarded inline rather
   than polluting the shared config:
   ```nix
   settings = { /* cross-platform */ } // lib.optionalAttrs isDarwin {
     "widget.macos.sidebar-blend-mode.behind-window" = false;
     "full-screen-api.macos-native-full-screen"      = false;
   };
   ```
   `darwinDefaultsId` is already correctly `lib.mkIf isDarwin`.

## Cleanups that fall out

- **Kill the `isDarwin` specialArg.** Two platform-detection mechanisms exist
  today: `isDarwin` via `extraSpecialArgs` (manually set in 3 wiring blocks, can
  drift) and `pkgs.stdenv.isDarwin` (can't lie). Standardize on `stdenv`, drop
  the specialArg from all three host flake-modules and from module signatures.
- **DRY the home-manager wiring block** via the resolver / a shared helper.
- **Move `private-vm` out of the global module registry** into host-local files.
- **Remove the stray `wezterm.lua` on private-vm** by making wezterm WSL-local.

## Implementation order

1. **Mechanical warmup:** replace `isDarwin` specialArg with
   `pkgs.stdenv.isDarwin` everywhere; remove it from `extraSpecialArgs`. Rebuild
   each host green. (Low risk, shrinks the diff for later steps.)
2. **Add Layer 2 + 3:** `modules/profiles.nix`, `flake.lib.mkHmSharedModules`,
   and the completeness assertion. Don't wire hosts yet.
3. **Proof-of-concept slice:** convert `base` + `browser`, point one host
   (mac) at the resolver for just those, `nix flake check`.
4. **Full reclassification:** drop whole-module guards from `darwinDesktop`
   members; move `wezterm` and `private-vm` to host-local; do the zen surgery;
   convert all three hosts to profile lists.
5. **DRY the wiring block.**

## Verification

- `nix flake check` after each phase.
- Per host: `nix build .#darwinConfigurations.mac.system` /
  `.#nixosConfigurations.{wsl,private-vm}.config.system.build.toplevel`.
- Spot-check: WSL no longer builds `wezterm.lua`? private-vm has zen and *no*
  ghostty/wezterm config? mac unchanged?

## Open questions

- **WSLg terminal.** When WSLg is tried, decide whether to build a
  cross-platform `ghostty` (the current one is mac-coupled via `ghostty-bin` +
  `macos-*` settings). Only then does a shared `terminalEmulator` profile earn
  its keep — don't build it speculatively.
- **darwinModules** are only consumed by mac today, so a profile layer for them
  is lower priority; the same mechanism applies if a second darwin host ever
  appears.
