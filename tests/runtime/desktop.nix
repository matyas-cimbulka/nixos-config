{ inputs, config, lib, ... }:
let
  deployment = config.flake.nixosConfigurations.pella.config;
  targetSystem = deployment.nixpkgs.hostPlatform.system;
  borrowedSourceName = "desktop-preview-nix-source.nix";
  borrowedSourceContents = "true";
  borrowedSource = builtins.toFile borrowedSourceName borrowedSourceContents;
  # Both consumers import this module; desktop features still come from the real profile.
  desktop = { config, pkgs, lib, ... }: {
    imports = [ configModule ];

    networking.hostName = "pella-preview";
    time.timeZone = deployment.time.timeZone;
    system.stateVersion = "26.11";

    users.users.matyas = {
      uid = 1000;
      initialPassword = "test-only";
      openssh.authorizedKeys.keys = lib.mkForce [];
    };

    services = {
      getty.autologinUser = lib.mkForce null;
      displayManager.noctalia-greeter.settings.output = {
        width = 1920;
        height = 1080;
        scale = 1.0;
      };
      # greetd starts a fresh session environment, so pass renderer and cursor flags to its command.
      greetd.settings.default_session.command = lib.mkIf config.services.displayManager.noctalia-greeter.enable
        (lib.escapeShellArgs ([ "${pkgs.coreutils}/bin/env" "WLR_RENDERER_ALLOW_SOFTWARE=1" "WLR_NO_HARDWARE_CURSORS=1"
          (lib.getExe' config.services.displayManager.noctalia-greeter.package "noctalia-greeter-session")
        ] ++ config.services.displayManager.noctalia-greeter.extraArgs));
    };
    home-manager.users.matyas.wayland.windowManager.hyprland.settings.monitor = {
      mode = lib.mkForce "1920x1080@60";
      scale = lib.mkForce 1.0;
    };

    environment = {
      # Keep software rendering inside the guest: builders need no host GPU or display.
      sessionVariables.LIBGL_ALWAYS_SOFTWARE = "1";
      systemPackages = [ pkgs.jq pkgs.libnotify (pkgs.python3.withPackages (packages: [ packages.dbus-python ])) ];
      etc = {
        "desktop-test/keyring.py".source = ./desktop-keyring.py;
        "desktop-test/tray.py".source = ./desktop-tray.py;
        "desktop-test/browser.html".text = "<html><title>Pella browser check</title><body>Desktop browser ready</body></html>";
        "desktop-test/editor.nix".text = "# Workstation editor ready\n{}\n";
        "desktop-test/nix".source = pkgs.writeTextDir "flake.nix" ''
        {
          outputs = _:
            assert import (builtins.toFile ${builtins.toJSON borrowedSourceName} ${builtins.toJSON borrowedSourceContents});
            let
              # Restore store references after serializing the fixture into a flake.
              bash = builtins.appendContext "${pkgs.bash}" { "${pkgs.bash}".path = true; };
              coreutils = builtins.appendContext "${pkgs.coreutils}" { "${pkgs.coreutils}".path = true; };
              probe = derivation {
                name = "desktop-preview-nix-probe";
                system = "${pkgs.stdenv.hostPlatform.system}";
                builder = "''${bash}/bin/bash";
                args = [ "-c" "''${coreutils}/bin/mkdir -p $out/bin; printf '#!''${bash}/bin/bash\\necho Desktop Nix works\\n' > $out/bin/desktop-preview-nix-probe; ''${coreutils}/bin/chmod +x $out/bin/desktop-preview-nix-probe" ];
              };
            in {
              packages.${pkgs.stdenv.hostPlatform.system}.default = probe;
            };
        }
        '';
      };
    };
    # The borrowed host store can change between launches while the guest DB persists.
    # Reconcile it after loading the current closure and before the daemon can serve clients.
    systemd.services.register-nix-paths.postStart = lib.mkIf config.nix.enable ''
      ${lib.getExe' config.nix.package.out "nix-store"} --store local --verify
    '';
    boot.kernelModules = [ "virtio_gpu" ];
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      diskSize = 8192;
      graphics = true;
      writableStore = true;
      writableStoreUseTmpfs = false;
      qemu.options = [ "-vga none" "-device virtio-gpu-pci,xres=1920,yres=1080" ];
    };
  };
  configModule = config.flake.modules.nixos.workstation-profile;
  preview = inputs.nixpkgs.lib.nixosSystem {
    system = targetSystem;
    modules = [ desktop "${inputs.nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix" ];
  };
in
{
  flake.lib.desktopPreview = preview;

  perSystem = { pkgs, system, ... }:
    let
      vm = preview.config.system.build.vm;
      launcher = pkgs.writeShellApplication {
        name = "desktop-preview";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          umask 077
          preview_state="''${XDG_STATE_HOME:-$HOME/.local/state}/nixos-config/desktop-preview"
          mkdir -p "$preview_state"
          export NIX_DISK_IMAGE="''${NIX_DISK_IMAGE:-$preview_state/pella-preview.qcow2}"
          exec ${vm}/bin/run-pella-preview-vm "$@"
        '';
      };
      smoke = inputs.nixpkgs.lib.nixos.runTest {
        name = "desktop";
        hostPkgs = pkgs;
        qemu.forceAccel = true;
        nodes.pella = desktop;
        enableOCR = true;
        globalTimeout = 600;
        # Driver-only inputs remain visible in the borrowed host store, outside the VM closure.
        testScript = ''
          borrowed_source = "${borrowedSource}"
          borrowed_registration = "${pkgs.closureInfo { rootPaths = [ borrowedSource ]; }}/registration"
        '' + builtins.readFile ./desktop.py;
      };
    in
    lib.mkIf (system == targetSystem) {
      packages = {
        desktop-preview = launcher;
        desktop-test-driver = smoke.driver;
        desktop-smoke = smoke;
      };
      apps.desktop-preview = {
        type = "app";
        program = "${launcher}/bin/desktop-preview";
      };
      checks = {
        build-desktop-preview = launcher;
        runtime-desktop = smoke;
      };
    };
}
