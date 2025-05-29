# pkgs/development/embedded/esp-idf/esp-idf-python-modules.nix
# ESP-IDF Python modules as proper Nix packages
{ lib, buildPythonPackage, esp-idf-src }:

{
  # ESP-IDF Monitor tool
  esp-idf-monitor = buildPythonPackage {
    pname = "esp-idf-monitor";
    version = "1.0.0";

    src = esp-idf-src;

    # Only include the monitor tool
    postUnpack = ''
      sourceRoot="$sourceRoot/tools"
    '';

    # Create minimal setup.py for the monitor
    preBuild = ''
      cat > setup.py << 'EOF'
from setuptools import setup

setup(
    name="esp-idf-monitor",
    version="1.0.0",
    py_modules=["idf_monitor"],
    entry_points={
        "console_scripts": [
            "esp_idf_monitor=idf_monitor:main",
        ],
    },
)
EOF
    '';

    # Don't run tests
    doCheck = false;

    # Make importable as esp_idf_monitor
    postInstall = ''
      # Create alias module for import compatibility
      cat > $out/lib/python*/site-packages/esp_idf_monitor.py << 'EOF'
# Compatibility module for ESP-IDF
from idf_monitor import *
EOF
    '';

    meta = {
      description = "ESP-IDF Serial Monitor Tool";
      license = lib.licenses.asl20;
    };
  };

  # ESP-IDF Tools module
  esp-idf-tools = buildPythonPackage {
    pname = "esp-idf-tools";
    version = "1.0.0";

    src = esp-idf-src;

    # Include the entire tools directory
    postUnpack = ''
      sourceRoot="$sourceRoot/tools"
    '';

    # Create setup.py that includes all tool modules
    preBuild = ''
      cat > setup.py << 'EOF'
from setuptools import setup, find_packages
import os

# Find all .py files in tools directory
py_modules = []
for root, dirs, files in os.walk('.'):
    for file in files:
        if file.endswith('.py') and file != 'setup.py':
            module = os.path.splitext(file)[0]
            py_modules.append(module)

setup(
    name="esp-idf-tools",
    version="1.0.0",
    py_modules=py_modules,
    packages=find_packages(),
    package_data={"": ["**/*.json", "**/*.txt", "**/*.yaml"]},
    include_package_data=True,
)
EOF
    '';

    # Don't run tests
    doCheck = false;

    meta = {
      description = "ESP-IDF Tools Python Modules";
      license = lib.licenses.asl20;
    };
  };
}
