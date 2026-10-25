{ config, ... }:
{
  flake.modules.nixos.tycho-microvms = {
    microvm.vms = {
      anderson.config.imports = [ config.flake.modules.nixos.anderson ];
      test-microvm.config.imports = [ config.flake.modules.nixos.test-microvm ]; 
    };
  };
}