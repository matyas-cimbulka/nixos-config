{
  flake.modules.nixos.onepassword = { config, lib, ... }: {
    options.deployment.onepassword.browserIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the 1Password Chrome extension when browser policies and the desktop app are enabled.";
    };

    config = lib.mkMerge [
      {
        programs = {
          _1password-gui.enable = lib.mkDefault true;
          _1password.enable = lib.mkDefault true;
        };
        nixpkgs.config.allowUnfreePackages = lib.optional config.programs._1password-gui.enable "1password"
          ++ lib.optional config.programs._1password.enable "1password-cli";
      }
      (lib.mkIf (config.programs._1password-gui.enable && config.programs.chromium.enable
        && config.deployment.onepassword.browserIntegration) {
        programs.chromium.extraOpts.ExtensionSettings.aeblfdkhhhdcdjpifhhbdiojplfjncoa = {
          installation_mode = "normal_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
      })
    ];
  };
}
