{ inputs }:
let
  lib = inputs.nixpkgs.lib;
in
rec {
  system = "x86_64-linux";
  mkSystem = selectedModules: settings: lib.nixosSystem {
    inherit system;
    modules = selectedModules ++ [ { system.stateVersion = "26.05"; } settings ];
  };
  mkHome = selectedModules: settings: inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    modules = selectedModules ++ [ {
      home = {
        username = lib.mkDefault "test";
        homeDirectory = lib.mkDefault "/home/test";
        stateVersion = lib.mkDefault "26.05";
      };
    } settings ];
  };
  extend = configuration: settings: configuration.extendModules { modules = [ settings ]; };
  check = message: condition: assert lib.assertMsg condition message; true;
  failsEvaluation = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  ports = configuration: interface:
    configuration.config.networking.firewall.interfaces.${interface}.allowedTCPPorts or [];
  alloyTexts = configuration: builtins.mapAttrs (_: file: file.text)
    (lib.filterAttrs (name: _: lib.hasPrefix "alloy/" name) configuration.config.environment.etc);
  failedAssertion = configuration: message: lib.any
    (entry: !entry.assertion && entry.message == message)
    configuration.config.assertions;

  # Inspect supporting config too: an inactive enable flag alone is insufficient.
  cadvisorInactive = configuration:
    !configuration.config.services.cadvisor.enable
    && !(configuration.config.systemd.services ? cadvisor)
    && configuration.config.services.cadvisor.extraOptions == []
    && !(builtins.elem 8081 configuration.config.networking.firewall.allowedTCPPorts)
    && lib.all
      (interface: !(builtins.elem 8081 interface.allowedTCPPorts))
      (builtins.attrValues configuration.config.networking.firewall.interfaces);
}
