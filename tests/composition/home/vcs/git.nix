{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  active = mkHome [ modules.matyas-cli-git ] {};
  custom = mkHome [ modules.matyas-cli-git ] {
    home.sessionVariables.EDITOR = "test-editor";
    programs.git.settings.user = { name = "Test Author"; email = "test@example.invalid"; };
  };
  cfg = active.config.programs.git;
in
{
  flake.lib.compositionTests.home-git = {
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
