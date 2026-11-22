{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem check;
  modules = config.flake.modules.nixos;
  system = mkSystem [ modules.docker modules.teleport-control-plane ] {
    deployment.teleport-control-plane = {
      domain = "teleport.cimbulka.net";
      dataVolume = "teleport-data";
    };
  };
  container = system.config.virtualisation.oci-containers.containers.teleport-control-plane;
  mount = lib.findFirst (lib.hasSuffix ":/etc/teleport/teleport.yaml:ro")
    (throw "Teleport must mount its configuration read-only.") container.volumes;
  settings = builtins.fromJSON (builtins.readFile (lib.removeSuffix ":/etc/teleport/teleport.yaml:ro" mount));
in
{
  flake.lib.compositionTests.teleport-control-plane = {
    control-plane-only = check "Teleport should run only Auth and Proxy, persist state, and publish no host ports."
      (settings.auth_service.enabled && settings.proxy_service.enabled && !settings.ssh_service.enabled
        && settings.auth_service.proxy_listener_mode == "multiplex"
        && builtins.elem "teleport-data:/var/lib/teleport" container.volumes
        && container.ports == []);
    passwordless-webauthn-by-default = check "Teleport should default to passwordless WebAuthn at its public hostname."
      (let auth = settings.auth_service.authentication; in
        settings.proxy_service.public_addr == "teleport.cimbulka.net:443"
        && auth.type == "local" && auth.passwordless && auth.connector_name == "passwordless"
        && auth.second_factors == [ "webauthn" ] && auth.webauthn.rp_id == "teleport.cimbulka.net");
  };
}
