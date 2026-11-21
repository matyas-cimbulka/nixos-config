{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check failsEvaluation;
  modules = config.flake.modules.homeManager;
  active = mkHome [ modules.matyas-cli-jj ] {};
  custom = mkHome [ modules.matyas-cli-jj ] {
    home.sessionVariables.EDITOR = "test-editor";
    programs.jujutsu.settings.user = { name = "Test Author"; email = "test@example.invalid"; };
  };
  cfg = active.config.programs.jujutsu;
  development = mkHome [ modules.matyas-cli-jj ] {
    deployment.jujutsu.development.enable = true;
    deployment.jujutsu.development.signing.key = "/run/test-signing.pub";
    programs.jujutsu.settings = {
      user = { name = "Test Author"; email = "test@example.invalid"; };
    };
  };
  missingIdentity = development.extendModules { modules = [ { programs.jujutsu.settings.user = lib.mkForce {}; } ]; };
  unsigned = development.extendModules { modules = [ { deployment.jujutsu.development.signing.enable = false; } ]; };
  missingKey = development.extendModules { modules = [ {
    deployment.jujutsu.development.signing = { enable = true; key = lib.mkForce null; };
  } ]; };
in
{
  flake.lib.compositionTests.home-jujutsu = {
    development-enables-ssh-signing = check "Development Jujutsu should sign its own commits through SSH when a public-key reference is supplied."
      (development.config.programs.jujutsu.settings.signing.backend == "ssh"
        && development.config.programs.jujutsu.settings.signing.behavior == "own");
    development-requires-author = check "Development Jujutsu must reject missing author information."
      (failsEvaluation missingIdentity.activationPackage.drvPath);
    signing-opt-out-removes-defaults = check "The signing opt-out should remove its backend, key, and behavior defaults."
      ((unsigned.config.programs.jujutsu.settings.signing or {}) == {});
    automatic-signing-requires-key = check "Jujutsu signing should reject a missing public-key reference."
      (failsEvaluation missingKey.activationPackage.drvPath);
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
