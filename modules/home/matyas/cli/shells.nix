{
  flake.modules.homeManager = {
    matyas-cli-fish = {
      programs.fish = {
        enable = true;

        interactiveShellInit = ''
          set fish_greeting # Disable greeting
        '';
      };
    };

    matyas-cli-starship = {
      programs.starship = {
        enable = true;
        enableFishIntegration = true;
        enableTransience = true;

        presets = [ "no-nerd-font" ];
      };
    };

    matyas-cli-direnv = {
      programs.direnv = {
        enable = true;
        enableFishIntegration = true;
      };
    };
  };
}
