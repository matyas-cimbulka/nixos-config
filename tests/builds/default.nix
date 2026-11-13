{ config, lib, ... }:
{
  perSystem = { pkgs, system, ... }:
    let
      hosts = config.flake.nixosConfigurations;
      hostBuilds = lib.mapAttrs'
        (name: host: lib.nameValuePair "build-host-${name}" host.config.system.build.toplevel)
        hosts;
      guestBuilds = lib.concatMapAttrs
        (hostName: host: lib.mapAttrs'
          (name: vm: lib.nameValuePair "build-guest-${hostName}-${name}" vm.config.config.system.build.toplevel)
          (host.config.microvm.vms or {}))
        hosts;
      homeBuilds = lib.mapAttrs'
        (name: home: lib.nameValuePair "build-home-${name}" home.activationPackage)
        config.flake.homeConfigurations;
      # Register the actual outputs, not success markers around their evaluation.
      builds = lib.filterAttrs (_: build: build.system == system)
        (hostBuilds // guestBuilds // homeBuilds);
    in
    {
      checks = builds // lib.optionalAttrs (builds != {}) {
        build-all = pkgs.linkFarm "configuration-builds"
          (lib.mapAttrsToList (name: path: { inherit name path; }) builds);
      };
    };
}
