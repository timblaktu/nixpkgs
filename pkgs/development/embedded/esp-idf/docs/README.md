# ESP-IDF for Nixpkgs

The Espressif IoT Development Framework (ESP-IDF) is the official development framework for Espressif's ESP32 series of microcontrollers.

## Overview

This package provides a complete ESP-IDF installation with support for all ESP32 variants, including preview targets like ESP32-C5. It follows nixpkgs best practices and provides a reproducible, offline-capable build environment.

## Supported Targets

### Stable Targets (Default)
- **ESP32** - Original ESP32, Xtensa architecture
- **ESP32-S2** - Xtensa, USB-OTG support
- **ESP32-S3** - Xtensa, AI acceleration
- **ESP32-C2** - RISC-V, low-cost variant
- **ESP32-C3** - RISC-V, popular choice
- **ESP32-C6** - RISC-V, Wi-Fi 6 support
- **ESP32-H2** - RISC-V, 802.15.4 only
- **ESP32-P4** - RISC-V, high performance

### Preview Targets (Opt-in)
- **ESP32-C5** - RISC-V, dual-band Wi-Fi 6 (requires `enablePreviewTargets = true`)

## Usage

### Basic Usage

```bash
# Install ESP-IDF with all stable targets
nix-shell -p esp-idf

# Enter development shell
nix-shell -p esp-idf --run 'echo "ESP-IDF Path: $IDF_PATH"'
```

### Target-Specific Variants

```nix
# Single target packages
esp-idf-esp32      # ESP32 only
esp-idf-esp32c3    # ESP32-C3 only
esp-idf-esp32c6    # ESP32-C6 only

# Architecture-specific
esp-idf-riscv      # All RISC-V targets
esp-idf-xtensa     # All Xtensa targets
```

### ESP32-C5 Preview Support

```nix
# Override for ESP32-C5 support
esp-idf.override {
  supportedTargets = [ "esp32c5" ];
  enablePreviewTargets = true;
  rev = "d930a386dae";  # Known working commit
  sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM=";
}

# Or use the convenience package
esp-idf-esp32c5
```

### Custom Target Selection

```nix
# Multi-target custom build
esp-idf.override {
  supportedTargets = [ "esp32" "esp32c3" "esp32c6" ];
}

# All targets including preview
esp-idf.override {
  supportedTargets = [ "esp32" "esp32s2" "esp32s3" "esp32c2" "esp32c3" "esp32c6" "esp32h2" "esp32p4" ];
  enablePreviewTargets = true;
  previewTargets = [ "esp32c5" ];
}
```

## Development Workflows

### Basic Project Setup

```bash
# Enter ESP-IDF environment
nix-shell -p esp-idf

# Create new project
mkdir my-esp-project && cd my-esp-project

# Set target (use --preview for ESP32-C5)
idf.py set-target esp32c3
# OR for ESP32-C5:
# idf.py --preview set-target esp32c5

# Configure project
idf.py menuconfig

# Build
idf.py build

# Flash and monitor
idf.py flash monitor
```

### Using with Flakes

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  
  outputs = { nixpkgs, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in {
      devShells.x86_64-linux.default = pkgs.mkShell {
        buildInputs = [ 
          (pkgs.esp-idf.override {
            supportedTargets = [ "esp32c6" ];
          })
        ];
        
        shellHook = ''
          echo "ESP32-C6 development environment ready!"
          echo "ESP-IDF Path: $IDF_PATH"
        '';
      };
    };
}
```

### Integration with Existing Projects

The package automatically sets up the required environment variables:
- `IDF_PATH` - Path to ESP-IDF installation
- `IDF_TOOLS_PATH` - Path to ESP-IDF tools
- `IDF_PYTHON_ENV_PATH` - Python environment path
- `PATH` - Updated to include all ESP-IDF tools

## Environment Variables

The package provides automatic environment setup through setup hooks. When ESP-IDF is in your `buildInputs`, these variables are automatically configured:

```bash
IDF_PATH=/nix/store/...-esp-idf-5.4.1
IDF_TOOLS_PATH=$IDF_PATH/.espressif
IDF_PYTHON_ENV_PATH=$IDF_PATH/python-env
```

## Advanced Configuration

### Custom Python Environment

```nix
esp-idf.override {
  pythonEnv = python3.withPackages (ps: with ps; [
    # Add custom Python packages
    setuptools click pyserial
    # Your additional packages here
  ]);
}
```

### Tool Selection

The package automatically installs all tools required for your selected targets by parsing ESP-IDF's `tools.json`. This ensures compatibility and completeness.

## Troubleshooting

### Common Issues

1. **"Tool not found" errors**: Ensure you're using a shell with ESP-IDF in `buildInputs` to get proper PATH setup.

2. **ESP32-C5 not available**: Make sure you're using `enablePreviewTargets = true` and the `--preview` flag with idf.py.

3. **Git repository errors**: The package creates a proper git repository structure that ESP-IDF expects.

4. **Python environment issues**: The package provides an isolated Python environment to avoid conflicts.

### Debug Information

```bash
# Check ESP-IDF environment
echo $IDF_PATH
echo $IDF_TOOLS_PATH

# List available targets
idf.py --list-targets
idf.py --preview --list-targets  # Include preview targets

# Verify tool installation
ls $IDF_TOOLS_PATH/tools/
```

## Migration from External Packages

See `migration.md` for detailed instructions on migrating from external ESP-IDF packages like `nixpkgs-esp-dev`.

## Contributing

This package follows nixpkgs standards and conventions. When contributing:

1. Test across multiple architectures
2. Ensure all targets build correctly
3. Verify integration tests pass
4. Update documentation as needed

## License

ESP-IDF is licensed under Apache License 2.0. This nixpkgs package follows the same license.