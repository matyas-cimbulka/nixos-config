{
  flake.modules.nixos.matyas = { pkgs, ... }: {
    programs.fish.enable = true;

    users.users.matyas = {
      isNormalUser = true;
      description = "Matyas Cimbulka";

      extraGroups = [ "wheel" ];

      shell = pkgs.fish;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOkghRgfCMR+4ne/KpXwjscvVprQVx3yIguHgUohdqa9"
      ];
    };

    services.openssh.settings.AllowUsers = [ "matyas" ];
  };
}
