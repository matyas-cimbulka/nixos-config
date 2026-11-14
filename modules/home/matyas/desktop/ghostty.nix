{
  flake.modules.homeManager.matyas-desktop-ghostty = { pkgs, ... }: {
    home.packages = [ pkgs.nerd-fonts.fira-code ];
    fonts.fontconfig.enable = true;

    programs.ghostty = {
      enable = true;
      settings = {
        font-family = "FiraCode Nerd Font Mono";
        font-size = 14;
        font-thicken = true;
        cursor-style = "bar";
        theme = "Catppuccin Mocha";
        window-height = 35;
        window-width = 130;
      };
    };
  };
}
