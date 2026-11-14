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
in
{
  flake.lib.compositionTests.home-manager = {
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
