{
  flake.modules.homeManager.matyas-base = { pkgs, ... }: {
    home = {
      username = "matyas";
      homeDirectory = "/home/matyas";
      stateVersion = "26.05";

      packages = with pkgs; [
        openssh
      ];
    };

    programs.home-manager.enable = true;
  };
}
