{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-zoxide = {
    programs.zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-zoxide
  ];
}