{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check;
  modules = config.flake.modules;
  active = mkSystem [ modules.nixos.workstation-profile ] {};
  home = active.config.home-manager.users.matyas;
  standalone = config.flake.homeConfigurations.matyas-workstation.config;
  disabled = extend active {
    home-manager.users.matyas.programs.vscode.enable = false;
    programs.nautilus.enable = false;
  };
in
{
  flake.lib.compositionTests.desktop-productivity = {
    editor-is-selected = check "The workstation should provide VS Code with an editable settings baseline and mutable extensions."
      (home.programs.vscode.enable && home.programs.vscode.profiles.default.mutableUserSettings
        && home.programs.vscode.mutableExtensionsDir
        && home.programs.vscode.profiles.default.userSettings."nix.enableLanguageServer"
        && standalone.programs.vscode.enable);
    editor-has-nix-tooling = check "VS Code should have Nix and direnv support without guessing unrelated language extensions."
      (lib.all (id: lib.any (extension: extension.vscodeExtUniqueId == id)
        home.programs.vscode.profiles.default.extensions) [ "jnoortheen.nix-ide" "mkhl.direnv" ]);
    file-manager-has-system-support = check "Nautilus should have its D-Bus registration and GVfs support for trash and removable devices."
      (active.config.programs.nautilus.enable && active.config.services.gvfs.enable
        && active.config.services.udisks2.enable
        && lib.any (package: lib.getName package == "nautilus") active.config.services.dbus.packages);
    file-manager-has-home-defaults = check "Nautilus should open directories, prefer dark appearance, and have a compositor shortcut."
      (home.programs.nautilus.enable
        && home.xdg.mimeApps.defaultApplications."inode/directory" == [ "org.gnome.Nautilus.desktop" ]
        && home.dconf.settings."org/gnome/desktop/interface".color-scheme == "prefer-dark"
        && lib.hasInfix "SUPER + E" home.xdg.configFile."hypr/hyprland.lua".text);
    opt-outs-remove-app-support = check "App opt-outs should remove personal settings, folder handlers, shortcuts, and file-service contributions."
      (!disabled.config.home-manager.users.matyas.programs.vscode.enable
        && !disabled.config.home-manager.users.matyas.programs.nautilus.enable
        && !disabled.config.services.gvfs.enable
        && !(disabled.config.home-manager.users.matyas.xdg.mimeApps.defaultApplications ? "inode/directory")
        && !(lib.hasInfix "SUPER + E" disabled.config.home-manager.users.matyas.xdg.configFile."hypr/hyprland.lua".text));
  };
}
