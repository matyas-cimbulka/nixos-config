{
  flake.modules.nixos.docker =
    { lib, ... }:
    {
      config = {
        virtualisation = {
          docker.enable = lib.mkDefault true;

          oci-containers.backend = lib.mkDefault "docker";
        };
      };
    };
}
