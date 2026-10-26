{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.tycho-microvms = { config, lib, pkgs, ... }:
  let
    dependentVmServices = map
      (name: "microvm@{name}")
      (lib.filter (name: name != "anderson")
        (builtins.attrNames config.microvm.vms));
  in
  {
    sops.secrets.tailscale-vm-oauth = { };

    microvm.vms = {
      anderson.config.imports = [ flakeConfig.flake.modules.nixos.anderson ];
      test-microvm.config.imports = [ flakeConfig.flake.modules.nixos.test-microvm ];
      
      behemoth.config = {
        imports = [ flakeConfig.flake.modules.nixos.behemoth ];

        microvm.credentialFiles.tailscale-vm-oauth =
          "/run/credentials/microvm@behemoth.service/tailscale-vm-oauth";
      };
    };

    # systemd.services."microvm@behemoth" = {
    #   requires = [ "sops-install-secrets.service" ];
    #   after = [ "sops-install-secrets.service" ];

    #   serviceConfig.LoadCredential = [
    #     "tailscale-vm-oauth:${config.sops.secrets.tailscale-vm-oauth.path}"
    #   ];
    # };

    systemd.services = lib.mkMerge [
      {
        "microvm@behemoth" = {
          requires = [ "sops-install-secrets.service" ];
          after = [ "sops-install-secrets.service" ];

          serviceConfig.LoadCredential = [
            "tailscale-vm-oauth:${config.sops.secrets.tailscale-vm-oauth.path}"
          ];
        };

        anderson-dns-ready = {
          description = "Wait for DNS through Anderson";

          requires = [ "microvm@anderson.service" ];
          after = [ "microvm@anderson.service" ];

          path = [
            pkgs.dnsutils
            pkgs.gnugrep
            pkgs.coreutils
          ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = 120s;
          };

          script = ''
            echo "Waiting for Anderson to resolve google.com";

            until dig @10.77.0.2 google.com A \
              +time=1 +tries=1 +short |
              grep -Eq '^[0-9]+(\.[0-9]+){3}$'
            do
              sleep 1
            done

            echo "DNS through Anderson is ready"
          '';
        };
      }
      
      (lib.genAttrs dependentVmServices (_: {
        requires = [ "anderson-dns-ready.service" ];
        after = [ "anderson-dns-ready.service" ]; 
      }))
    ];

  };
}