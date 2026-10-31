{ config, inputs, ... }:
{
  flake.modules.nixos.matyas = { pkgs, ... }: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    programs.fish.enable = true;

    users.users.matyas = {
      isNormalUser = true;
      description = "Matyas Cimbulka";

      extraGroups = [ "wheel" ];

      shell = pkgs.fish;
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };
  };

  flake.modules.nixos.server-profile = {
    imports = [
      config.flake.modules.nixos.matyas
    ];

    users.users.matyas.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOkghRgfCMR+4ne/KpXwjscvVprQVx3yIguHgUohdqa9"
    ];

    home-manager.users.matyas.imports = [
      config.flake.modules.homeManager.matyas-server
    ];

    services.openssh.settings = {
      AllowUsers = [ "matyas" ];
    };
  };
}
