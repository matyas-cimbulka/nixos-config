{
  flake.modules.homeManager.matyas-cli-git = { config, lib, ... }:
  let cfg = config.programs.git;
  in {
    options.deployment.git.development.enable = lib.mkEnableOption "development identity validation and SSH signing defaults";
    config = lib.mkMerge [ {
      programs.git = {
        enable = true;
        ignores = [ ".claude" ];
        settings = {
          init.defaultBranch = "main";
          pull.rebase = true;
          push.autoSetupRemote = true;
          rerere.enabled = true;
        };
      };
    } (lib.mkIf (cfg.enable && config.deployment.git.development.enable) {
      assertions = [
        {
          assertion = (cfg.settings.user.name or "") != "" && (cfg.settings.user.email or "") != "";
          message = "Development Git requires programs.git.settings.user.name and user.email.";
        }
        {
          assertion = cfg.signing.signByDefault != true || (cfg.signing.key != null && cfg.signing.key != "");
          message = "Automatic Git signing requires programs.git.signing.key.";
        }
      ];
      programs.git.signing = {
        format = lib.mkDefault "ssh";
        signByDefault = lib.mkDefault (cfg.signing.key != null);
      };
    }) ];
  };
}
