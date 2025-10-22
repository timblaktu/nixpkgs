{ config
, lib
, callPackages
, pkgs
,
}:

# If you are reading this, you can test these writers by running: nix-build . -A tests.writers
let
  aliases = if config.allowAliases then (import ./aliases.nix lib) else prev: { };

  # Writers for JSON-like data structures
  dataWriters = callPackages ./data.nix { };

  # Writers for scripts
  scriptWriters = callPackages ./scripts.nix { };

  # Automatic writer selection based on file type detection
  autoWriters = import ./auto.nix { inherit lib pkgs; writers = scriptWriters // dataWriters; };

  writers = scriptWriters // dataWriters // autoWriters;
in
writers // (aliases writers)
