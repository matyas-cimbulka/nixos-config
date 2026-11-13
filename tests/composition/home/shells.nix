{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  fish = mkHome [ modules.matyas-cli-fish ] {};
  starship = mkHome [ modules.matyas-cli-starship ] {};
  direnv = mkHome [ modules.matyas-cli-direnv ] {};
  combined = mkHome [ modules.matyas-cli-fish modules.matyas-cli-starship modules.matyas-cli-direnv ] {};
in
{
  flake.lib.compositionTests.home-shells = {
    fish-is-independently-selectable = check "Fish should configure its greeting without requiring Starship or direnv."
      (fish.config.programs.fish.enable && !fish.config.programs.starship.enable
        && !fish.config.programs.direnv.enable
        && lib.hasInfix "set fish_greeting" fish.config.programs.fish.interactiveShellInit);
    prompt-and-direnv-do-not-select-shell = check "Prompt and direnv features should leave shell selection explicit."
      (!starship.config.programs.fish.enable && !direnv.config.programs.fish.enable);
    fish-integrations-are-active = check "Fish, Starship, and direnv should compose into their generated shell initialization."
      (combined.config.programs.fish.enable
        && combined.config.programs.starship.enableFishIntegration
        && combined.config.programs.direnv.enableFishIntegration
        && lib.hasInfix "starship" combined.config.programs.fish.interactiveShellInit
        && lib.hasInfix "direnv" combined.config.programs.fish.interactiveShellInit);
  };
}
