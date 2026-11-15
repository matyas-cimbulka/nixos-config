{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check;
  modules = config.flake.modules.nixos;
  active = mkSystem [ (modules.noctalia-greeter or {}) ] {};
  withHyprland = extend active { programs.hyprland = { enable = true; withUWSM = true; }; };
  verboseStart = extend withHyprland { environment.sessionVariables.UWSM_SILENT_START = "0"; };
  disabled = extend withHyprland { services.displayManager.noctalia-greeter.enable = false; };
  machine = active.config;
in
{
  flake.lib.compositionTests.noctalia-greeter = {
    supplies-readable-cursor-theme = check "The greeter should have a system-readable Adwaita cursor theme and explicit cursor size."
      (machine.services.displayManager.noctalia-greeter.cursorTheme.package != null
        && machine.services.displayManager.noctalia-greeter.settings.cursor.theme == "Adwaita"
        && machine.services.displayManager.noctalia-greeter.settings.cursor.size == 24
        && machine.services.displayManager.noctalia-greeter.settings.cursor.path
          == "${machine.services.displayManager.noctalia-greeter.cursorTheme.package}/share/icons");
    owns-graphical-login = check "The greeter feature should start Noctalia through greetd as the unprivileged greeter account."
      (machine.services.displayManager.noctalia-greeter.enable && machine.services.greetd.enable
        && machine.services.greetd.settings.default_session.user == "greeter"
        && lib.hasInfix "noctalia-greeter-session" machine.services.greetd.settings.default_session.command
        && machine.services.accounts-daemon.enable && machine.security.polkit.enable);
    requires-account-and-password = check "The greeter should leave account selection to upstream and require authentication before starting a session."
      (machine.services.displayManager.noctalia-greeter.enable
        && !(machine.services.displayManager.noctalia-greeter.settings ? user)
        && !(machine.services.greetd.settings ? initial_session)
        && !machine.programs.noctalia.enable);
    selects-managed-hyprland-when-available = check "The greeter should select the registered UWSM Hyprland session when both features are enabled."
      ((withHyprland.config.services.displayManager.noctalia-greeter.settings.session.default or null) == "hyprland-uwsm"
        && !(machine.services.displayManager.noctalia-greeter.settings ? session));
    quiets-managed-session-start = check "The graphical greeter should suppress UWSM startup chatter on the TTY while preserving an explicit opt-out."
      ((withHyprland.config.environment.sessionVariables.UWSM_SILENT_START or null) == "1"
        && verboseStart.config.environment.sessionVariables.UWSM_SILENT_START == "0"
        && !(machine.environment.sessionVariables ? UWSM_SILENT_START));
    can-be-disabled = check "Disabling the greeter should remove its login service, state provisioning, and session defaults."
      (!disabled.config.services.greetd.enable && !disabled.config.services.accounts-daemon.enable
        && !(disabled.config.systemd.tmpfiles.settings ? "10-noctalia-greeter")
        && !(disabled.config.services.displayManager.noctalia-greeter.settings ? session)
        && !(disabled.config.environment.sessionVariables ? UWSM_SILENT_START));
  };
}
