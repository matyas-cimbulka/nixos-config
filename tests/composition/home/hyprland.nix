{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome mkSystem check;
  modules = config.flake.modules;
  standalone = mkHome [ modules.homeManager.matyas-desktop-hyprland ] {};
  embedded = mkSystem [ modules.nixos.workstation-profile ] {};
  cfg = standalone.config.wayland.windowManager.hyprland;
  embeddedCfg = embedded.config.home-manager.users.matyas.wayland.windowManager.hyprland;
  disabled = standalone.extendModules { modules = [ { deployment.hyprland.overview.enable = false; } ]; };
  noShell = mkHome [ modules.homeManager.matyas-workstation ] { programs.noctalia.enable = false; };
  text = standalone.config.xdg.configFile."hypr/hyprland.lua".text or "";
in {
  flake.lib.compositionTests.home-hyprland = {
    loads-native-scrolling-overview = check "Hyprland should load ScrollOverview and bind Super+Tab to a native zoomed-out overview."
      (lib.any (plugin: lib.getName plugin == "scrolloverview") cfg.plugins
        && lib.hasInfix "hl.plugin.load" text && lib.hasInfix "SUPER + TAB" text
        && lib.hasInfix "hl.plugin.scrolloverview.overview" text
        && cfg.settings.config.plugin.scrolloverview.layout == "vertical"
        && cfg.settings.config.plugin.scrolloverview.scale == 0.5);
    plugin-matches-compositor = check "The overview must build against the compositor selected by Home Manager or NixOS."
      (toString (builtins.head cfg.plugins).hyprland == toString cfg.package
        && toString (builtins.head embeddedCfg.plugins).hyprland
          == toString embedded.config.programs.hyprland.package);
    compositor-overview-is-independent-of-shell = check "Disabling Noctalia must preserve Hyprland's native overview."
      (lib.hasInfix "hl.plugin.scrolloverview.overview" noShell.config.xdg.configFile."hypr/hyprland.lua".text);
    overview-has-scoped-keyboard-controls = check "Overview navigation and Escape must be scoped to its own submap while desktop shortcuts remain usable."
      (cfg.submaps ? scrolloverview && lib.hasInfix "ESCAPE" text && lib.hasInfix "submap_universal" text
        && lib.hasInfix "hl.plugin.scrolloverview.navigate" text);
    overview-supports-pointer-selection = check "The custom overview submap must explicitly select clicked windows and close the overview."
      (lib.hasInfix "mouse:272" text && lib.hasInfix "hl.plugin.scrolloverview.window(\"select\")" text);
    overview-can-be-disabled = check "The overview opt-out must remove its plugin, configuration, and shortcuts together."
      (disabled.config.wayland.windowManager.hyprland.plugins == []
        && !(lib.hasInfix "scrolloverview" disabled.config.xdg.configFile."hypr/hyprland.lua".text));
  };
}
