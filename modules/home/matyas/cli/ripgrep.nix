{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-rg.programs.ripgrep.enable = true;

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-rg
  ];
}