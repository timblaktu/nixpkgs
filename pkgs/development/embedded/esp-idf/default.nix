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
    # Use fetchTags for proper git tag support (requires fetchgit-fetchTags feature)
    fetchTags = true;
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
        # Fix: Use the bare SHA256 hash directly - Nix will auto-detect the format
        sha256 = downloadInfo.sha256;
        name = "${tool.name}-${versionInfo.name}";
      };
  }) requiredTools);

  # Python environment with ESP-IDF requirements
  # Install ESP-IDF Python dependencies from requirements files during build
  pythonEnv = python3.withPackages (ps: with ps; [
    # Core Python packages that ESP-IDF needs
    setuptools
    pip
    wheel
    # Basic dependencies available in nixpkgs
    click
    pyserial
    cryptography
    pyparsing
    pyelftools
    pyyaml
    future
    voluptuous
    jsonschema
    # Additional common packages
    requests
    packaging
  ]);

in stdenv.mkDerivation rec {
  pname = "esp-idf";
  version = if lib.hasPrefix "v" rev then lib.removePrefix "v" rev else rev;

  inherit src;

  nativeBuildInputs = [
    makeWrapper
    pythonEnv
    git
    cmake
    ninja
    pkg-config
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

    # Install ESP-IDF Python requirements
    echo "Installing ESP-IDF Python dependencies..."
    export PIP_DISABLE_PIP_VERSION_CHECK=1
    export PIP_NO_CACHE_DIR=1
    export PIP_ROOT_USER_ACTION=ignore
    
    # Install ESP-IDF Python packages to the python environment
    ${pythonEnv}/bin/python -m pip install --no-deps --target ${pythonEnv}/${pythonEnv.sitePackages} \
      -r tools/requirements/requirements.core.txt || true
    
    # Install ESP-IDF specific modules that aren't in nixpkgs
    ${pythonEnv}/bin/python -m pip install --no-deps --target ${pythonEnv}/${pythonEnv.sitePackages} \
      esp-idf-monitor esptool kconfiglib construct xmltodict pycparser reedsolo bitstring intelhex || true

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

    # Set up Python environment link
    ln -sf ${pythonEnv} $out/python-env

    # Create tool environment configuration
    mkdir -p $out/etc

    # Generate tool paths for all installed tools
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

    # Tag the commit to match expected version (only if tag doesn't exist)
    git tag "${rev}" HEAD 2>/dev/null || true
    if [ "${rev}" != "v${version}" ]; then
      git tag "v${version}" HEAD 2>/dev/null || true
    fi

    # Set up git safe directory configuration
    cat > $out/etc/gitconfig << 'EOF'
    [safe]
      directory = *
    EOF

    # Create environment setup script
    cat > $out/export.sh << 'EOF'
    #!/usr/bin/env bash
    # ESP-IDF Environment Setup Script

    export IDF_PATH="$( cd "$( dirname "''${BASH_SOURCE[0]}" )" && pwd )"
    export IDF_TOOLS_PATH="$IDF_PATH/.espressif"
    export IDF_PYTHON_ENV_PATH="$IDF_PATH/python-env"
    export IDF_PYTHON_CHECK_CONSTRAINTS=no

    # Load tool paths
    if [ -f "$IDF_PATH/etc/esp-idf-tool-env" ]; then
      source "$IDF_PATH/etc/esp-idf-tool-env"
    fi

    # Add ESP-IDF tools to PATH
    export PATH="$IDF_PATH/tools:$IDF_PYTHON_ENV_PATH/bin:$PATH"

    # Git configuration
    export GIT_CONFIG_SYSTEM="$IDF_PATH/etc/gitconfig"

    # Python path
    export PYTHONPATH="$IDF_PYTHON_ENV_PATH/lib/python${pythonEnv.pythonVersion}/site-packages''${PYTHONPATH:+:$PYTHONPATH}"

    echo "ESP-IDF environment configured for: ${lib.concatStringsSep ", " allTargets}"
    ${lib.optionalString enablePreviewTargets ''
      echo "Preview targets enabled: ${lib.concatStringsSep ", " previewTargets}"
      echo "Note: Use 'idf.py --preview' for preview target commands"
    ''}
    EOF

    chmod +x $out/export.sh

    runHook postInstall
  '';

  # Setup hook for automatic environment configuration
  setupHook = writeText "esp-idf-setup-hook" ''
    addEspIdfVars() {
      if [ -e "$1/tools/idf.py" ]; then
        export IDF_PATH="$1"
        export IDF_TOOLS_PATH="$IDF_PATH/.espressif"
        export IDF_PYTHON_ENV_PATH="$IDF_PATH/python-env"
        export IDF_PYTHON_CHECK_CONSTRAINTS=no

        # Add tools to PATH
        if [ -e "$IDF_PATH/etc/esp-idf-tool-env" ]; then
          source "$IDF_PATH/etc/esp-idf-tool-env"
        fi

        addToSearchPath PATH "$IDF_PATH/tools"
        addToSearchPath PATH "$IDF_PYTHON_ENV_PATH/bin"

        # Git configuration
        export GIT_CONFIG_SYSTEM="$IDF_PATH/etc/gitconfig"

        # Python environment
        addToSearchPath PYTHONPATH "$IDF_PYTHON_ENV_PATH/lib/python${pythonEnv.pythonVersion}/site-packages"
      fi
    }

    addEnvHooks "$hostOffset" addEspIdfVars
  '';

  passthru = {
    inherit pythonEnv toolDerivations supportedTargets;
    enabledTargets = allTargets;

    # Provide target-specific variants
    withTargets = targets: (import ./default.nix).override { supportedTargets = targets; };
    withPreview = (import ./default.nix).override { enablePreviewTargets = true; };

    # Common variants
    esp32 = (import ./default.nix).override { supportedTargets = [ "esp32" ]; };
    esp32c5 = (import ./default.nix).override {
      supportedTargets = [ "esp32c5" ];
      enablePreviewTargets = true;
      # Use your working commit for ESP32-C5
      rev = "d930a386dae";
      sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM=";
    };

    # Built-in tests
    tests = {
      basic = import ./tests/basic.nix { inherit lib stdenv; esp-idf = stdenv.mkDerivation {}; };
      esp32c5 = import ./tests/esp32c5.nix { inherit lib stdenv; esp-idf = stdenv.mkDerivation {}; };
      integration = import ./tests/integration.nix { inherit lib stdenv; esp-idf = stdenv.mkDerivation {}; };
    };
  };

  meta = with lib; {
    description = "Espressif IoT Development Framework";
    longDescription = ''
      ESP-IDF is the official development framework for the ESP32, ESP32-S and ESP32-C
      series of SoCs from Espressif Systems. It provides a rich set of APIs and tools
      for developing applications for these microcontrollers.

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
