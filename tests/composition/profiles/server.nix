{ inputs, config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check;
  modules = config.flake.modules.nixos;
  active = mkSystem [ modules.server-profile ] {
    deployment.alloy = { httpInterfaces = [ "metrics0" ]; overrideLokiIntegration = true; };
  };
  standaloneHome = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages.${compositionHelpers.system};
    modules = [ config.flake.modules.homeManager.matyas-server ];
  };
  custom = extend active { networking.firewall.enable = false; networking.useDHCP = true; };
  home = active.config.home-manager.users.matyas;
in
{
  flake.lib.compositionTests.server-profile = {
    explicitly-selects-common-features = check "Server should compose base policy, Matyas, and Alloy."
      (active.config.services.alloy.enable && active.config.users.users.matyas.isNormalUser
        && builtins.elem "flakes" active.config.nix.settings.experimental-features);
    does-not-select-deployment-credentials-or-tailscale = check "Server policy should leave SOPS and Tailscale selection to deployment."
      (!active.config.services.tailscale.enable && !(active.options ? sops));
    ssh-is-key-only = check "Server SSH policy should forbid root and password logins."
      (active.config.services.openssh.enable
        && active.config.services.openssh.settings.PermitRootLogin == "no"
        && !active.config.services.openssh.settings.PasswordAuthentication
        && !active.config.services.openssh.settings.KbdInteractiveAuthentication);
    networking-policy-is-overridable = check "Server network defaults should remain deployment-overridable."
      (!custom.config.networking.firewall.enable && custom.config.networking.useDHCP);
    embeds-shared-home-manager = check "The server profile should select the Matyas home with the shared package policy and CLI tools."
      (active.config.home-manager.useGlobalPkgs && active.config.home-manager.useUserPackages
        && home.home.username == "matyas" && home.home.homeDirectory == "/home/matyas"
        && home.programs.btop.enable && home.programs.neovim.enable);
    debugging-home-matches-standalone-tools = check "Embedded server Home Manager should use the same tools and settings as the standalone profile."
      (home.programs.neovim.enable == standaloneHome.config.programs.neovim.enable
        && home.programs.git.settings == standaloneHome.config.programs.git.settings
        && home.programs.jujutsu.settings == standaloneHome.config.programs.jujutsu.settings
        && home.home.sessionVariables.EDITOR == standaloneHome.config.home.sessionVariables.EDITOR);
    credentials-are-not-assumed = check "Server VCS should configure no personal identity or signing key."
      (!(home.programs.git.settings ? user) && home.programs.git.signing.key == null
        && !(home.programs.jujutsu.settings ? signing));
  };
}
