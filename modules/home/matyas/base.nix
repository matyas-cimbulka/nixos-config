{ config, ... }:
{
  flake.modules.homeManager.matyas-base = { pkgs, ... }: {
    imports = [
      config.flake.modules.homeManager.matyas-cli-bat
      config.flake.modules.homeManager.matyas-cli-btop
      config.flake.modules.homeManager.matyas-cli-direnv
      config.flake.modules.homeManager.matyas-cli-eza
      config.flake.modules.homeManager.matyas-cli-fd
      config.flake.modules.homeManager.matyas-cli-fish
      config.flake.modules.homeManager.matyas-cli-fzf
      config.flake.modules.homeManager.matyas-cli-git
      config.flake.modules.homeManager.matyas-cli-jj
      config.flake.modules.homeManager.matyas-cli-jq
      config.flake.modules.homeManager.matyas-cli-ncdu
      config.flake.modules.homeManager.matyas-cli-nom
      config.flake.modules.homeManager.matyas-cli-nvim
      config.flake.modules.homeManager.matyas-cli-rg
      config.flake.modules.homeManager.matyas-cli-starship
      config.flake.modules.homeManager.matyas-cli-zellij
      config.flake.modules.homeManager.matyas-cli-zoxide
    ];

    home = {
      username = "matyas";
      homeDirectory = "/home/matyas";
      stateVersion = "26.05";

      packages = [ pkgs.openssh ];
    };

    programs.home-manager.enable = true;
  };
}
