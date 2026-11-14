{
  flake.modules.nixos.gnome-keyring = { lib, ... }: {
    services.gnome.gnome-keyring.enable = lib.mkDefault true;
  };
}
