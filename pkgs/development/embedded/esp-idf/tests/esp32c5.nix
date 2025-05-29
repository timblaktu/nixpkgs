# pkgs/development/embedded/esp-idf/tests/esp32c5.nix - ESP32-C5 specific tests  
{ runCommand, esp-idf }:

let
  esp-idf-c5 = esp-idf.override {
    supportedTargets = [ "esp32c5" ];
    enablePreviewTargets = true;
    rev = "d930a386dae";
    sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM=";
  };
in runCommand "esp-idf-esp32c5-tests" {
  buildInputs = [ esp-idf-c5 ];
} ''
  echo "Testing ESP32-C5 preview support..."
  
  cd $(mktemp -d)
  
  # Test 1: ESP32-C5 target available with --preview
  timeout 30s python3 $IDF_PATH/tools/idf.py --preview --list-targets > targets.txt || (echo "Failed to list preview targets" && exit 1)
  grep -q "esp32c5" targets.txt || (echo "ESP32-C5 target missing from preview targets" && exit 1)
  
  # Test 2: Can set ESP32-C5 target without errors
  echo 'cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(test)' > CMakeLists.txt
  
  mkdir main
  echo '#include <stdio.h>
void app_main(void) { printf("Hello ESP32-C5\\n"); }' > main/main.c
  echo 'idf_component_register(SRCS "main.c")' > main/CMakeLists.txt
  
  # Test 3: Set target succeeds
  timeout 60s python3 $IDF_PATH/tools/idf.py --preview set-target esp32c5 || (echo "Failed to set ESP32-C5 target" && exit 1)
  
  # Test 4: Configuration contains ESP32-C5 settings
  [ -f sdkconfig ] || (echo "sdkconfig not created" && exit 1)
  grep -q "CONFIG_IDF_TARGET=\"esp32c5\"" sdkconfig || (echo "ESP32-C5 not configured correctly" && exit 1)
  
  echo "✅ ESP32-C5 tests passed"
  touch $out
''