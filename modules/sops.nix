{ inputs, ... }:
{
  flake.modules.nixos.sops = {
    imports = [
      inputs.sops-nix.nixosModules.sops
    ];

    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  };
}
