{
  flake.modules.nixos.matyas = {
    users.users.matyas = {
      isNormalUser = true;
      description = "Matyas Cimbulka";

      extraGroups = [ "wheel" ];
    };
  };

  flake.modules.nixos.server-profile.users.users.matyas.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOkghRgfCMR+4ne/KpXwjscvVprQVx3yIguHgUohdqa9"
  ];
}