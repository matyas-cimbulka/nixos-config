{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  base = mkHome [ modules.matyas-base ] {};
  server = mkHome [ modules.matyas-server ] {};
in
{
  flake.lib.compositionTests.home-profiles = {
    base-owns-user-home-identity = check "The shared home profile should define the Matyas home identity and CLI environment."
      (base.config.home.username == "matyas" && base.config.home.homeDirectory == "/home/matyas"
        && base.config.programs.home-manager.enable && base.config.programs.fish.enable);
    server-preserves-shared-settings = check "The server home profile should compose the same shared editor, VCS, and CLI settings."
      (base.config.programs.git.settings == server.config.programs.git.settings
        && base.config.programs.jujutsu.settings == server.config.programs.jujutsu.settings
        && base.config.home.sessionVariables == server.config.home.sessionVariables
        && base.config.programs.btop.enable == server.config.programs.btop.enable);
    vcs-inherits-global-editor = check "The shared profile should provide EDITOR without either VCS feature pinning an editor."
      (server.config.home.sessionVariables.EDITOR == "nvim"
        && !(server.config.programs.git.settings ? core.editor)
        && !(server.config.programs.jujutsu.settings.ui ? editor));
  };
}
