{ pkgs ? import <nixpkgs> { } }:

let
  content = ''
    #!/usr/bin/env bash
    echo "test"
  '';
  path = "/bin/test-auto-bin";
  result = pkgs.lib.fileTypes.getWriterType path content;
in
{
  inherit content path result;
  # This should show what writer type is detected
}
