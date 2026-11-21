{
  flake.modules.homeManager.matyas-desktop-onepassword = { config, lib, pkgs, osConfig, ... }:
  let
    cfg = config.programs.onepassword;
    systemApp = if osConfig == null then null else osConfig.programs._1password-gui;
  in {
    options.programs.onepassword = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = systemApp == null || systemApp.enable;
        description = "Enable the personal 1Password desktop and agent configuration.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = if systemApp == null then pkgs._1password-gui else systemApp.package;
        description = "1Password GUI package used for session startup.";
      };
      installPackages = lib.mkOption {
        type = lib.types.bool;
        default = systemApp == null;
        description = "Install the app and CLI through Home Manager; NixOS supplies its system helpers instead.";
      };
      autostart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Start 1Password quietly with the graphical session.";
      };
      sshAgent = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Point SSH and session applications at the 1Password SSH agent; enable the agent once in the app.";
        };
        socket = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/.1password/agent.sock";
          description = "Absolute path to the 1Password SSH agent socket.";
        };
      };
    };
    config = lib.mkMerge [
      (lib.mkIf cfg.enable {
        assertions = [ {
          assertion = systemApp == null || systemApp.enable;
          message = "The 1Password home configuration on NixOS requires programs._1password-gui.enable for system integration.";
        } ];
        home.packages = lib.mkIf cfg.installPackages [ cfg.package pkgs._1password-cli ];
      })
      (lib.mkIf (cfg.enable && cfg.autostart) {
        systemd.user.services.onepassword = {
          Unit = {
            Description = "1Password desktop and SSH agent";
            PartOf = [ config.wayland.systemd.target ];
            After = [ config.wayland.systemd.target ];
          };
          Service = {
            ExecStart = "${lib.getExe cfg.package} --silent";
            Restart = "on-failure";
          };
          Install.WantedBy = [ config.wayland.systemd.target ];
        };
      })
      (lib.mkIf (cfg.enable && cfg.sshAgent.enable) {
        home.sessionVariables.SSH_AUTH_SOCK = cfg.sshAgent.socket;
        programs.ssh = {
          enable = lib.mkDefault true;
          enableDefaultConfig = false;
          settings."*".IdentityAgent = lib.mkDefault cfg.sshAgent.socket;
        };
      })
    ];
  };
}
