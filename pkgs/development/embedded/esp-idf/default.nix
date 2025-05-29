# pkgs/development/embedded/esp-idf/default.nix
{ lib
, stdenv
, fetchFromGitHub
, fetchurl
, python3
, git
, cmake
, ninja
, pkg-config
, makeWrapper
, writeText
, runCommand
, buildPackages

# Build tools that ESP-IDF needs
, gnumake
, flex
, bison
, gperf
, ncurses5
, dfu-util
, wget

# Configuration options
, rev ? "v5.4.1"
, sha256 ? "sha256-UiocEqfLYlrFGBGszscFj/RzGrpVbi5YcT2sVkVhViw="
, supportedTargets ? [ "esp32" "esp32s2" "esp32s3" "esp32c2" "esp32c3" "esp32c6" "esp32h2" "esp32p4" ]
, enablePreviewTargets ? false  # Set to true for ESP32-C5
, previewTargets ? [ "esp32c5" ]
}:

let
  # Determine which targets to actually support
  allTargets = supportedTargets ++ (lib.optionals enablePreviewTargets previewTargets);

  # ESP-IDF source
  src = fetchFromGitHub {
    owner = "espressif";
    repo = "esp-idf";
    inherit rev sha256;
    fetchSubmodules = true;
    fetchTags = true;  # Your approved feature - essential for ESP-IDF version detection
  };

  # Parse tools.json to get all required tools for our targets
  toolsJson = builtins.fromJSON (builtins.readFile "${src}/tools/tools.json");

  # Determine platform key for downloads
  platformKey = if stdenv.isLinux then
    (if stdenv.isx86_64 then "linux-amd64"
     else if stdenv.isAarch64 then "linux-arm64"
     else throw "Unsupported Linux architecture")
  else if stdenv.isDarwin then
    (if stdenv.isx86_64 then "macos"
     else if stdenv.isAarch64 then "macos-arm64"
     else "macos")
  else throw "Unsupported platform";

  # Filter tools that both: 1) we need for our targets, 2) have our platform
  requiredTools = builtins.filter (tool:
    let
      versionInfo = builtins.head tool.versions;
      hasOurPlatform = builtins.hasAttr platformKey versionInfo;
    in
      hasOurPlatform && (
      # Include tool if any of our targets need it
      builtins.any (target:
        # Check if target is in supported_targets (handle both attrset and list formats)
        (if builtins.isAttrs (tool.supported_targets or {})
         then builtins.hasAttr target (tool.supported_targets or {})
         else builtins.elem target (tool.supported_targets or [])) ||
        # For RISC-V targets (ESP32-C series) - include riscv tools
        (lib.hasInfix "riscv" tool.name) ||
        (lib.hasInfix "esp32c" tool.name) ||
        (builtins.hasAttr "riscv32" tool)
      ) allTargets)
  ) toolsJson.tools;

  # Pre-fetch all required tools for offline installation
  toolDerivations = builtins.listToAttrs (builtins.map (tool: {
    name = tool.name;
    value = let
      # tool.versions is a list, get the first/recommended version
      versionInfo = builtins.head tool.versions;

      # versionInfo has platform-specific download info as attributes
      downloadInfo = versionInfo.${platformKey};
    in
      fetchurl {
        url = downloadInfo.url;
        sha256 = downloadInfo.sha256;
        name = "${tool.name}-${versionInfo.name}";
      };
  }) requiredTools);

  # Dynamic Python package discovery - read ESP-IDF's actual requirements
  # This makes the package resilient to ESP-IDF changes
  espIdfRequirementsCore = builtins.readFile "${src}/tools/requirements/requirements.core.txt";

  # Parse requirements.txt to extract package names (simple approach)
  # This could be made more sophisticated if needed
  extractPackageNames = requirements:
    let
      lines = lib.splitString "\n" requirements;
      nonEmptyLines = builtins.filter (line: line != "" && !(lib.hasPrefix "#" line)) lines;
      packageNames = builtins.map (line:
        let
          # Extract package name before any version specifiers (>=, ==, etc.)
          parts = lib.splitString ">=" line;
          firstPart = builtins.head parts;
          parts2 = lib.splitString "==" firstPart;
          packageName = builtins.head parts2;
        in
          lib.toLower (lib.replaceStrings ["_"] ["-"] packageName)
      ) nonEmptyLines;
    in
      packageNames;

  requiredPythonPackages = extractPackageNames espIdfRequirementsCore;

  # ESP-IDF Python modules as proper Nix packages
  espIdfPythonModules = python3.pkgs.callPackage ./python-modules.nix {
    esp-idf-src = src;
  };

  # Create isolated Python environment for ESP-IDF with proper ESP-IDF modules
  espIdfPythonEnv = python3.withPackages (ps:
    let
      # Get available packages that match ESP-IDF requirements
      availablePackages = builtins.filter (pkgName:
        builtins.hasAttr pkgName ps
      ) requiredPythonPackages;

      # Convert package names to actual package objects
      packages = builtins.map (pkgName: builtins.getAttr pkgName ps) availablePackages;
    in
      # Include ESP-IDF's own Python modules as proper packages
      packages ++ [
        espIdfPythonModules.esp-idf-monitor
        espIdfPythonModules.esp-idf-tools
      ] ++ (with ps; [
        setuptools
        pip
        wheel
        # Fallback essential packages that ESP-IDF always needs
        click
        pyserial
        cryptography
        pyparsing
        pyelftools
        pyyaml
        future
        voluptuous
        jsonschema
        requests
        packaging
      ])
  );

