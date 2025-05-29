# pkgs/development/embedded/esp-idf/shells.nix  
# Development shells for ESP-IDF projects
{ pkgs }:

let
  esp-idf-variants = pkgs.callPackage ./variants.nix { };
  
  # Common development tools for ESP projects
  commonDevTools = with pkgs; [
    # Serial communication
    minicom
    picocom
    screen
    
    # Development utilities  
    git
    gnumake
    cmake
    ninja
    
    # Debugging and analysis
    gdb
    openocd
    
    # File utilities
    unzip
    which
  ];
  
  # Create a development shell for a specific ESP-IDF variant
  mkEspShell = { esp-idf-pkg, name, extraPackages ? [ ], shellHook ? "" }: 
    pkgs.mkShell {
      inherit name;
      
      buildInputs = [ esp-idf-pkg ] ++ commonDevTools ++ extraPackages;
      
      shellHook = ''
        echo "╭────────────────────────────────────────────────────────────╮"
        echo "│ ESP-IDF Development Shell: ${name}"
        echo "│ Targets: ${pkgs.lib.concatStringsSep ", " esp-idf-pkg.enabledTargets}"
        echo "│ ESP-IDF Path: $IDF_PATH" 
        echo "│ Tools Path: $IDF_TOOLS_PATH"
        echo "╰────────────────────────────────────────────────────────────╯"
        echo ""
        
        # Source ESP-IDF environment if export.sh exists
        if [ -f "$IDF_PATH/export.sh" ]; then
          echo "Sourcing ESP-IDF environment..."
          source "$IDF_PATH/export.sh"
        fi
        
        echo "Available commands:"
        echo "  idf.py    - ESP-IDF build system"
        echo "  esptool   - Flash utility"  
        echo "  monitor   - Serial monitor"
        echo ""
        
        ${shellHook}
      '';