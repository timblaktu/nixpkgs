# Migration Guide: From External ESP-IDF Packages to nixpkgs ESP-IDF

This guide helps you migrate from external ESP-IDF packages to the official nixpkgs ESP-IDF package.

## Migration Overview

### From `nixpkgs-esp-dev`

The most common migration path is from `mirrexagon/nixpkgs-esp-dev`, which many users currently rely on.

#### Before (nixpkgs-esp-dev)
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-esp-dev = {
      url = "github:mirrexagon/nixpkgs-esp-dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  
  outputs = { nixpkgs, nixpkgs-esp-dev, ... }: {
    devShells.x86_64-linux.default = 
      let pkgs-esp = nixpkgs-esp-dev.packages.x86_64-linux;
      in pkgs.mkShell {
        buildInputs = [ pkgs-esp.esp-idf-esp32c3 ];
      };
  };
}
```

#### After (nixpkgs ESP-IDF)
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Remove nixpkgs-esp-dev dependency
  };
  
  outputs = { nixpkgs, ... }: {
    devShells.x86_64-linux.default = 
      let pkgs = import nixpkgs { system = "x86_64-linux"; };
      in pkgs.mkShell {
        buildInputs = [ 
          (pkgs.esp-idf.override { supportedTargets = [ "esp32c3" ]; })
        ];
      };
  };
}
```

### ESP32-C5 Migration

#### Before (Manual ESP-IDF installation)
```bash
# Manual installation required for ESP32-C5
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf && git checkout d930a386dae
./install.sh esp32c5
source export.sh
```

#### After (nixpkgs ESP-IDF)
```nix
# Declarative ESP32-C5 support
esp-idf.override {
  supportedTargets = [ "esp32c5" ];
  enablePreviewTargets = true;
  rev = "d930a386dae";
  sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM=";
}

# Or use the convenience package
esp-idf-esp32c5
```

## Detailed Migration Steps

### Step 1: Update Flake Inputs

Remove external ESP-IDF dependencies from your flake inputs:

```diff
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
-   nixpkgs-esp-dev = {
-     url = "github:mirrexagon/nixpkgs-esp-dev";
-     inputs.nixpkgs.follows = "nixpkgs";
-   };
  };
```

### Step 2: Update Package References

Replace external package references with nixpkgs ESP-IDF:

```diff
- buildInputs = [ nixpkgs-esp-dev.packages.${system}.esp-idf-esp32c3 ];
+ buildInputs = [ (pkgs.esp-idf.override { supportedTargets = [ "esp32c3" ]; }) ];
```

### Step 3: Update Environment Setup

The nixpkgs package provides automatic environment setup, so you can remove manual setup:

```diff
  shellHook = ''
-   export IDF_PATH=${nixpkgs-esp-dev.packages.${system}.esp-idf-esp32c3}/share/esp-idf
-   export PATH=$IDF_PATH/tools:$PATH
+   # Environment automatically configured by nixpkgs ESP-IDF
    echo "ESP-IDF Path: $IDF_PATH"
  '';
```

### Step 4: Update Build Commands

Commands remain the same, but preview targets now work properly:

```bash
# Same commands work
idf.py set-target esp32c3
idf.py build

# ESP32-C5 now works with --preview flag
idf.py --preview set-target esp32c5
idf.py --preview build
```

## Package Mapping

### nixpkgs-esp-dev → nixpkgs ESP-IDF

| Old Package | New Package |
|-------------|-------------|
| `esp-idf-esp32` | `pkgs.esp-idf.override { supportedTargets = [ "esp32" ]; }` |
| `esp-idf-esp32s2` | `pkgs.esp-idf.override { supportedTargets = [ "esp32s2" ]; }` |
| `esp-idf-esp32s3` | `pkgs.esp-idf.override { supportedTargets = [ "esp32s3" ]; }` |
| `esp-idf-esp32c2` | `pkgs.esp-idf.override { supportedTargets = [ "esp32c2" ]; }` |
| `esp-idf-esp32c3` | `pkgs.esp-idf.override { supportedTargets = [ "esp32c3" ]; }` |
| `esp-idf-esp32c6` | `pkgs.esp-idf.override { supportedTargets = [ "esp32c6" ]; }` |
| `esp-idf-full` | `pkgs.esp-idf` (default includes all stable targets) |
| N/A (unsupported) | `pkgs.esp-idf-esp32c5` (now available!) |

