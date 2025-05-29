# pkgs/development/embedded/esp-idf/tests/integration.nix - Real project integration tests
{ runCommand, esp-idf, fetchFromGitHub }:

let
  # Use ESP-IDF hello_world example for integration testing
  hello-world-src = runCommand "hello-world-example" {} ''
    mkdir -p $out
    cp -r ${esp-idf}/examples/get-started/hello_world/* $out/
    chmod -R +w $out
  '';
  
  esp-idf-c5 = esp-idf.override {
    supportedTargets = [ "esp32c5" ];
    enablePreviewTargets = true;
    rev = "d930a386dae";  
    sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM=";
  };
in runCommand "esp-idf-integration-tests" {
  buildInputs = [ esp-idf-c5 ];
} ''
  echo "Testing ESP-IDF integration with real project..."
  
  # Copy example project
  cp -r ${hello-world-src} ./hello_world
  cd hello_world
  chmod -R +w .
  
  # Test 1: Configure for ESP32-C5
  timeout 120s python3 $IDF_PATH/tools/idf.py --preview set-target esp32c5 || (echo "Failed to configure project" && exit 1)
  
  # Test 2: Project builds successfully (compilation test)
  # Note: This tests that headers are found and tools work
  timeout 300s python3 $IDF_PATH/tools/idf.py --preview build || (echo "Failed to build project" && exit 1)
  
  # Test 3: Build artifacts exist
  [ -f build/hello_world.bin ] || (echo "Binary not generated" && exit 1)
  [ -f build/bootloader/bootloader.bin ] || (echo "Bootloader not generated" && exit 1)
  
  # Test 4: Build size is reasonable (sanity check)
  size=$(stat -c%s build/hello_world.bin)
  [ "$size" -gt 1000 ] || (echo "Binary too small: $size bytes" && exit 1)
  [ "$size" -lt 10000000 ] || (echo "Binary too large: $size bytes" && exit 1)
  
  echo "✅ Integration tests passed"
  touch $out
''