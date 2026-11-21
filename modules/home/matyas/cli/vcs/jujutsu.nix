{
  flake.modules.homeManager.matyas-cli-jj = { config, lib, pkgs, ... }:
  let
    cfg = config.programs.jujutsu;
    development = config.deployment.jujutsu.development;
  in {
    options.deployment.jujutsu.development = {
      enable = lib.mkEnableOption "development identity validation and SSH signing defaults";
      signing = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = development.signing.key != null;
          description = "Sign own commits through SSH when a deployment supplies its public signing key.";
        };
        key = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Public signing key or runtime public-key file reference. Never put a private key here.";
        };
      };
    };
    config = lib.mkMerge [ {
      programs.jujutsu = {
        enable = true;
        settings.ui.default-command = "log";
      };
    } (lib.mkIf (cfg.enable && development.enable) {
      assertions = [
        {
          assertion = (cfg.settings.user.name or "") != "" && (cfg.settings.user.email or "") != "";
          message = "Development Jujutsu requires programs.jujutsu.settings.user.name and user.email.";
        }
        {
          assertion = !development.signing.enable || (development.signing.key != null && development.signing.key != "");
          message = "Development Jujutsu signing requires deployment.jujutsu.development.signing.key.";
        }
      ];
      programs.jujutsu.settings.signing = lib.mkIf development.signing.enable {
        backend = lib.mkDefault "ssh";
        behavior = lib.mkDefault "own";
        key = development.signing.key;
        backends.ssh.program = lib.mkDefault (lib.getExe' pkgs.openssh "ssh-keygen");
      };
    }) ];
  };
}
