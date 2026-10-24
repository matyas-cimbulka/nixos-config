{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-zellij = {
    programs.zellij = {
      enable = true;
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-zellij
  ];
}