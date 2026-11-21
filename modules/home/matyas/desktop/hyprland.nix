{
  flake.modules.homeManager.matyas-desktop-hyprland = { config, lib, pkgs, osConfig, ... }:
  let
    cfg = config.wayland.windowManager.hyprland;
    overview = cfg.enable && config.deployment.hyprland.overview.enable;
    compositor = if cfg.package != null then cfg.package
      else if osConfig != null then osConfig.programs.hyprland.package else pkgs.hyprland;
    scrolloverview = pkgs.callPackage ./hyprland.pkgs.nix { hyprland = compositor; };
    keyOptions = lib.optionalAttrs overview { submap_universal = true; };
    overviewAction = action: lib.generators.mkLuaInline ''function() hl.plugin.scrolloverview.${action} end'';
    terminal = if config.programs.ghostty.package == null then "ghostty"
      else lib.getExe config.programs.ghostty.package;
    terminalCommand = if config.wayland.windowManager.hyprland.systemd.enable
      then terminal else "uwsm app -- ${terminal}";
    exec = command: lib.generators.mkLuaInline "hl.dsp.exec_cmd(${lib.generators.toLua {} command})";
    logout = if config.wayland.windowManager.hyprland.systemd.enable
      then lib.generators.mkLuaInline "hl.dsp.exit()" else exec "uwsm stop";
    workspaces = lib.range 1 5;
  in
  {
    options.deployment.hyprland.overview.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the native scrolling workspace overview, built against the selected compositor.";
    };
    config = {
      assertions = lib.optional overview {
        assertion = cfg.package != null || (osConfig != null && osConfig.programs.hyprland.enable);
        message = "The native overview requires a Hyprland package selected by Home Manager or NixOS.";
      };
      home.sessionVariables = lib.mkIf config.wayland.windowManager.hyprland.enable {
        NIXOS_OZONE_WL = lib.mkDefault "1";
      };
      wayland.windowManager.hyprland = {
        enable = true;
        configType = "lua";
        plugins = lib.optional overview scrolloverview;
        settings = {
          config = {
            ecosystem.no_update_news = true;
            general.layout = lib.mkDefault "scrolling";
            plugin.scrolloverview = lib.mkIf overview {
              scale = 0.5;
              workspace_gap = 100;
              layout = "vertical";
              wallpaper = 2;
              blur = true;
              shadow.enabled = true;
            };
          };
          monitor = {
            output = "";
            mode = "preferred";
            position = "auto";
            scale = "auto";
          };
          bind = [
            { _args = [ "SUPER + RETURN" (exec terminalCommand) keyOptions ]; }
            { _args = [ "SUPER + Q" (lib.generators.mkLuaInline "hl.dsp.window.close()") keyOptions ]; }
            { _args = [ "SUPER + SHIFT + E" logout keyOptions ]; }
            { _args = [ "SUPER + LEFT" (lib.generators.mkLuaInline ''hl.dsp.focus({ direction = "left" })'') keyOptions ]; }
            { _args = [ "SUPER + RIGHT" (lib.generators.mkLuaInline ''hl.dsp.focus({ direction = "right" })'') keyOptions ]; }
          ] ++ lib.optional overview {
            _args = [ "SUPER + TAB" (overviewAction ''overview("toggle")'') keyOptions ];
          } ++ lib.concatMap (number:
            let workspace = toString number;
            in [
                { _args = [ "SUPER + ${workspace}" (lib.generators.mkLuaInline "hl.dsp.focus({ workspace = ${workspace} })") keyOptions ]; }
                { _args = [ "SUPER + SHIFT + ${workspace}" (lib.generators.mkLuaInline "hl.dsp.window.move({ workspace = ${workspace} })") keyOptions ]; }
            ]) workspaces;
        };
        submaps = lib.mkIf overview { scrolloverview.settings.bind = [
          { _args = [ "ESCAPE" (overviewAction ''overview("close")'') ]; }
          { _args = [ "RETURN" (overviewAction ''overview("close")'') ]; }
          { _args = [ "mouse:272" (lib.generators.mkLuaInline ''function()
              hl.plugin.scrolloverview.overview("select")
              hl.plugin.scrolloverview.window("select")
              hl.plugin.scrolloverview.overview("close")
            end'') { mouse = true; } ]; }
        ] ++ map (direction: {
          _args = [ (lib.toUpper direction) (overviewAction ''navigate("${direction}")'') ];
        }) [ "left" "right" "up" "down" ]; };
        extraConfig = lib.concatMapStringsSep "\n"
          (number: ''hl.workspace_rule({ workspace = "${toString number}", persistent = true })'') workspaces;
      };
    };
  };
}
