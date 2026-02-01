# NixOS Modules for RP5

This directory contains reusable NixOS modules for the Retroid Pocket 5 configuration.

## Module Overview

| Module | Purpose |
|--------|---------|
| `hardware/` | Snapdragon 865 SoC and gamepad configuration |
| `graphics/` | Mesa/Turnip Vulkan and Gamescope compositor |
| `emulation/` | FEX-Emu/Box64 for x86_64 and Steam support |
| `overlay/` | System overlay daemon (HOME button quick settings) |
| `rocknix-compat/` | ROCKNIX kernel/firmware compatibility layer |

## Module Dependencies

```
rocknix-compat/kernel-modules.nix
         ↓
hardware/sm8250.nix
         ↓
graphics/mesa-turnip.nix
         ↓
graphics/gamescope.nix ← emulation/fex-emu.nix
         ↓                       ↓
      sessions             emulation/steam.nix
         ↓
  overlay/overlay-daemon.nix
```

## How Modules Work

Each module follows the standard NixOS module pattern:

1. **Options Declaration** - Defines configurable options under `rp5.*`
2. **Config Section** - Implements the configuration when enabled
3. **Dependencies** - May enable other modules it depends on

### Example Module Structure

```nix
{ config, lib, pkgs, ... }:

{
  options.rp5.myModule = {
    enable = lib.mkEnableOption "My module description";

    someSetting = lib.mkOption {
      type = lib.types.str;
      default = "default-value";
      description = "What this setting does";
    };
  };

  config = lib.mkIf (config.rp5.myModule.enable or true) {
    # Configuration goes here
    environment.systemPackages = [ ... ];
  };
}
```

## Enabling/Disabling Modules

Most modules are enabled by default (`config.rp5.*.enable or true`). To disable:

```nix
# In hosts/rp5/default.nix or similar
{
  rp5.steam.enable = false;      # Disable Steam support
  rp5.gamescope.enable = false;  # Disable Gamescope
}
```

## Adding New Modules

1. Create a new `.nix` file in the appropriate subdirectory
2. Follow the module pattern above
3. Import it in `flake.nix` or the host configuration
4. Document it in this README

## Common Options

All modules use the `rp5.*` option namespace:

| Option | Type | Description |
|--------|------|-------------|
| `rp5.hardware.sm8250.enable` | bool | Snapdragon 865 hardware config |
| `rp5.hardware.gamepad.enable` | bool | Built-in gamepad support |
| `rp5.graphics.enable` | bool | Mesa/Turnip graphics |
| `rp5.gamescope.enable` | bool | Gamescope compositor |
| `rp5.fex-emu.enable` | bool | x86_64 emulation |
| `rp5.steam.enable` | bool | Steam integration |
| `rp5.overlay.enable` | bool | System overlay daemon |
| `rp5.rocknix.enable` | bool | ROCKNIX compatibility |
