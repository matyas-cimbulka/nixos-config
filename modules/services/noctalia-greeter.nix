{
  flake.modules.nixos.noctalia-greeter = { config, lib, pkgs, ... }: {
    services.displayManager.noctalia-greeter = {
      enable = lib.mkDefault true;
      # Greeter 1.7 clears a first mouse press when focus causes closed-menu relayout.
      package = lib.mkDefault (pkgs.noctalia-greeter.overrideAttrs (old: {
        patches = (old.patches or []) ++ [ ./noctalia-greeter/preserve-pointer-without-menus.patch ];
      }));
      cursorTheme.package = lib.mkDefault pkgs.adwaita-icon-theme;
      settings = {
        cursor.size = lib.mkIf config.services.displayManager.noctalia-greeter.enable (lib.mkDefault 24);
        session = lib.mkIf (config.services.displayManager.noctalia-greeter.enable && config.programs.hyprland.enable) {
          default = lib.mkDefault (if config.programs.hyprland.withUWSM then "hyprland-uwsm" else "hyprland");
        };
      };
    };
    environment.sessionVariables = lib.mkIf (config.services.displayManager.noctalia-greeter.enable
      && config.programs.hyprland.enable && config.programs.hyprland.withUWSM) {
      UWSM_SILENT_START = lib.mkDefault "1";
    };
  };
}
