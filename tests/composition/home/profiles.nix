{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  base = mkHome [ modules.matyas-base ] {};
  server = mkHome [ modules.matyas-server ] {};
  workstation = mkHome [ modules.matyas-workstation ] {};
  hyprlandText = workstation.config.xdg.configFile."hypr/hyprland.lua".text or "";
in
{
  flake.lib.compositionTests.home-profiles = {
    workstation-selects-noctalia = check "The workstation home should select Noctalia and its graphical-session service."
      (workstation.config.programs.noctalia.enable && workstation.config.programs.noctalia.systemd.enable);
    workstation-provides-hyprland-and-ghostty = check "The workstation home should provide Hyprland configuration, Ghostty, and standalone session management."
      (workstation.config.wayland.windowManager.hyprland.enable && workstation.config.programs.ghostty.enable
        && workstation.config.wayland.windowManager.hyprland.package != null
        && workstation.config.wayland.windowManager.hyprland.systemd.enable);
    workstation-renders-minimal-desktop = check "The generated Lua configuration should provide a terminal command, window closing, and session exit."
      (lib.hasInfix "ghostty" hyprlandText && lib.hasInfix "hl.dsp.window.close()" hyprlandText
        && lib.hasInfix "hl.dsp.exit()" hyprlandText);
    shared-and-server-homes-stay-cli-only = check "Desktop selection must not add Hyprland or Ghostty to the shared or server homes."
      (lib.all (home: !home.config.wayland.windowManager.hyprland.enable && !home.config.programs.ghostty.enable
        && !home.config.programs.noctalia.enable)
        [ base server ]);
    base-owns-user-home-identity = check "The shared home profile should define the Matyas home identity and CLI environment."
      (base.config.home.username == "matyas" && base.config.home.homeDirectory == "/home/matyas"
        && base.config.programs.home-manager.enable && base.config.programs.fish.enable);
    server-preserves-shared-settings = check "The server home profile should compose the same shared editor, VCS, and CLI settings."
      (base.config.programs.git.settings == server.config.programs.git.settings
        && base.config.programs.jujutsu.settings == server.config.programs.jujutsu.settings
        && base.config.home.sessionVariables == server.config.home.sessionVariables
        && base.config.programs.btop.enable == server.config.programs.btop.enable);
    workstation-preserves-shared-settings = check "The workstation home profile should preserve the shared identity, editor, VCS, and CLI settings."
      (base.config.home.username == workstation.config.home.username
        && base.config.home.homeDirectory == workstation.config.home.homeDirectory
        && base.config.programs.git.settings == workstation.config.programs.git.settings
        && base.config.programs.jujutsu.settings == workstation.config.programs.jujutsu.settings
        && lib.all (name: (workstation.config.home.sessionVariables.${name} or null)
          == base.config.home.sessionVariables.${name}) (builtins.attrNames base.config.home.sessionVariables)
        && base.config.programs.btop.enable == workstation.config.programs.btop.enable
        && base.config.programs.neovim.enable == workstation.config.programs.neovim.enable);
    vcs-inherits-global-editor = check "The shared profile should provide EDITOR without either VCS feature pinning an editor."
      (server.config.home.sessionVariables.EDITOR == "nvim"
        && !(server.config.programs.git.settings ? core.editor)
        && !(server.config.programs.jujutsu.settings.ui ? editor));
  };
}
