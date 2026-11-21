{
  flake.modules.homeManager.matyas-desktop-noctalia = { config, lib, pkgs, ... }:
  let
    enabled = config.programs.noctalia.enable;
    wallpaper = pkgs.runCommand "workstation-gradient.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
      rsvg-convert --width 3840 --height 2160 ${./assets/gradient.svg} > "$out"
    '';
    command = action: lib.generators.mkLuaInline
      "hl.dsp.exec_cmd(${lib.generators.toLua {} "${lib.getExe config.programs.noctalia.package} msg ${action}"})";
  in
  {
    home.packages = lib.mkIf enabled [ pkgs.inter ];
    fonts.fontconfig.enable = lib.mkIf enabled true;

    programs.noctalia = {
      enable = lib.mkDefault true;
      systemd.enable = lib.mkDefault true;
      settings = lib.mkIf enabled {
        theme = {
          mode = "dark";
          source = "builtin";
          builtin = "Catppuccin";
        };
        shell = {
          font_family = "Inter";
          setup_wizard_enabled = false;
          polkit_agent = true;
          launch_apps_as_systemd_services = true;
          panel = {
            transparency_mode = "solid";
            control_center_placement = "floating";
          };
          launcher = {
            layout = "full";
            search_position = "top";
            width = 720;
          };
        };
        bar.default = {
          position = "top";
          background_opacity = 0.0;
          margin_edge = 8;
          margin_ends = 8;
          padding = 0;
          thickness = 40;
          reserve_space = true;
          shadow = false;
          capsule = true;
          capsule_fill = "surface";
          capsule_opacity = 0.90;
          capsule_border = "outline";
          capsule_thickness = 0.90;
          start = [ "group:workspaces" ];
          center = [ "clock" ];
          end = [ "group:controls" ];
          capsule_group = [
            { id = "workspaces"; members = [ "launcher" "workspaces" ]; fill = "surface"; border = "outline"; opacity = 0.90; padding = 6.0; }
            { id = "controls"; members = [ "tray" "notifications" "network" "bluetooth" "volume" "control-center" "session" ]; fill = "surface"; border = "outline"; opacity = 0.90; padding = 8.0; }
          ];
        };
        widget = {
          clock.format = "{:%a %d %b  %H:%M}";
          workspaces = {
            label_source = "id";
            show_icons = false;
            empty_color = "surface";
            occupied_color = "surface_variant";
            # A narrower active pill makes Noctalia hide its workspace label.
            active_pill_size = 1.4;
            inactive_pill_size = 1.4;
          };
        };
        dock.enabled = false;
        wallpaper = {
          enabled = true;
          default.path = toString wallpaper;
          transition = [ "fade" ];
        };
      };
    };

    wayland.windowManager.hyprland = lib.mkIf (enabled && config.wayland.windowManager.hyprland.enable) {
      settings = {
        config = {
          misc = {
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            background_color = "rgb(11111b)";
          };
          general = {
            gaps_in = 5;
            gaps_out = 10;
            border_size = 1;
            col = {
              active_border = "rgba(cba6f7cc)";
              inactive_border = "rgba(45475a88)";
            };
          };
          decoration = {
            rounding = 14;
            blur = { enabled = true; size = 3; passes = 2; };
            shadow = { enabled = true; range = 12; render_power = 3; color = "rgba(11111b66)"; };
          };
        };
        bind = map (binding: binding // {
          _args = binding._args ++ lib.optional (config.deployment.hyprland.overview.enable or false) { submap_universal = true; };
        }) [
          { _args = [ "SUPER + SPACE" (command "panel-toggle launcher") ]; }
          { _args = [ "SUPER + S" (command "panel-toggle control-center") ]; }
          { _args = [ "SUPER + COMMA" (command "settings-toggle") ]; }
          { _args = [ "SUPER + L" (command "session lock") ]; }
          { _args = [ "XF86AudioRaiseVolume" (command "volume-up") ]; }
          { _args = [ "XF86AudioLowerVolume" (command "volume-down") ]; }
          { _args = [ "XF86AudioMute" (command "volume-mute") ]; }
        ];
      };
      extraConfig = ''
        hl.layer_rule({
          name = "noctalia",
          match = { namespace = "^noctalia-.*$" },
          no_anim = true,
          blur = true,
          ignore_alpha = 0.5,
        })
      '';
    };
  };
}
