# File type detection utilities for automatic writer selection
{ lib }:

let
  inherit (lib)
    hasPrefix
    hasSuffix
    removeSuffix
    replaceStrings
    splitString
    head
    tail
    optional
    last
    stringLength
    substring;

  # Extract file extension from path (including the dot)
  # Examples: "/path/to/file.py" -> ".py", "script.sh" -> ".sh", "noext" -> ""
  fileExtension = path:
    let
      basename = builtins.baseNameOf (toString path);
      parts = splitString "." basename;
    in
    if builtins.length parts <= 1
    then ""
    else ".${last parts}";

  # Remove file extension from basename
  # Examples: "script.py" -> "script", "file.tar.gz" -> "file.tar"
  removeExtension = path:
    let
      basename = builtins.baseNameOf (toString path);
      ext = fileExtension path;
    in
    if ext == ""
    then basename
    else removeSuffix ext basename;

in
rec {
  inherit fileExtension removeExtension;

  # Map file extensions to writer function names
  # This should match the available writers in pkgs.writers
  extensionToWriterMap = {
    # Shell scripts - using writeBash, writeDash, writeFish
    ".sh" = "writeBash";
    ".bash" = "writeBash";
    ".dash" = "writeDash";
    ".fish" = "writeFish";

    # Scripting languages - using writePython3, writeRuby, etc.
    ".py" = "writePython3";
    ".python" = "writePython3";
    ".rb" = "writeRuby";
    ".ruby" = "writeRuby";
    ".js" = "writeJS";
    ".javascript" = "writeJS";
    ".lua" = "writeLua";
    ".nu" = "writeNu";
    ".pl" = "writePerl";
    ".perl" = "writePerl";

    # Compiled languages
    ".rs" = "writeRust";
    ".rust" = "writeRust";
    ".hs" = "writeHaskell";
    ".haskell" = "writeHaskell";
    ".nim" = "writeNim";
    ".fs" = "writeFSharp";
    ".fsx" = "writeFSharp";
    ".fsharp" = "writeFSharp";

    # Functional/specialized languages
    ".scm" = "writeGuile";
    ".guile" = "writeGuile";
    ".clj" = "writeBabashka";
    ".cljs" = "writeBabashka";
    ".bb" = "writeBabashka";

    # Configuration files (treated as text)
    ".conf" = "writeText";
    ".config" = "writeText";
    ".ini" = "writeText";
    ".txt" = "writeText";
    ".md" = "writeText";
    ".rst" = "writeText";
  };

  # Common shebang patterns mapped to writer types
  # These patterns are checked as prefixes of the first line
  shebangToWriterMap = {
    "#!/usr/bin/env bash" = "writeBash";
    "#!/bin/bash" = "writeBash";
    "#!/usr/bin/bash" = "writeBash";
    "#!/usr/bin/env sh" = "writeBash"; # sh is compatible with bash writer
    "#!/bin/sh" = "writeBash";

    "#!/usr/bin/env dash" = "writeDash";
    "#!/bin/dash" = "writeDash";

    "#!/usr/bin/env fish" = "writeFish";
    "#!/bin/fish" = "writeFish";

    "#!/usr/bin/env python" = "writePython3";
    "#!/usr/bin/env python3" = "writePython3";
    "#!/usr/bin/python" = "writePython3";
    "#!/usr/bin/python3" = "writePython3";

    "#!/usr/bin/env ruby" = "writeRuby";
    "#!/usr/bin/ruby" = "writeRuby";

    "#!/usr/bin/env node" = "writeJS";
    "#!/usr/bin/node" = "writeJS";

    "#!/usr/bin/env lua" = "writeLua";
    "#!/usr/bin/lua" = "writeLua";

    "#!/usr/bin/env nu" = "writeNu";
    "#!/usr/bin/nu" = "writeNu";

    "#!/usr/bin/env perl" = "writePerl";
    "#!/usr/bin/perl" = "writePerl";

    "#!/usr/bin/env runhaskell" = "writeHaskell";
    "#!/usr/bin/runhaskell" = "writeHaskell";

    "#!/usr/bin/env nim" = "writeNim";
    "#!/usr/bin/nim" = "writeNim";

    "#!/usr/bin/env guile" = "writeGuile";
    "#!/usr/bin/guile" = "writeGuile";

    "#!/usr/bin/env bb" = "writeBabashka";
    "#!/usr/bin/bb" = "writeBabashka";
  };

  # Detect file type from extension
  # Returns writer type string or null if no match
  detectByExtension = path:
    let ext = fileExtension path;
    in extensionToWriterMap.${ext} or null;

  # Detect file type from shebang line
  # Takes the content string and checks the first line
  # Returns writer type string or null if no match
  detectByShebang = content:
    let
      lines = splitString "\n" content;
      firstLine = if builtins.length lines > 0 then head lines else "";

      # Find the first shebang pattern that matches as a prefix
      matchingShebang = builtins.head (
        builtins.filter
          (shebang: hasPrefix shebang firstLine)
          (builtins.attrNames shebangToWriterMap)
      );
    in
    if builtins.length
      (
        builtins.filter
          (shebang: hasPrefix shebang firstLine)
          (builtins.attrNames shebangToWriterMap)
      ) > 0
    then shebangToWriterMap.${matchingShebang}
    else null;

  # Combined file type detection with priority-based strategy
  # Priority: 1. Shebang (if content provided), 2. Extension, 3. Default fallback
  # Returns: writer type string, defaults to "text" if no detection possible
  detectFileType = path: content:
    let
      shebangType =
        if content != null && content != ""
        then detectByShebang content
        else null;
      extensionType = detectByExtension path;
      defaultType = "writeText";
    in
    if shebangType != null
    then shebangType
    else if extensionType != null
    then extensionType
    else defaultType;

  # Convenience function: detect from path only (no content analysis)
  detectFileTypeFromPath = path: detectFileType path "";

  # Get appropriate writer function name for automatic script creation
  # This is what will be used to look up writers.${writerType}
  getWriterType = path: content: detectFileType path content;

  # Utility to check if a path has executable characteristics
  # Based on extension or common executable patterns
  looksExecutable = path:
    let
      ext = fileExtension path;
      writerType = detectByExtension path;
      basename = builtins.baseNameOf (toString path);
    in
    # Has a known script extension
    (writerType != null && writerType != "writeText") ||
    # No extension but common executable names
    (ext == "" && builtins.any (pattern: builtins.match pattern basename != null) [
      ".*run.*"
      ".*script.*"
      ".*build.*"
      ".*install.*"
      ".*setup.*"
      ".*start.*"
      ".*stop.*"
      "bin.*"
    ]);

  # Debug helper: show detection results for a file
  debugDetection = path: content: {
    inherit path;
    extension = fileExtension path;
    extensionType = detectByExtension path;
    shebangType = if content != null then detectByShebang content else null;
    finalType = detectFileType path content;
    looksExecutable = looksExecutable path;
  };
}
