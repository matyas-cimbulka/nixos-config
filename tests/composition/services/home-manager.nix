{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check;
  modules = config.flake.modules.nixos;
  active = mkSystem [ modules.home-manager ] {};
  userNames = [ "alice" "bob" ];
  withUsers = extend active {
    users.users = lib.genAttrs userNames (_: { isNormalUser = true; });
    home-manager.users = lib.genAttrs userNames (_: { pkgs, ... }: {
      home = {
        stateVersion = "26.05";
        packages = [ pkgs.hello ];
      };
    });
  };
  hyprlandUsers = extend withUsers {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };
    home-manager.users = lib.genAttrs userNames (_: {
      wayland.windowManager.hyprland.enable = true;
    });
  };
  withoutUWSM = extend hyprlandUsers { programs.hyprland.withUWSM = lib.mkForce false; };
  homeOnly = extend withUsers { home-manager.users.alice.wayland.windowManager.hyprland.enable = true; };
in
{
  flake.lib.compositionTests.home-manager = {
    coordinates-hyprland-for-every-user = check "Each Hyprland user should delegate compositor and portal installation to NixOS and session management to UWSM."
      (lib.all (name:
        let hyprland = hyprlandUsers.config.home-manager.users.${name}.wayland.windowManager.hyprland;
        in hyprland.package == null && hyprland.portalPackage == null && !hyprland.systemd.enable)
        userNames);
    imports-home-environment-into-uwsm = check "UWSM sessions should source each user's Home Manager session variables."
      (lib.all (name:
        let home = hyprlandUsers.config.home-manager.users.${name};
        in toString (home.xdg.configFile."uwsm/env".source or "")
          == "${home.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh") userNames);
    without-uwsm-home-manager-owns-session = check "Without UWSM, Home Manager should retain Hyprland session management."
      (withoutUWSM.config.home-manager.users.alice.wayland.windowManager.hyprland.systemd.enable
        && !(withoutUWSM.config.home-manager.users.alice.xdg.configFile ? "uwsm/env"));
    home-only-hyprland-keeps-installation = check "Without NixOS Hyprland, a Home Manager user should retain its compositor, portal, and session management."
      (homeOnly.config.home-manager.users.alice.wayland.windowManager.hyprland.package != null
        && homeOnly.config.home-manager.users.alice.wayland.windowManager.hyprland.portalPackage != null
        && homeOnly.config.home-manager.users.alice.wayland.windowManager.hyprland.systemd.enable);
    owns-shared-package-policy = check "Home Manager should share system packages and install user packages through NixOS."
      (active.config.home-manager.useGlobalPkgs && active.config.home-manager.useUserPackages);
    does-not-select-users = check "Home Manager alone should not select any managed homes or the Matyas account."
      (active.config.home-manager.users == {} && !(active.config.users.users ? matyas));
    applies-policy-to-each-user = check "Each Home Manager user should inherit their account identity and receive packages through NixOS."
      (lib.all (name:
        let
          home = withUsers.config.home-manager.users.${name};
          account = withUsers.config.users.users.${name};
        in
          home.home.username == name && home.home.homeDirectory == "/home/${name}"
          && builtins.elem (toString withUsers.pkgs.hello) (map toString home.home.packages)
          && builtins.elem (toString home.home.path) (map toString account.packages))
        userNames);
    does-not-enable-server-services = check "Home Manager alone should not select SSH or observability."
      (!active.config.services.openssh.enable && !active.config.services.alloy.enable);
  };
}
