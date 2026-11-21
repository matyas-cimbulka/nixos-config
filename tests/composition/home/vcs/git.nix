{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check failsEvaluation;
  modules = config.flake.modules.homeManager;
  active = mkHome [ modules.matyas-cli-git ] {};
  custom = mkHome [ modules.matyas-cli-git ] {
    home.sessionVariables.EDITOR = "test-editor";
    programs.git.settings.user = { name = "Test Author"; email = "test@example.invalid"; };
  };
  cfg = active.config.programs.git;
  development = mkHome [ modules.matyas-cli-git ] {
    deployment.git.development.enable = true;
    programs.git.settings.user = { name = "Test Author"; email = "test@example.invalid"; };
    programs.git.signing.key = "/run/test-signing.pub";
  };
  missingIdentity = development.extendModules { modules = [ { programs.git.settings.user = lib.mkForce {}; } ]; };
  unsigned = development.extendModules { modules = [ { programs.git.signing.signByDefault = false; } ]; };
  missingKey = development.extendModules { modules = [ {
    programs.git.signing = { key = lib.mkForce null; signByDefault = true; };
  } ]; };
in
{
  flake.lib.compositionTests.home-git = {
    development-enables-ssh-signing = check "Development Git should default to SSH signing when supplied a public-key reference."
      (development.config.programs.git.signing.format == "ssh" && development.config.programs.git.signing.signByDefault);
    development-requires-author = check "Development Git must reject missing author information."
      (failsEvaluation missingIdentity.activationPackage.drvPath);
    signing-can-be-disabled = check "Development Git should preserve an explicit automatic-signing opt-out."
      (!unsigned.config.programs.git.signing.signByDefault);
    automatic-signing-requires-key = check "Automatic Git signing should reject a missing key."
      (failsEvaluation missingKey.activationPackage.drvPath);
    enables-unauthenticated-git = check "The Git feature should install Git without assuming a personal identity."
      (cfg.enable && (cfg.settings.user or {}) == {});
    leaves-editor-to-environment = check "Git should leave editor selection to its environment."
      (!(cfg.settings ? core.editor) && custom.config.home.sessionVariables.EDITOR == "test-editor"
        && !(custom.config.programs.git.settings ? core.editor));
    leaves-signing-unconfigured = check "Baseline Git should not assume a signing key or enable automatic signing."
      (cfg.signing.key == null && !(cfg.settings.commit.gpgSign or false));
    leaves-https-remotes-unmodified = check "Baseline Git should not rewrite HTTPS remotes to SSH."
      ((cfg.settings.url or {}) == {});
    permits-explicit-deployment-identity = check "Deployment should be able to supply Git author identity through native options."
      (custom.config.programs.git.settings.user.email == "test@example.invalid");
    does-not-select-editor-or-shell = check "Git alone should not select an editor or Fish."
      (!active.config.programs.neovim.enable && !active.config.programs.fish.enable);
  };
}
