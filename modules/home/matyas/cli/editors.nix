{
  flake.modules.homeManager.matyas-cli-nvim = {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };
  };
}
