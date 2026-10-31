{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-jj = {
    programs.jujutsu = {
      enable = true;

      settings = {
        user = {
          name = "Matyas Cimbulka";
          email = "matyas.cimbulka@gmail.com";
        };

        signing = {
          behavior = "own";
          backend = "ssh";
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHuanqwyg+nSluVQKYa5CsEmxjJLW5JKQosV2D7h1rKP";
        };

        ui = {
          default-command = "log";
        };
      };
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-jj
  ];
}