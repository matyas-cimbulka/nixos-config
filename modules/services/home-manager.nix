{ inputs, ... }:
{
  flake.modules.nixos.home-manager = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = [
        ({ config, lib, osConfig, ... }: {
          config = lib.mkIf (osConfig.programs.hyprland.enable && config.wayland.windowManager.hyprland.enable) {
            wayland.windowManager.hyprland = {
              package = lib.mkDefault null;
              portalPackage = lib.mkDefault null;
              systemd.enable = lib.mkDefault (!osConfig.programs.hyprland.withUWSM);
            };
            xdg.configFile = lib.mkIf osConfig.programs.hyprland.withUWSM {
              "uwsm/env".source = lib.mkDefault "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
            };
          };
        })
      ];
    };
  };
}
