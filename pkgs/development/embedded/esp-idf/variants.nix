# pkgs/development/embedded/esp-idf/variants.nix
# Target-specific ESP-IDF variants for convenience
{ callPackage }:

let
  esp-idf = callPackage ./default.nix { };
in
{
  # Full ESP-IDF with all stable targets
  esp-idf-full = esp-idf;
  
  # Individual target variants
  esp-idf-esp32 = esp-idf.override {
    supportedTargets = [ "esp32" ];
  };
  
  esp-idf-esp32s2 = esp-idf.override {
    supportedTargets = [ "esp32s2" ];
  };
  
  esp-idf-esp32s3 = esp-idf.override {
    supportedTargets = [ "esp32s3" ];
  };
  
  esp-idf-esp32c2 = esp-idf.override {
    supportedTargets = [ "esp32c2" ];
  };
  
  esp-idf-esp32c3 = esp-idf.override {
    supportedTargets = [ "esp32c3" ];
  };
  
  esp-idf-esp32c6 = esp-idf.override {
    supportedTargets = [ "esp32c6" ];
  };
  
  esp-idf-esp32h2 = esp-idf.override {
    supportedTargets = [ "esp32h2" ];
  };
  
  esp-idf-esp32p4 = esp-idf.override {
    supportedTargets = [ "esp32p4" ];
  };
  
  # ESP32-C5 with your working commit
  esp-idf-esp32c5 = esp-idf.override {
    supportedTargets = [ "esp32c5" ];
    enablePreviewTargets = true;
    rev = "d930a386dae";
    sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM=";
  };
  
  # RISC-V targets combined
  esp-idf-riscv = esp-idf.override {
    supportedTargets = [ "esp32c2" "esp32c3" "esp32c6" "esp32h2" ];
  };
  
  # RISC-V with preview (includes ESP32-C5)
  esp-idf-riscv-preview = esp-idf.override {
    supportedTargets = [ "esp32c2" "esp32c3" "esp32c6" "esp32h2" ];
    enablePreviewTargets = true;
    previewTargets = [ "esp32c5" ];
    rev = "d930a386dae";
    sha256 = "sha256-MIikNiUxR5+JkgD51wRokN+r8g559ejWfU4MP8zDwoM=";
  };
  
  # Xtensa targets 
  esp-idf-xtensa = esp-idf.override {
    supportedTargets = [ "esp32" "esp32s2" "esp32s3" "esp32p4" ];
  };

  # Inherit the base package
  inherit esp-idf;
}