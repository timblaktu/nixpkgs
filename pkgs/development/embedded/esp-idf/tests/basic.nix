# pkgs/development/embedded/esp-idf/tests/basic.nix - Basic functionality tests
{ runCommand, esp-idf }:

runCommand "esp-idf-basic-tests" {
  buildInputs = [ esp-idf ];
} ''
  echo "Testing ESP-IDF basic functionality..."
  
  # Test 1: IDF_PATH is set correctly
  [ -n "$IDF_PATH" ] || (echo "IDF_PATH not set" && exit 1)
  [ -d "$IDF_PATH" ] || (echo "IDF_PATH not a directory" && exit 1)
  
  # Test 2: idf.py exists and is executable
  [ -x "$IDF_PATH/tools/idf.py" ] || (echo "idf.py not found or not executable" && exit 1)
  
  # Test 3: Python environment is properly set up
  [ -n "$IDF_PYTHON_ENV_PATH" ] || (echo "Python env not configured" && exit 1)
  [ -d "$IDF_PYTHON_ENV_PATH" ] || (echo "Python env directory missing" && exit 1)
  
  # Test 4: Required tools are in PATH
  command -v python3 >/dev/null || (echo "Python not in PATH" && exit 1)
  
  # Test 5: Can list targets without errors
  cd $(mktemp -d)
  timeout 30s python3 $IDF_PATH/tools/idf.py --list-targets > targets.txt || (echo "Failed to list targets" && exit 1)
  
  # Test 6: Expected stable targets are present
  grep -q "esp32" targets.txt || (echo "ESP32 target missing" && exit 1)
  grep -q "esp32c3" targets.txt || (echo "ESP32-C3 target missing" && exit 1)
  grep -q "esp32c6" targets.txt || (echo "ESP32-C6 target missing" && exit 1)
  
  echo "✅ Basic tests passed"
  touch $out
''