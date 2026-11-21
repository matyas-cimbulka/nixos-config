{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  selected = modules.matyas-desktop-noctalia or {};
  active = mkHome [ selected ] {};
  withHyprland = mkHome [ selected modules.matyas-desktop-hyprland ] {};
  disabled = mkHome [ selected modules.matyas-desktop-hyprland ] { programs.noctalia.enable = false; };
  home = active.config;
  unit = home.systemd.user.services.noctalia or {};
  hyprland = withHyprland.config.xdg.configFile."hypr/hyprland.lua".text or "";
in
{
  flake.lib.compositionTests.home-noctalia = {
    leaves-overview-to-compositor = check "The window overview should belong to Hyprland rather than Noctalia's carousel."
      (!(lib.hasInfix "msg window-switcher" hyprland)
        && lib.hasInfix "hl.plugin.scrolloverview.overview" hyprland);
    control-center-has-independent-background = check "The control center should have an opaque floating surface independent of the transparent bar."
      (home.programs.noctalia.settings.shell.panel.transparency_mode == "solid"
        && home.programs.noctalia.settings.shell.panel.control_center_placement == "floating");
    avoids-default-wallpaper-flash = check "The compositor should use a dark backing without its default wallpaper or splash while Noctalia starts."
      (withHyprland.config.wayland.windowManager.hyprland.settings.config.misc.disable_hyprland_logo
        && withHyprland.config.wayland.windowManager.hyprland.settings.config.misc.disable_splash_rendering
        && withHyprland.config.wayland.windowManager.hyprland.settings.config.misc.background_color == "rgb(11111b)");
    manages-session-service = check "The home feature should install and start one Noctalia service bound to the graphical session."
      (home.programs.noctalia.enable && home.programs.noctalia.systemd.enable
        && unit.Unit.PartOf == [ home.wayland.systemd.target ]
        && unit.Install.WantedBy == [ home.wayland.systemd.target ]
        && unit.Service.ExecStart == [ (lib.getExe home.programs.noctalia.package) ]);
    preserves-ui-experimentation = check "Home Manager should validate the declarative baseline while leaving Noctalia's UI state writable."
      (home.programs.noctalia.enable && home.programs.noctalia.checkConfig
        && home.xdg.configFile ? "noctalia/config.toml"
        && !(home.home.file ? ".local/state/noctalia/settings.toml"));
    hyprland-integration-follows-selection = check "Selecting Noctalia with Hyprland should add shell shortcuts without a second compositor startup command."
      (lib.hasInfix "panel-toggle launcher" hyprland && lib.hasInfix "panel-toggle control-center" hyprland
        && lib.hasInfix "settings-toggle" hyprland
        && !(lib.hasInfix "hl.exec_cmd(\"noctalia\")" hyprland)
        && !(active.config.wayland.windowManager.hyprland.enable));
    can-be-disabled = check "Disabling the shell should remove its service, generated baseline, and Hyprland shell shortcuts."
      (!disabled.config.programs.noctalia.enable
        && !(disabled.config.systemd.user.services ? noctalia)
        && !(disabled.config.xdg.configFile ? "noctalia/config.toml")
        && !(lib.hasInfix "msg window-switcher" (disabled.config.xdg.configFile."hypr/hyprland.lua".text or ""))
        && !(lib.hasInfix "panel-toggle launcher" (disabled.config.xdg.configFile."hypr/hyprland.lua".text or "")));
  };
}
