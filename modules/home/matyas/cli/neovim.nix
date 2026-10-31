{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-nvim = {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-nvim
  ];
}