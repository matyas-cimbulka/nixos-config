{ host, lib }:
rec {
  inherit host;
  guest = name: host.microvm.vms.${name}.config.config;
  check = message: condition: assert lib.assertMsg condition message; true;
  sameMembers = left: right: lib.sort builtins.lessThan left == lib.sort builtins.lessThan right;
  tcpPorts = machine: interface: machine.networking.firewall.interfaces.${interface}.allowedTCPPorts or [];
  udpPorts = machine: interface: machine.networking.firewall.interfaces.${interface}.allowedUDPPorts or [];
  internalDomain = lib.head (lib.toList host.services.dnsmasq.settings.domain);
  internalHost = machine: "${machine.networking.hostName}.${internalDomain}";
  bridgeName = host.systemd.network.netdevs.microvm-br.netdevConfig.Name;
  bridgeAddress = lib.head (lib.splitString "/" (lib.head host.systemd.network.networks.microvm-br.addresses).Address);

  # Names and source files are explicit test expectations. Read references only,
  # never decrypted files. formatPath handles Grafana's $__file{...} syntax.
  credentialWiring = { vm, service, name, source, consumedPaths, formatPath ? lib.id }:
    let
      machine = guest vm;
      vmService = host.systemd.services."microvm@${vm}";
      guestService = machine.systemd.services.${service};
      hostPath = "/run/credentials/microvm@${vm}.service/${name}";
      guestPath = "/run/credentials/${service}.service/${name}";
    in
    check "${vm}/${service}: credential ${name} must connect its host source, VM forwarding, import, consumer, and startup dependencies."
      (builtins.elem "${name}:${source}" (vmService.serviceConfig.LoadCredential or [])
        && (machine.microvm.credentialFiles.${name} or null) == hostPath
        && builtins.elem name (guestService.serviceConfig.ImportCredential or [])
        && builtins.elem (formatPath guestPath) consumedPaths
        && builtins.elem "sops-install-secrets.service" vmService.requires
        && builtins.elem "sops-install-secrets.service" vmService.after);

  job = machine: name: lib.findFirst
    (entry: entry.job_name == name)
    (throw "Deployment has no Prometheus job named ${name}.")
    machine.services.prometheus.scrapeConfigs;
  targets = machine: name: lib.concatMap (entry: entry.targets) (job machine name).static_configs;
  commandValue = prefix: flags: lib.removePrefix prefix
    (lib.findFirst (lib.hasPrefix prefix) (throw "Deployment command has no ${prefix} flag.") flags);
}
