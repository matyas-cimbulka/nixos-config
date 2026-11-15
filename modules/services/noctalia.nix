{
  flake.modules.nixos.noctalia = { config, lib, ... }: {
    programs.noctalia = {
      enable = lib.mkDefault true;
      recommendedServices.enable = lib.mkDefault true;
    };

    security = lib.mkIf config.programs.noctalia.enable {
      polkit.enable = lib.mkDefault true;
      rtkit.enable = lib.mkDefault true;
    };
    services.pipewire = lib.mkIf config.programs.noctalia.enable {
      enable = lib.mkDefault true;
      alsa.enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
    };
  };
}
