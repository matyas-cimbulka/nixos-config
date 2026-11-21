{
  flake.modules.homeManager.matyas-desktop-nautilus = { config, lib, pkgs, osConfig, ... }:
  let
    cfg = config.programs.nautilus;
    systemEnabled = osConfig != null && (osConfig.programs.nautilus.enable or false);
    command = if cfg.package == null then "nautilus" else lib.getExe cfg.package;
    launch = if config.wayland.windowManager.hyprland.systemd.enable then command else "uwsm app -- ${command}";
  in {
    options.programs.nautilus = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = osConfig == null || systemEnabled;
        description = "Use GNOME Files as the personal file manager.";
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = if systemEnabled then null else pkgs.nautilus;
        description = "Package to install, or null when NixOS owns file-manager installation.";
      };
    };
    config = lib.mkMerge [
      (lib.mkIf cfg.enable {
        home.packages = lib.mkIf (cfg.package != null) [ cfg.package ];
        dconf.settings."org/gnome/desktop/interface".color-scheme = lib.mkDefault "prefer-dark";
        xdg.mimeApps = {
          enable = true;
          defaultApplications."inode/directory" = lib.mkDefault [ "org.gnome.Nautilus.desktop" ];
        };
      })
      (lib.mkIf (cfg.enable && config.wayland.windowManager.hyprland.enable) {
        wayland.windowManager.hyprland.settings.bind = [ {
          _args = [ "SUPER + E" (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${lib.generators.toLua {} launch})") ]
            ++ lib.optional (config.deployment.hyprland.overview.enable or false) { submap_universal = true; };
        } ];
      })
    ];
  };
}
