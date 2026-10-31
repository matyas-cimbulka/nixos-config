{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-bat = {
    programs.bat.enable = true;
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-bat
  ];
}
