{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  active = mkHome [ modules.matyas-cli-zellij ] {};
in
{
  flake.lib.compositionTests.home-multiplexers = {
    independently-selectable = check "Zellij should work as an independent feature without selecting Fish or an editor."
      (active.config.programs.zellij.enable && !active.config.programs.fish.enable
        && !active.config.programs.neovim.enable);
  };
}
