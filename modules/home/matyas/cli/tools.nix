{
  flake.modules.homeManager = {
    matyas-cli-bat = {
      programs.bat.enable = true;
    };

    matyas-cli-btop.programs.btop.enable = true;

    matyas-cli-eza = {
      programs.eza = {
        enable = true;
        enableFishIntegration = true;

        colors = "auto";
        git = true;
        icons = "auto";
      };
    };

    matyas-cli-fd.programs.fd.enable = true;

    matyas-cli-fzf = {
      programs.fzf = {
        enable = true;
        enableFishIntegration = true;
      };
    };

    matyas-cli-jq.programs.jq.enable = true;

    matyas-cli-ncdu = { pkgs, ... }: {
      home.packages = [ pkgs.ncdu ];
    };

    matyas-cli-nom = { pkgs, ... }: {
      home.packages = [ pkgs.nix-output-monitor ];
    };

    matyas-cli-rg.programs.ripgrep.enable = true;

    matyas-cli-zoxide = {
      programs.zoxide = {
        enable = true;
        enableFishIntegration = true;
      };
    };
  };
}
