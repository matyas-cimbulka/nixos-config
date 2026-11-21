{
  flake.modules.homeManager.matyas-desktop-vscode = { config, lib, pkgs, ... }: {
    programs.vscode = {
      enable = lib.mkDefault true;
      mutableExtensionsDir = true;
      profiles.default = {
        mutableUserSettings = true;
        enableUpdateCheck = false;
        extensions = with pkgs.vscode-extensions; [ jnoortheen.nix-ide mkhl.direnv catppuccin.catppuccin-vsc ];
        userSettings = {
          "editor.fontFamily" = "'FiraCode Nerd Font Mono', monospace";
          "editor.fontSize" = 14;
          "editor.fontLigatures" = true;
          "workbench.colorTheme" = "Catppuccin Mocha";
          "terminal.integrated.defaultProfile.linux" = "fish";
          "nix.enableLanguageServer" = true;
          "nix.serverPath" = lib.getExe pkgs.nixd;
        };
      };
    };
  };
}