### Convenience Packages

For common use cases, direct packages are available:

```nix
# Instead of overrides, you can use direct packages
esp-idf-esp32      # ESP32 only
esp-idf-esp32c3    # ESP32-C3 only  
esp-idf-esp32c5    # ESP32-C5 with preview support
esp-idf-riscv      # All RISC-V targets
esp-idf-xtensa     # All Xtensa targets
```

## Configuration Migration

### Target Selection

#### Before
```nix
# Fixed packages for each target
nixpkgs-esp-dev.packages.${system}.esp-idf-esp32c3
nixpkgs-esp-dev.packages.${system}.esp-idf-esp32c6
```

#### After
```nix
# Flexible target selection
esp-idf.override { 
  supportedTargets = [ "esp32c3" "esp32c6" ]; 
}
```

### Version Pinning

#### Before
```nix
# Version controlled by nixpkgs-esp-dev maintainer
nixpkgs-esp-dev.packages.${system}.esp-idf-esp32c3
```

#### After
```nix
# Direct control over ESP-IDF version
esp-idf.override {
  rev = "v5.4.1";  # or specific commit
  sha256 = "sha256-...";
}
```

## Testing Your Migration

After migration, verify everything works:

```bash
# Test basic functionality
nix develop
echo $IDF_PATH
idf.py --list-targets

# Test your specific target
idf.py set-target esp32c3  # or your target
idf.py menuconfig
idf.py build

# For ESP32-C5
idf.py --preview set-target esp32c5
idf.py --preview build
```

## Common Migration Issues

### Issue: "Package not found"
**Problem**: Trying to use old package names
**Solution**: Use the new nixpkgs ESP-IDF package with appropriate overrides

### Issue: "ESP32-C5 target not available"
**Problem**: Preview targets not enabled
**Solution**: Use `enablePreviewTargets = true` and `--preview` flag

### Issue: "Tool not found in PATH"
**Problem**: Environment not properly set up
**Solution**: Ensure ESP-IDF is in `buildInputs`, not just installed separately

### Issue: "Python environment conflicts"
**Problem**: System Python conflicting with ESP-IDF Python
**Solution**: The nixpkgs package provides isolated Python environment automatically

## Benefits of Migration

### Immediate Benefits
- ✅ **ESP32-C5 support** - Preview targets now work properly
- ✅ **Official support** - Part of nixpkgs, maintained by community
- ✅ **Better reproducibility** - Proper fixed-output derivations
- ✅ **Simplified dependencies** - No external flake inputs needed

### Long-term Benefits
- 🚀 **Automatic updates** - Updated with nixpkgs releases
- 🚀 **Better integration** - Works seamlessly with nixpkgs ecosystem
- 🚀 **Wider compatibility** - Tested across all nixpkgs platforms
- 🚀 **Future-ready** - Support for new ESP32 variants as they're released

## Getting Help

If you encounter issues during migration:

1. **Check the troubleshooting section** in `README.md`
2. **Test with minimal configuration** to isolate issues
3. **Compare working examples** in the documentation
4. **Report issues** to nixpkgs if you find bugs

## Rollback Plan

If you need to temporarily rollback during migration:

```nix
# Temporarily keep both during transition
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-esp-dev.url = "github:mirrexagon/nixpkgs-esp-dev";  # Keep temporarily
  };
  
  outputs = { nixpkgs, nixpkgs-esp-dev, ... }: {
    devShells.x86_64-linux = {
      # New nixpkgs ESP-IDF (preferred)
      default = pkgs.mkShell {
        buildInputs = [ pkgs.esp-idf-esp32c3 ];
      };
      
      # Old nixpkgs-esp-dev (fallback)
      legacy = pkgs.mkShell {
        buildInputs = [ nixpkgs-esp-dev.packages.x86_64-linux.esp-idf-esp32c3 ];
      };
    };
  };
}
```

This allows you to use `nix develop .#legacy` if needed while transitioning.