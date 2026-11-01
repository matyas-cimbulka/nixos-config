{
  flake.modules.nixos.cadvisor = {
    networking.firewall.interfaces."lan0".allowedTCPPorts = [ 8081 ];
    
    services.cadvisor = {
      enable = true;

      listenAddress = "0.0.0.0";
      port = 8081;

      extraOptions = [
        "--docker=unix:///var/run/docker.sock"
        "--docker_only=true"
        "--store_container_labels=false"
        
        "--containerd=/run/docker/containerd/containerd.sock"
        "--containerd-namespace=moby"
      ];
    };

    systemd.services.cadvisor.requires = [
      "docker.service"
    ];
  };
}