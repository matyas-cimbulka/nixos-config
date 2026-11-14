{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem check;
  modules = config.flake.modules.nixos;
  active = mkSystem [ modules.matyas ] {};
in
{
  flake.lib.compositionTests.matyas-user = {
    owns-debugging-user = check "Matyas should be a normal wheel user with Fish and public SSH access."
      (active.config.users.users.matyas.isNormalUser
        && builtins.elem "wheel" active.config.users.users.matyas.extraGroups
        && active.config.programs.fish.enable
        && active.config.users.users.matyas.openssh.authorizedKeys.keys != []);
    restricts-ssh-to-declared-user = check "The user feature should declare Matyas in SSH AllowUsers."
      (builtins.elem "matyas" active.config.services.openssh.settings.AllowUsers);
    does-not-select-home-manager = check "The account alone should not select Home Manager or a home profile."
      (!(active.options ? home-manager));
    does-not-enable-server-services = check "Selecting the user alone should not select the server role or observability."
      (!active.config.services.openssh.enable && !active.config.services.alloy.enable);
  };
}
