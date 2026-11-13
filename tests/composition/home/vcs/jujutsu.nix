{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  active = mkHome [ modules.matyas-cli-jj ] {};
  custom = mkHome [ modules.matyas-cli-jj ] {
    home.sessionVariables.EDITOR = "test-editor";
    programs.jujutsu.settings.user = { name = "Test Author"; email = "test@example.invalid"; };
  };
  cfg = active.config.programs.jujutsu;
in
{
  flake.lib.compositionTests.home-jujutsu = {
    enables-unauthenticated-jujutsu = check "The Jujutsu feature should install it without personal identity."
      (cfg.enable && (cfg.settings.user or {}) == {});
    leaves-signing-unconfigured = check "Baseline Jujutsu should not assume signing credentials."
      ((cfg.settings.signing or {}) == {});
    leaves-editor-to-environment = check "Jujutsu should leave its editor to the environment."
      (!(cfg.settings.ui ? editor) && custom.config.home.sessionVariables.EDITOR == "test-editor");
    permits-native-author-settings = check "Deployment should be able to supply author identity through native Jujutsu settings."
      (custom.config.programs.jujutsu.settings.user.email == "test@example.invalid");
    does-not-select-other-features = check "Jujutsu alone should not select Fish or Neovim."
      (!active.config.programs.fish.enable && !active.config.programs.neovim.enable);
  };
}
