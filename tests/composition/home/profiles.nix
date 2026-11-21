{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  base = mkHome [ modules.matyas-base ] {};
  server = mkHome [ modules.matyas-server ] {};
  workstation = mkHome [ modules.matyas-workstation ] {};
  home = workstation.config;
  signingFile = "${home.home.homeDirectory}/.ssh/signing.pub";
  hyprlandText = workstation.config.xdg.configFile."hypr/hyprland.lua".text or "";
in
{
  flake.lib.compositionTests.home-profiles = {
    workstation-defaults-to-scrolling = check "New workspaces should inherit the scrolling layout without pinning individual workspaces."
      ((home.wayland.windowManager.hyprland.settings.config.general.layout or null) == "scrolling");
    scrolling-has-keyboard-navigation = check "The scrolling desktop should support keyboard focus between neighboring windows."
      (lib.hasInfix "SUPER + LEFT" hyprlandText && lib.hasInfix "SUPER + RIGHT" hyprlandText
        && lib.hasInfix "hl.dsp.focus" hyprlandText);
    workstation-enables-development-vcs = check "The workstation should enable Git SSH signing and Jujutsu signing of own commits."
      (home.deployment.git.development.enable && home.deployment.jujutsu.development.enable
        && home.programs.git.signing.format == "ssh" && home.programs.git.signing.signByDefault
        && (home.programs.jujutsu.settings.signing.backend or null) == "ssh"
        && (home.programs.jujutsu.settings.signing.behavior or null) == "own");
    workstation-shares-signing-material = check "Both VCS tools should use one public-key file and the same trusted-signers file."
      (home.programs.git.signing.key == signingFile
        && (home.programs.jujutsu.settings.signing.key or null) == signingFile
        && lib.hasPrefix "ssh-ed25519 " (home.home.file.".ssh/signing.pub".text or "")
        && home.programs.git.signing.allowedSigners != ""
        && home.programs.jujutsu.settings.signing.backends.ssh.allowed-signers
          == "${home.xdg.configHome}/git/allowed_signers");
    baseline-and-server-vcs-remain-unauthenticated = check "Personal workstation identity and signing must not leak into shared or server homes."
      (lib.all (profile: !profile.config.deployment.git.development.enable
        && !profile.config.deployment.jujutsu.development.enable
        && (profile.config.programs.git.settings.user or {}) == {}
        && (profile.config.programs.jujutsu.settings.user or {}) == {}
        && profile.config.programs.git.signing.key == null
        && (profile.config.programs.jujutsu.settings.signing or {}) == {}) [ base server ]);
    suppresses-compositor-update-overlay = check "Declarative desktop startup should not cover applications with Hyprland's first-run update window."
      ((workstation.config.wayland.windowManager.hyprland.settings.config.ecosystem.no_update_news or false));
    electron-apps-prefer-wayland = check "The workstation desktop should allow Electron wrappers to select native Wayland."
      ((workstation.config.home.sessionVariables.NIXOS_OZONE_WL or null) == "1");
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
    workstation-preserves-shared-settings = check "The workstation should preserve shared CLI defaults while adding personal VCS identity and signing."
      (base.config.home.username == workstation.config.home.username
        && base.config.home.homeDirectory == workstation.config.home.homeDirectory
        && lib.recursiveUpdate workstation.config.programs.git.settings base.config.programs.git.settings
          == workstation.config.programs.git.settings
        && lib.recursiveUpdate workstation.config.programs.jujutsu.settings base.config.programs.jujutsu.settings
          == workstation.config.programs.jujutsu.settings
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
