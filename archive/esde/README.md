# Archived: ES-DE (EmulationStation Desktop Edition) Support

This directory contains archived code for ES-DE session support that was removed to scale back the project scope.

## What Was Removed

ES-DE support included:
- **Gamescope ES-DE session** - Launch ES-DE inside Gamescope compositor
- **Session switching** - Switch to/from ES-DE via `rp5-session-switch esde`
- **Overlay menu integration** - "Switch to ES-DE" option in quick settings

## Why It Was Archived

The project was scaled back to focus on core functionality:
- NixOS boot chain
- Steam Gamescope session
- KDE Plasma desktop
- System overlay daemon

ES-DE can be re-integrated when these core features are stable.

## Files in This Archive

| File | Description |
|------|-------------|
| `sessions.nix.snippet` | ES-DE session script, desktop entry, and systemd service |
| `overlay.nix.snippet` | ES-DE case in rp5-session-switch utility |
| `overlay-daemon.nix.snippet` | ES-DE menu options in overlay UI |

## How to Re-integrate

### 1. Add session script to `hosts/rp5/sessions.nix`

Add the `gamescopeEsdeSession` script definition in the `let` block (after `gamescopeSteamSession`).

### 2. Add desktop entry to `hosts/rp5/sessions.nix`

Add the desktop entry under `environment.etc."greetd/sessions/gamescope-esde.desktop"`.

### 3. Add systemd user service to `hosts/rp5/sessions.nix`

Add the `gamescope-esde` service in `systemd.user.services`.

### 4. Add session switch case to `overlays/default.nix`

Add the `esde)` case to the `rp5-session-switch` script.

### 5. Add overlay menu option to `modules/overlay/overlay-daemon.nix`

Add "Switch to ES-DE" option and handler in the overlay UI script.

### 6. Install ES-DE package

Add `emulationstation-de` to `environment.systemPackages` if not already available.

## Dependencies

ES-DE requires:
- Gamescope compositor (already configured)
- RetroArch and/or standalone emulators
- ROM files and BIOS files
- ES-DE themes (optional)

## Testing After Re-integration

1. Build: `nix build .#nixosConfigurations.rp5.config.system.build.toplevel`
2. Verify desktop entry exists: Check `/etc/greetd/sessions/`
3. Test session switching: `rp5-session-switch esde`
4. Test overlay menu: Hold HOME for 800ms, select ES-DE option
