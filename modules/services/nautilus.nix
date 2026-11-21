{
  flake.modules.nixos.nautilus = { config, lib, pkgs, ... }:
  let cfg = config.programs.nautilus;
  in {
    options.programs.nautilus = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable GNOME Files and its file-service integration.";
      };
      package = lib.mkPackageOption pkgs "nautilus" {};
    };
    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
      services = {
        dbus.packages = [ cfg.package ];
        gvfs.enable = lib.mkDefault true;
      };
    };
  };
}
