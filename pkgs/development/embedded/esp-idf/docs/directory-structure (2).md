# ESP-IDF Package Directory Structure and Setup

## Working in Your Existing nixpkgs Fork

Since you already have a nixpkgs working tree with your fork as origin:

### Directory Structure in Your nixpkgs Fork

```
/path/to/your/nixpkgs/
├── pkgs/
│   ├── development/
│   │   └── embedded/
│   │       └── esp-idf/                 # ← Create this
│   │           ├── default.nix          # Main package (artifact 1)
│   │           ├── variants.nix         # Target variants (artifact 2)  
│   │           ├── shells.nix           # Dev shells (artifact 3)
│   │           ├── tests/
│   │           │   ├── basic.nix        # Basic tests (artifact 4)
│   │           │   ├── esp32c5.nix      # ESP32-C5 tests (artifact 5)
│   │           │   └── integration.nix  # Integration tests (artifact 6)
│   │           └── docs/
│   │               ├── README.md        # Package docs (artifact 7)
│   │               └── migration.md     # Migration guide (artifact 8)
│   └── top-level/
│       └── all-packages.nix             # ← Update this (artifact 9)
└── .git/                                # Your existing git repo
```

## Branch Strategy

Given that ESP-IDF inspired your fetchTags feature and will benefit from it:

**Recommended approach:**
```bash
# Build on your fetchgit work since ESP-IDF needs it
git checkout -b esp-idf-init origin/fetchgit-fetchTags
```

**Why this makes sense:**
- ESP-IDF was the original motivation for fetchTags
- ESP-IDF likely needs proper git tag support for version detection
- You can demonstrate both improvements together
- After fetchgit merges, you can clean up any temporary references

## Setup Commands

```bash
# Navigate to your existing nixpkgs working tree
cd /path/to/your/nixpkgs

# Fetch latest upstream changes
git fetch upstream
git fetch origin

# Create new branch (choose based on strategy above)
git checkout -b esp-idf-init upstream/master

# Create ESP-IDF package directory structure
mkdir -p pkgs/development/embedded/esp-idf/{tests,docs}

# Download artifacts and place them:
# - default.nix → pkgs/development/embedded/esp-idf/default.nix
# - variants.nix → pkgs/development/embedded/esp-idf/variants.nix
# - shells.nix → pkgs/development/embedded/esp-idf/shells.nix
# - basic.nix → pkgs/development/embedded/esp-idf/tests/basic.nix
# - esp32c5.nix → pkgs/development/embedded/esp-idf/tests/esp32c5.nix
# - integration.nix → pkgs/development/embedded/esp-idf/tests/integration.nix
# - README.md → pkgs/development/embedded/esp-idf/docs/README.md
# - migration.md → pkgs/development/embedded/esp-idf/docs/migration.md

# Add entries to all-packages.nix (around line 15000 with embedded tools)
# See all-packages.nix artifact for exact entries

# Test the package
nix-build -A esp-idf

# Test ESP32-C5 variant
nix-build -A esp-idf --arg supportedTargets '["esp32c5"]' --arg enablePreviewTargets true --arg rev '"d930a386dae"'

# Run comprehensive tests
nixpkgs-review rev HEAD
```

## Integration with Your nixcfg

For your development workflow, you can either:

1. **Direct reference** (simplest):
   ```nix
   # In your flake.nix, use your local nixpkgs
   nixpkgs.url = "path:/path/to/your/nixpkgs";
   ```

2. **Overlay approach** (if you prefer separation):
   ```nix
   # In overlays/default.nix
   final: prev: {
     esp-idf = prev.callPackage /path/to/your/nixpkgs/pkgs/development/embedded/esp-idf { };
   }
   ```

This approach lets you develop and test directly in your nixpkgs fork, making the contribution process seamless!