in stdenv.mkDerivation rec {
  pname = "esp-idf";
  version = if lib.hasPrefix "v" rev then lib.removePrefix "v" rev else rev;

  inherit src;

  # Note: pythonEnv is NOT in nativeBuildInputs - no Python exposed to shell
  nativeBuildInputs = [
    makeWrapper
    git
    cmake
    ninja
    pkg-config
    # espIdfPythonEnv is used internally but not exposed to users
  ];

  buildInputs = [
    gnumake
    flex
    bison
    gperf
    ncurses5
    dfu-util
    wget
  ] ++ lib.optionals stdenv.isLinux [
    # Linux-specific dependencies
  ];

  # Prevent network access during build while allowing tool installation
  __impureHostDeps = lib.optionals stdenv.isDarwin [
    "/usr/bin/xcode-select"
  ];

  configurePhase = ''
    runHook preConfigure

    # Set up the environment for ESP-IDF installation
    export HOME=$(mktemp -d)
    export IDF_TOOLS_PATH=$out/.espressif

    # Prepare tools directory structure
    mkdir -p $IDF_TOOLS_PATH/tools

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    echo "Preparing ESP-IDF tools for targets: ${lib.concatStringsSep " " allTargets}"

    # Pre-install fetched tools to simulate offline install.sh behavior
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: toolDrv: ''
      echo "Installing ${name}..."
      toolDir="$IDF_TOOLS_PATH/tools/${name}"
      mkdir -p "$toolDir"

      # Extract tool (handle both .tar.gz and .zip archives)
      cd "$toolDir"
      if [[ "${toolDrv}" == *.tar.gz ]] || [[ "${toolDrv}" == *.tgz ]]; then
        tar --strip-components=1 -xzf "${toolDrv}"
      elif [[ "${toolDrv}" == *.tar.xz ]]; then
        tar --strip-components=1 -xJf "${toolDrv}"
      elif [[ "${toolDrv}" == *.zip ]]; then
        ${buildPackages.unzip}/bin/unzip "${toolDrv}"
        # For zip files, move contents up one level if needed
        if [ -d * ] && [ $(echo */ | wc -w) = 1 ]; then
          mv */* . 2>/dev/null && rmdir */ 2>/dev/null || true
        fi
      fi
      cd -
    '') toolDerivations)}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Copy ESP-IDF source to output
    mkdir -p $out
    cp -r . $out/
    cd $out

    # Create the exact Python virtual environment structure that ESP-IDF expects
    # This mimics what ESP-IDF's install.sh creates
    mkdir -p $out/.espressif/python_env

    # Create the specific venv directory name ESP-IDF expects
    pythonVersion="${espIdfPythonEnv.pythonVersion}"
    venvDir="idf${version}_py''${pythonVersion}_env"
    mkdir -p "$out/.espressif/python_env/$venvDir"

    # Install the Python environment into ESP-IDF's expected location
    # This creates a complete Python environment in the nix store with ESP-IDF modules
    cp -rL ${espIdfPythonEnv}/* "$out/.espressif/python_env/$venvDir/"

    # Create the standard symlink for compatibility
    ln -sf "$out/.espressif/python_env/$venvDir" $out/python-env

    # Ensure ESP-IDF's tools directory can be used as Python modules
    # ESP-IDF's idf.py expects to import modules from the tools directory
    touch $out/tools/__init__.py

    # Set up tool environment configuration
    mkdir -p $out/etc
    cat > $out/etc/esp-idf-tool-env << 'EOF'
    # ESP-IDF Tool Environment Configuration
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _: ''
      export PATH="$IDF_TOOLS_PATH/tools/${name}/bin:$PATH"
    '') toolDerivations)}
    EOF

    # Create git repository structure (ESP-IDF expects this)
    git init .
    git config user.email "nixbld@localhost"
    git config user.name "nixbld"
    git add -A
    git commit --allow-empty -m "ESP-IDF ${version} for Nix"

    # Tag the commit to match expected version (essential for git describe)
    git tag "${rev}" HEAD 2>/dev/null || true
    if [ "${rev}" != "v${version}" ]; then
      git tag "v${version}" HEAD 2>/dev/null || true
    fi

    # Set up git safe directory configuration
    cat > $out/etc/gitconfig << 'EOF'
    [safe]
      directory = *
    EOF

    # Create environment setup script that matches ESP-IDF's export.sh
    cat > $out/export.sh << 'EOF'
    #!/usr/bin/env bash
    # ESP-IDF Environment Setup Script

    export IDF_PATH="$( cd "$( dirname "''${BASH_SOURCE[0]}" )" && pwd )"
    export IDF_TOOLS_PATH="$IDF_PATH/.espressif"

    # Set Python environment path to the pre-built environment in nix store
    pythonVersion="${espIdfPythonEnv.pythonVersion}"
    venvDir="idf${version}_py''${pythonVersion}_env"
    export IDF_PYTHON_ENV_PATH="$IDF_TOOLS_PATH/python_env/$venvDir"
    export IDF_PYTHON_CHECK_CONSTRAINTS=no

    # Load tool paths
    if [ -f "$IDF_PATH/etc/esp-idf-tool-env" ]; then
      source "$IDF_PATH/etc/esp-idf-tool-env"
    fi

    # Add ESP-IDF tools to PATH (but NOT python - idf.py handles that)
    export PATH="$IDF_PATH/tools:$PATH"

    # Git configuration
    export GIT_CONFIG_SYSTEM="$IDF_PATH/etc/gitconfig"

    # Add ESP-IDF tools directory to Python path for module imports
    export PYTHONPATH="$IDF_PATH/tools''${PYTHONPATH:+:$PYTHONPATH}"

    echo "ESP-IDF environment configured for: ${lib.concatStringsSep ", " allTargets}"
    ${lib.optionalString enablePreviewTargets ''
      echo "Preview targets enabled: ${lib.concatStringsSep ", " previewTargets}"
      echo "Note: Use 'idf.py --preview' for preview target commands"
    ''}
    echo "Python environment: $IDF_PYTHON_ENV_PATH"
    echo "Use 'idf.py' commands - no direct Python access needed"
    EOF

    chmod +x $out/export.sh

    runHook postInstall
  '';

  # Setup hook that provides ESP-IDF environment but NO external Python
  setupHook = writeText "esp-idf-setup-hook" ''
    addEspIdfVars() {
      if [ -e "$1/tools/idf.py" ]; then
        export IDF_PATH="$1"
        export IDF_TOOLS_PATH="$IDF_PATH/.espressif"

        # Set Python environment to pre-built nix store location
        pythonVersion="${espIdfPythonEnv.pythonVersion}"
        venvDir="idf''${version}_py''${pythonVersion}_env"
        export IDF_PYTHON_ENV_PATH="$IDF_TOOLS_PATH/python_env/$venvDir"
        export IDF_PYTHON_CHECK_CONSTRAINTS=no

        # Load tool paths
        if [ -e "$IDF_PATH/etc/esp-idf-tool-env" ]; then
          source "$IDF_PATH/etc/esp-idf-tool-env"
        fi

        # Add ESP-IDF tools to PATH (but NOT Python)
        addToSearchPath PATH "$IDF_PATH/tools"

        # Git configuration
        export GIT_CONFIG_SYSTEM="$IDF_PATH/etc/gitconfig"

        # Add ESP-IDF tools directory to Python path for ESP-IDF's module imports
        addToSearchPath PYTHONPATH "$IDF_PATH/tools"

        # Expose python (binary and venv) from esp-idf package to the shell
        # in case user wants python outside of idf.py. This simplifies the package
        # considerably and aligns with the primary use case which is dev shells.
        addToSearchPath PATH "$IDF_PYTHON_ENV_PATH/bin"
      fi
    }

    addEnvHooks "$hostOffset" addEspIdfVars

  '';

  passthru = {
    inherit espIdfPythonEnv toolDerivations supportedTargets;
    enabledTargets = allTargets;

    # Built-in tests
    #tests = {
    #  basic = runCommand "esp-idf-basic-test" { buildInputs = [ (callPackage ./default.nix {}) ]; } (builtins.readFile ./tests/basic.nix);
    #  esp32c5 = runCommand "esp-idf-esp32c5-test" {
    #    buildInputs = [ (callPackage ./default.nix { supportedTargets = [ "esp32c5" ]; enablePreviewTargets = true; rev = "d930a386dae"; sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM="; }) ];
    #  } (builtins.readFile ./tests/esp32c5.nix);
    #  integration = callPackage ./tests/integration.nix {};
    #};

    # Provide target-specific variants
    withTargets = targets: (import ./default.nix).override { supportedTargets = targets; };
    withPreview = (import ./default.nix).override { enablePreviewTargets = true; };

    # Common variants
    esp32 = (import ./default.nix).override { supportedTargets = [ "esp32" ]; };
    esp32c5 = (import ./default.nix).override {
      supportedTargets = [ "esp32c5" ];
      enablePreviewTargets = true;
      rev = "d930a386dae";
      sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM=";
    };
  };

  meta = with lib; {
    description = "Espressif IoT Development Framework";
    longDescription = ''
      ESP-IDF is the official development framework for the ESP32, ESP32-S and ESP32-C
      series of SoCs from Espressif Systems. It provides a rich set of APIs and tools
      for developing applications for these microcontrollers.

      This package provides an isolated ESP-IDF environment. Use 'idf.py' commands
      for all ESP-IDF operations - no direct Python access is provided.

      Supported targets: ${lib.concatStringsSep ", " allTargets}
      ${lib.optionalString enablePreviewTargets "Preview targets: ${lib.concatStringsSep ", " previewTargets}"}
    '';
    homepage = "https://github.com/espressif/esp-idf";
    license = licenses.asl20;
    maintainers = with maintainers; [ ]; # Add your maintainer info
    platforms = platforms.linux ++ platforms.darwin;

    # Mark as broken if trying to use preview targets without flag
    broken = builtins.any (target: lib.elem target previewTargets) supportedTargets && !enablePreviewTargets;
  };
}
