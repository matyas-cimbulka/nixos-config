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
  home = active.config.home-manager.users.matyas;
  standaloneHome = config.flake.homeConfigurations.matyas-workstation;
in
{
  flake.lib.compositionTests.workstation-profile = {
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
