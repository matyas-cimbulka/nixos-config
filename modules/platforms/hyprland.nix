{
  flake.modules.nixos.hyprland = { lib, ... }: {
    programs.hyprland = {
      enable = lib.mkDefault true;
      withUWSM = lib.mkDefault true;
    };
  };
}
