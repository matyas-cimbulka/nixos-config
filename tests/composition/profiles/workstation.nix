{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check;
  modules = config.flake.modules.nixos;
  active = mkSystem [ modules.workstation-profile ] {};
  custom = extend active {
    networking = {
      firewall.enable = false;
      networkmanager.enable = false;
      useDHCP = true;
      useNetworkd = true;
    };
  };
  customHyprland = extend active {
    programs.hyprland.package = active.pkgs.hyprland.overrideAttrs (_: {
      pname = "hyprland-composition-test";
    });
  };
  withoutKeyring = extend active { services.gnome.gnome-keyring.enable = false; };
  withGreeter = extend active {
    services.greetd = {
      enable = true;
      settings.default_session.command = "${active.pkgs.coreutils}/bin/false";
    };
  };
  home = active.config.home-manager.users.matyas;
  homeHyprland = home.wayland.windowManager.hyprland;
  standaloneHome = config.flake.homeConfigurations.matyas-workstation;
  sessions = lib.concatMap (package: package.providedSessions or [])
    active.config.services.displayManager.sessionPackages;
  coherentHyprlandPackages = system:
    let
      native = system.config.programs.hyprland;
      personal = system.config.home-manager.users.matyas.wayland.windowManager.hyprland;
      samePackage = left: right: toString left == toString right;
    in
      native.enable && personal.enable && system.config.xdg.portal.enable
      && lib.any (samePackage native.portalPackage) system.config.xdg.portal.extraPortals
      # Home Manager may delegate installation to NixOS or use the same final packages.
      && (personal.finalPackage == null || samePackage personal.finalPackage native.package)
      && (personal.finalPortalPackage == null || samePackage personal.finalPortalPackage native.portalPackage);
  keyringLogin = system:
    let pam = system.config.security.pam.services.login;
    in system.config.services.gnome.gnome-keyring.enable && pam.enableGnomeKeyring
      && pam.rules.auth.gnome_keyring.enable && pam.rules.auth.gnome_keyring.control == "optional"
      && pam.rules.session.gnome_keyring.enable && pam.rules.session.gnome_keyring.control == "optional"
      && pam.rules.session.gnome_keyring.settings.auto_start
      && lib.hasInfix "pam_gnome_keyring.so" pam.text;
in
{
  flake.lib.compositionTests.workstation-profile = {
    keyring-supports-password-login = check "Workstation should provide the Secret Service daemon and optional PAM hooks to unlock and start the login keyring."
      (keyringLogin active
        && lib.any (package: toString package == toString active.pkgs.gnome-keyring) active.config.services.dbus.packages
        && !active.config.services.greetd.enable);
    greetd-inherits-keyring-login = check "A future greetd greeter should inherit the keyring-enabled login PAM stack without duplicate keyring hooks."
      (keyringLogin withGreeter
        && lib.hasInfix "auth substack login" withGreeter.config.security.pam.services.greetd.text
        && lib.hasInfix "session include login" withGreeter.config.security.pam.services.greetd.text
        && !(lib.hasInfix "pam_gnome_keyring.so" withGreeter.config.security.pam.services.greetd.text));
    keyring-can-be-disabled = check "Disabling the keyring feature should remove its login hooks and Secret Service registration."
      (!withoutKeyring.config.services.gnome.gnome-keyring.enable
        && !withoutKeyring.config.security.pam.services.login.enableGnomeKeyring
        && !(lib.hasInfix "pam_gnome_keyring.so" withoutKeyring.config.security.pam.services.login.text)
        && !(lib.any (package: toString package == toString withoutKeyring.pkgs.gnome-keyring)
          withoutKeyring.config.services.dbus.packages));
    hyprland-selects-system-and-home = check "Workstation should select both NixOS Hyprland integration and Matyas's Home Manager configuration."
      (active.config.programs.hyprland.enable && homeHyprland.enable);
    hyprland-registers-managed-session = check "Workstation should register a Hyprland session that launches through UWSM."
      (builtins.elem "hyprland-uwsm" sessions);
    hyprland-packages-and-portal-agree = check "Workstation Home Manager should use or delegate to the NixOS compositor and portal packages."
      (coherentHyprlandPackages active);
    hyprland-package-override-stays-coherent = check "Overriding the system compositor should preserve matching Home Manager and portal packages."
      (coherentHyprlandPackages customHyprland);
    hyprland-session-has-one-owner = check "UWSM should manage the Hyprland session without a competing Home Manager session target."
      (active.config.programs.hyprland.enable && homeHyprland.enable
        && active.config.programs.hyprland.withUWSM && active.config.programs.uwsm.enable
        && !homeHyprland.systemd.enable
        && !(home.systemd.user.targets ? hyprland-session));
    hyprland-logout-stops-managed-session = check "The embedded Hyprland configuration should launch applications and log out through UWSM."
      (lib.hasInfix "uwsm app --" (home.xdg.configFile."hypr/hyprland.lua".text or "")
        && lib.hasInfix "uwsm stop" (home.xdg.configFile."hypr/hyprland.lua".text or ""));
    explicitly-selects-common-features = check "Workstation should compose base policy, the Matyas account, and shared Home Manager policy."
      (active.config.users.users.matyas.isNormalUser
        && builtins.elem "flakes" active.config.nix.settings.experimental-features
        && active.config.home-manager.useGlobalPkgs && active.config.home-manager.useUserPackages);
    networkmanager-owns-networking = check "Workstation should use NetworkManager with firewall protection and no competing networkd or DHCP client."
      (active.config.networking.networkmanager.enable
        && active.config.networking.firewall.enable && active.config.networking.nftables.enable
        && !active.config.networking.useNetworkd && !active.config.systemd.network.enable
        && !active.config.networking.useDHCP && !(active.config.systemd.services ? dhcpcd));
    networkmanager-access-preserves-wheel = check "Matyas should have NetworkManager access while retaining wheel membership."
      (lib.all (group: builtins.elem group active.config.users.users.matyas.extraGroups)
        [ "wheel" "networkmanager" ]);
    sudo-requires-authentication = check "Workstation sudo should be restricted to wheel and require a password."
      (active.config.security.sudo.enable && active.config.security.sudo.execWheelOnly
        && active.config.security.sudo.wheelNeedsPassword);
    networking-policy-is-overridable = check "Workstation network defaults should remain deployment-overridable."
      (!custom.config.networking.firewall.enable && !custom.config.networking.networkmanager.enable
        && custom.config.networking.useDHCP && custom.config.networking.useNetworkd);
    embeds-workstation-home-manager = check "Workstation should give Matyas the shared home identity and CLI tools."
      (home.home.username == "matyas" && home.home.homeDirectory == "/home/matyas"
        && home.programs.fish.enable && home.programs.btop.enable && home.programs.neovim.enable);
    embedded-home-matches-standalone = check "Embedded workstation Home Manager should use the same editor, VCS settings, and CLI tools as the exported standalone home."
      (home.programs.git.settings == standaloneHome.config.programs.git.settings
        && home.programs.jujutsu.settings == standaloneHome.config.programs.jujutsu.settings
        && home.home.sessionVariables.EDITOR == standaloneHome.config.home.sessionVariables.EDITOR
        && home.home.sessionVariables.VISUAL == standaloneHome.config.home.sessionVariables.VISUAL
        && home.programs.btop.enable == standaloneHome.config.programs.btop.enable
        && home.programs.neovim.enable == standaloneHome.config.programs.neovim.enable);
    does-not-select-server-or-deployment-services = check "The minimal workstation should leave SSH, monitoring, Docker, credentials, and Tailscale unselected."
      (!active.config.services.openssh.enable && !active.config.services.alloy.enable
        && !active.config.virtualisation.docker.enable && !active.config.services.tailscale.enable
        && !(active.options ? sops));
  };
}
