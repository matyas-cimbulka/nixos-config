{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  active = mkHome [ modules.matyas-cli-nvim ] {};
  custom = mkHome [ modules.matyas-cli-nvim ] {
    programs.neovim.defaultEditor = lib.mkForce false;
    home.sessionVariables.EDITOR = "test-editor";
  };
in
{
  flake.lib.compositionTests.home-editors = {
    editor-owns-global-default = check "Neovim should provide the global EDITOR default."
      (active.config.programs.neovim.enable && active.config.home.sessionVariables.EDITOR == "nvim");
    explicit-global-editor-wins = check "Deployment should be able to opt out of Neovim as the default and supply EDITOR."
      (custom.config.home.sessionVariables.EDITOR == "test-editor");
  };
}
