# Automatic writer selection based on file type detection
{ lib, pkgs, writers }:

let
  inherit (lib) fileTypes;
  inherit (lib.fileTypes) removeExtension;

  # Extract script name from path for writer functions
  # "/bin/script.py" -> "script"
  # "myscript.sh" -> "myscript"
  extractScriptName = path:
    removeExtension (builtins.baseNameOf (toString path));

in
rec {
  /**
    Automatically select and apply the appropriate writer based on file characteristics.
    
    This function combines lib.fileTypes detection with nixpkgs writers to provide
    seamless automatic script creation with validation.
    
    # Inputs
    
    `path` (String or Path)
    : The target path or filename for the script. Used for both file type detection
      and determining the output location.
    
    `content` (String)  
    : The script content/source code. Used for shebang-based file type detection.
    
    `deps` (Optional, List, Default: [])
    : Dependencies for the script. Only used by writers that support dependencies
      (e.g., Python, Rust, Haskell). Ignored by simple writers like writeBash.
    
    `options` (Optional, AttrSet, Default: {})
    : Additional options passed to the underlying writer. Different writers accept
      different options:
      - Python: { doCheck = false; flakeIgnore = ["E501"]; }
      - Rust: { rustcArgs = ["-O"]; strip = true; }
      - Bash: { makeWrapperArgs = ["--set" "VAR" "value"]; }
    
    # Examples
    
    :::{.example}
    ## Basic usage with file extension detection
    
    ```nix
    # Automatically detects Python from .py extension
    myPythonScript = autoWriter {
      path = "bin/hello.py";
      content = ''
        #!/usr/bin/env python3
        print("Hello from auto-detected Python!")
      '';
      deps = [ python3Packages.requests ];
    };
    ```
    :::
    
    :::{.example}
    ## Shebang-based detection overrides extension
    
    ```nix  
    # Detects Bash from shebang despite .sh.py extension
    bashScript = autoWriter {
      path = "weird-script.sh.py";
      content = ''
        #!/bin/bash
        echo "This is actually a bash script"
      '';
    };
    ```
    :::
    
    :::{.example}
    ## Passing writer-specific options
    
    ```nix
    rustProgram = autoWriter {
      path = "bin/fast-tool.rs";
      content = ''
        fn main() {
            println!("Optimized Rust program");
        }
      '';
      options = { rustcArgs = ["-O"]; };
    };
    ```
    :::
  */
  autoWriter =
    { path
    , content
    , deps ? [ ]
    , options ? { }
    ,
    }:
    let
      # Detect the appropriate writer type
      writerType = fileTypes.getWriterType path content;

      # Extract base name for the script
      scriptName = extractScriptName path;

      # Get the writer function
      writer = writers.${writerType} or pkgs.writeText;

      # Handle different writer signatures
      callWriter = writerType: writer: scriptName: content: deps: options:
        if writerType == "writeText" then
        # writeText: name -> content  (from pkgs, not writers)
          pkgs.writeText scriptName content

        else if writerType == "writePython3" then
        # Python writers: name -> { deps, options... } -> content
          writer scriptName (options // { libraries = deps; }) content

        else if writerType == "writeRust" then
        # Rust writer: name -> { options... } -> content (deps ignored)
          writer scriptName options content

        else if writerType == "writeHaskell" then
        # Haskell writer: name -> { deps, options... } -> content  
          writer scriptName (options // { libraries = deps; }) content

        else if lib.hasPrefix "write" writerType then
        # Most script writers: name -> content or name -> options -> content
          if options == { } then
            writer scriptName content
          else
            writer scriptName options content

        else
        # Fallback to writeText for unrecognized types
          pkgs.writeText scriptName content;

    in
    callWriter writerType writer scriptName content deps options;

  /**
    Like autoWriter but creates an executable in /bin/ subdirectory.
    
    This is equivalent to autoWriter but ensures the output goes to $out/bin/name
    making it suitable for use with PATH.
    
    # Example
    
    ```nix
    myTool = autoWriterBin {
      name = "my-tool";
      content = ''
        #!/usr/bin/env python3
        print("This tool is in PATH")
      '';
    };
    ```
  */
  autoWriterBin =
    { name
    , content
    , deps ? [ ]
    , options ? { }
    ,
    }:
    let
      # Detect the appropriate writer type
      writerType = fileTypes.getWriterType name content;

      # Convert to Bin variant (writeBash -> writeBashBin)
      binWriterType =
        if lib.hasPrefix "write" writerType && writerType != "writeText"
        then "${writerType}Bin"
        else "writeTextFile";

      # Get the writer function
      writer = writers.${binWriterType} or (
        if binWriterType == "writeTextFile"
        then pkgs.writeTextFile
        else writers.writeTextFile
      );

      # Handle different writer signatures for bin variants
      callBinWriter = binWriterType: writer: name: content: deps: options:
        if binWriterType == "writeTextFile" then
        # writeTextFile with executable option
          writer
            {
              name = name;
              text = content;
              executable = true;
            }

        else if binWriterType == "writePython3Bin" then
        # Python bin writers: name -> { deps, options... } -> content
          writer name (options // { libraries = deps; }) content

        else if binWriterType == "writeRustBin" then
        # Rust bin writer: name -> { options... } -> content (deps ignored)
          writer name options content

        else if binWriterType == "writeHaskellBin" then
        # Haskell bin writer: name -> { deps, options... } -> content  
          writer name (options // { libraries = deps; }) content

        else if lib.hasPrefix "write" binWriterType && lib.hasSuffix "Bin" binWriterType then
        # Most script bin writers: name -> content or name -> options -> content
          if options == { } then
            writer name content
          else
            writer name options content

        else
        # Fallback to writeTextFile with executable
          pkgs.writeTextFile {
            name = name;
            text = content;
            executable = true;
          };

    in
    callBinWriter binWriterType writer name content deps options;

  /**
    Debug helper to show what writer would be selected for given file characteristics.
    
    Useful for understanding and troubleshooting autoWriter behavior.
    
    # Example
    
    ```nix
    builtins.trace (debugAutoWriter "script.py" "#!/usr/bin/env python3\nprint('test')")
    # Shows: { path = "script.py"; detectedType = "writePython3"; ... }
    ```
  */
  debugAutoWriter = path: content:
    let
      writerType = fileTypes.getWriterType path content;
      scriptName = extractScriptName path;
    in
    {
      inherit path content;
      detectedType = writerType;
      scriptName = scriptName;
      hasWriter = builtins.hasAttr writerType writers;
      debugInfo = fileTypes.debugDetection path content;
    };
}
