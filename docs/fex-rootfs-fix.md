# FEX-Emu Rootfs Overlay Fix Plan

## Problem Summary

Steam cannot render its UI on the RP5 because FEX-Emu's rootfs overlay is not activating. x86_64 processes see the NixOS host filesystem instead of the Ubuntu 24.04 rootfs, so no x86_64 shared libraries (mesa, libGL, libc, etc.) are available. steamwebhelper (Chromium-based) crashes because it can't create a GL context.

## Diagnostic Evidence

| Command | Expected | Actual | Implication |
|---------|----------|--------|-------------|
| `FEXBash -c "uname -m"` | `x86_64` | `aarch64` | FEX is NOT emulating |
| `FEXBash -c "cat /etc/os-release"` | Ubuntu 24.04 | NixOS | Rootfs overlay NOT active |
| `steam` client starts | — | Connects to Valve | binfmt dispatches x86_64 binary to FEXInterpreter |
| steamwebhelper | Renders UI | Crashes (no GL) | No x86_64 mesa/llvmpipe available |

## How FEX Rootfs Overlay Works

FEX does NOT use FUSE or kernel overlayfs. It intercepts syscalls at the emulation layer:

1. x86_64 guest process issues `open("/usr/lib/x86_64-linux-gnu/libGL.so")`
2. FEX's `FileManager::GetEmulatedFDPath()` intercepts the syscall
3. Tries `openat2(rootfs_fd, "usr/lib/x86_64-linux-gnu/libGL.so", RESOLVE_IN_ROOT)`
4. If found in rootfs: use rootfs version. If not: fall back to host path.

This requires:
- A valid rootfs directory fd (`rootfs_fd`) initialized at startup
- Config.json properly read with `RootFS` pointing to the rootfs
- Kernel 5.15+ for `openat2()` with `RESOLVE_IN_ROOT` (ROCKNIX 6.12.28 has this)

### FEXBash Flow
```
FEXBash → execve(FEX, [FEX, "/bin/bash"]) → FEX loads config → FEX opens rootfs dir
  → FEX tries rootfs's /bin/bash (x86_64) → JIT-translates → rootfs overlay active for all syscalls
```

### binfmt Flow
```
kernel exec(x86_64.elf) → binfmt → /run/binfmt/FEX-x86_64 (shell wrapper) → FEXInterpreter
  → FEX loads config → same rootfs overlay for this process
```

## Root Causes (Ranked)

### 1. `/bin/bash` tmpfiles symlink short-circuits FEXBash (HIGH)

`steam.nix` creates: `"L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"`

FEXBash calls `FEX /bin/bash`. If FEX resolves `/bin/bash` on the host BEFORE checking the rootfs (or if the rootfs fd isn't initialized yet), it finds an aarch64 ELF, can't emulate its own arch, and either passes through or errors out. The result: native bash, no emulation, no rootfs overlay.

### 2. Config/Data directory mismatch (HIGH)

- Config: `~/.config/fex-emu/Config.json` (XDG path)
- Data: `~/.fex-emu/RootFS/Ubuntu_24_04/` (legacy path)

FEX resolves these independently. The config is read from XDG. But rootfs name resolution searches the **data directory**. If there's a mismatch in how these are resolved, the rootfs fd never gets initialized.

### 3. nixpkgs FEX patches shift config option indexing (LOW)

The nixpkgs package renames `ThunkGuestLibs` → `UnusedThunkGuestLibs` and `ThunkHostLibs` → `UnusedThunkHostLibs` in the config schema. The `ROOTFS` option itself is NOT renamed, but if the enum/indexing shifts, the runtime value could be wrong. Unlikely but possible.

## Fix Plan

### Phase 1: Tactical Fixes (in code)

1. **FEX config setup service** — Ensure Config.json uses absolute rootfs path and lives in the correct directory (`~/.fex-emu/Config.json`)
2. **Remove `/bin/bash` tmpfiles symlink** — Force FEX to find bash from rootfs, not host. Use `environment.binsh` if other services need it.
3. **Steam wrapper diagnostics** — Add pre-flight checks before launching FEXBash
4. **Direct FEX invocation** — Try `FEX <rootfs>/bin/bash` instead of relying on FEXBash's `/bin/bash` lookup
5. **FEX_ROOTFS env var** — Set rootfs path explicitly in the environment

### Phase 2: Strategic Alternative (if Phase 1 fails)

**bubblewrap namespace approach** — Create a real filesystem namespace with the rootfs as root, bypassing FEX's syscall-level overlay entirely:

```bash
bwrap \
  --bind ~/.fex-emu/RootFS/Ubuntu_24_04 / \
  --dev /dev --proc /proc --bind /sys /sys \
  --bind /tmp /tmp --bind /run /run \
  --bind ~/.local/share/Steam ~/.local/share/Steam \
  -- /bin/bash -c "./steam.sh"
```

### Phase 3: Full Solution (future)

Consider muvm (micro-VM) approach used by Fedora Asahi — kernel overlayfs for merged rootfs. See: https://github.com/nrabulinski/nixos-muvm-fex

## References

- [FEX-Emu Wiki: RootFS Setup](https://wiki.fex-emu.com/index.php/Development:Setting_up_RootFS)
- [FEX-Emu Wiki: Config](https://wiki.fex-emu.com/index.php/Config)
- [FEX-Emu GitHub: FileManagement.cpp](https://github.com/FEX-Emu/FEX/blob/main/Source/Tools/LinuxEmulation/LinuxSyscalls/FileManagement.cpp)
- [nixpkgs FEX package](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/fe/fex/package.nix)
- [nixpkgs #373165: FEX rootfs issues](https://github.com/NixOS/nixpkgs/issues/373165)
- [nixpkgs #376850: FEX thunk libs](https://github.com/NixOS/nixpkgs/issues/376850)
- [nixos-muvm-fex](https://github.com/nrabulinski/nixos-muvm-fex)
