{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check;
  active = mkSystem [ (config.flake.modules.nixos.noctalia or {}) ] {};
  disabled = extend active { programs.noctalia.enable = false; };
  withoutIntegrations = extend active { programs.noctalia.recommendedServices.enable = false; };
  machine = active.config;
in
{
  flake.lib.compositionTests.noctalia = {
    selects-system-support = check "Noctalia should supply desktop integration services, audio, and authentication support."
      (machine.programs.noctalia.enable && machine.programs.noctalia.recommendedServices.enable
        && machine.networking.networkmanager.enable && machine.hardware.bluetooth.enable
        && machine.services.upower.enable && machine.services.power-profiles-daemon.enable
        && machine.services.pipewire.enable && machine.services.pipewire.alsa.enable
        && machine.services.pipewire.pulse.enable && machine.security.rtkit.enable
        && machine.security.polkit.enable && machine.xdg.sounds.enable);
    supplies-lock-authentication = check "The pinned Noctalia lock screen authenticates through the existing login PAM password stack."
      (machine.programs.noctalia.enable && machine.security.pam.services.login.unixAuth
        && lib.hasInfix "pam_unix.so" machine.security.pam.services.login.text);
    leaves-user-startup-to-home-manager = check "System integration should not also start a second Noctalia instance."
      (machine.programs.noctalia.enable && !machine.programs.noctalia.systemd.enable);
    integration-services-can-be-disabled = check "The native recommended-services opt-out should remove its default integrations."
      (withoutIntegrations.config.programs.noctalia.enable
        && !withoutIntegrations.config.networking.networkmanager.enable
        && !withoutIntegrations.config.hardware.bluetooth.enable
        && !withoutIntegrations.config.services.upower.enable
        && !withoutIntegrations.config.services.power-profiles-daemon.enable);
    disabling-removes-support = check "An unselected Noctalia feature should leave no desktop audio or integration contributions."
      (!disabled.config.services.pipewire.enable && !disabled.config.security.rtkit.enable
        && !disabled.config.hardware.bluetooth.enable && !disabled.config.services.upower.enable);
  };
}
