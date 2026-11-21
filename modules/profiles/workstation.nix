{ config, lib, ... }:
let
  nixos = config.flake.modules.nixos;
  homeManager = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.workstation-profile = { config, pkgs, ... }:
  let
    home = config.home-manager.users.matyas;
    desktopAppearance = config.services.displayManager.noctalia-greeter.enable && home.programs.noctalia.enable;
  in
  {
    imports = [
      nixos.base-profile
      nixos.home-manager
      nixos.gnome-keyring
      nixos.hyprland
      nixos.noctalia
      nixos.noctalia-greeter
      nixos.onepassword
      nixos.nautilus
      nixos.matyas
    ];

    security.sudo.execWheelOnly = true;
    programs = {
      chromium.enable = lib.mkDefault home.programs.google-chrome.enable;
      _1password-gui.polkitPolicyOwners = [ "matyas" ];
    };
    services.displayManager.noctalia-greeter.settings.appearance = lib.mkIf desktopAppearance {
      scheme = lib.mkDefault "Catppuccin";
      theme_mode = lib.mkDefault "dark";
      font_family = lib.mkDefault home.programs.noctalia.settings.shell.font_family;
      wallpaper.path = lib.mkDefault home.programs.noctalia.settings.wallpaper.default.path;
    };
    fonts.packages = lib.mkIf desktopAppearance [ pkgs.inter ];

    networking = {
      firewall.enable = lib.mkDefault true;
      networkmanager.enable = lib.mkDefault true;
      nftables.enable = lib.mkDefault true;
      useDHCP = lib.mkDefault false;
      useNetworkd = lib.mkDefault false;
    };

    users.users.matyas.extraGroups = [ "networkmanager" ];

    home-manager.users.matyas.imports = [
      homeManager.matyas-workstation
    ];
  };
}
