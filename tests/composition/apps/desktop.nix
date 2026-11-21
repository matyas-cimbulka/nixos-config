{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem mkHome extend check;
  modules = config.flake.modules;
  system = mkSystem [ modules.nixos.workstation-profile ] {};
  home = system.config.home-manager.users.matyas;
  standalone = config.flake.homeConfigurations.matyas-workstation.config;
  server = (mkHome [ modules.homeManager.matyas-server ] {}).config;
  withoutPassword = extend system { programs._1password-gui.enable = false; };
  withoutChrome = extend system { home-manager.users.matyas.programs.google-chrome.enable = false; };
  disabledHome = mkHome [ (modules.homeManager.matyas-desktop-onepassword or {}) ] {
    programs.onepassword.enable = false;
  };
  extension = "aeblfdkhhhdcdjpifhhbdiojplfjncoa";
in
{
  flake.lib.compositionTests.desktop-apps = {
    password-cli-is-installed = check "The workstation must install the 1Password CLI through NixOS, and through Home Manager when standalone."
      (system.config.programs._1password.enable
        && lib.any (package: toString package == toString system.config.programs._1password.package)
          system.config.environment.systemPackages
        && lib.any (package: lib.getName package == "1password-cli") standalone.home.packages);
    selects-browser = check "The workstation should install Google Chrome and make it the user's default web browser."
      (home.programs.google-chrome.enable
        && home.xdg.mimeApps.defaultApplications."x-scheme-handler/https" == [ "google-chrome.desktop" ]
        && standalone.programs.google-chrome.enable);
    password-system-support = check "The workstation should provide 1Password browser/CLI helpers and account-scoped Polkit integration."
      (system.config.programs._1password-gui.enable && system.config.programs._1password.enable
        && system.config.programs._1password-gui.polkitPolicyOwners == [ "matyas" ]
        && system.config.security.wrappers."1Password-BrowserSupport".setgid
        && system.config.security.wrappers.op.setgid);
    password-session-startup = check "1Password should start silently once with the graphical session and provide the SSH agent to GUI and CLI clients."
      (home.programs.onepassword.enable
        && lib.hasInfix "--silent" (lib.concatStringsSep " " home.systemd.user.services.onepassword.Service.ExecStart)
        && home.systemd.user.services.onepassword.Unit.PartOf == [ "graphical-session.target" ]
        && home.home.sessionVariables.SSH_AUTH_SOCK == "/home/matyas/.1password/agent.sock"
        && lib.hasInfix "identityagent /home/matyas/.1password/agent.sock"
          (lib.toLower home.home.file.".ssh/config".text));
    password-packages-have-one-owner = check "Embedded homes should use the system 1Password package, while standalone homes install their own."
      (!home.programs.onepassword.installPackages && standalone.programs.onepassword.installPackages
        && toString home.programs.onepassword.package == toString system.config.programs._1password-gui.package);
    browser-extension-is-declarative = check "1Password should be installed through Chrome's supported system policy."
      (system.config.programs.chromium.extraOpts.ExtensionSettings.${extension}.installation_mode == "normal_installed");
    password-opt-out-removes-integration = check "Disabling 1Password should remove its home startup, SSH wiring, and browser extension policy."
      (!withoutPassword.config.home-manager.users.matyas.programs.onepassword.enable
        && !(withoutPassword.config.home-manager.users.matyas.systemd.user.services ? onepassword)
        && !(withoutPassword.config.home-manager.users.matyas.home.sessionVariables ? SSH_AUTH_SOCK)
        && !(builtins.hasAttr extension (withoutPassword.config.programs.chromium.extraOpts.ExtensionSettings or {})));
    browser-opt-out-removes-integration = check "Disabling Chrome should remove its defaults and the 1Password extension policy."
      (!(withoutChrome.config.home-manager.users.matyas.xdg.mimeApps.defaultApplications ? "x-scheme-handler/https")
        && !(builtins.hasAttr extension (withoutChrome.config.programs.chromium.extraOpts.ExtensionSettings or {})));
    independent-password-opt-out = check "The home feature must remove all app-specific startup and agent support when disabled."
      (!(disabledHome.config.systemd.user.services ? onepassword)
        && !(disabledHome.config.home.sessionVariables ? SSH_AUTH_SOCK));
    inherits-unrestricted-package-policy = check "The workstation should inherit base policy allowing all unfree packages."
      ((system.config.nixpkgs.config.allowUnfree or false) && (system.pkgs.config.allowUnfree or false));
    server-remains-cli-only = check "Servers should not gain a browser, editor GUI, or desktop password app."
      (!server.programs.google-chrome.enable && !server.programs.vscode.enable
        && !(server.systemd.user.services ? onepassword));
  };
}
