{ inputs, config, lib, ... }:
let
  targetSystem = "x86_64-linux";
  # Both consumers import this module; desktop features still come from the real profile.
  desktop = { config, pkgs, lib, ... }: {
    imports = [ configModule ];

    networking.hostName = "pella-preview";
    system.stateVersion = "26.11";

    users.users.matyas = {
      uid = 1000;
      initialPassword = "test-only";
      openssh.authorizedKeys.keys = lib.mkForce [];
    };

    # Only the disposable VM logs in automatically. A later greeter takes over.
    services.getty.autologinUser = lib.mkIf (!config.services.greetd.enable) "matyas";
    programs.fish.loginShellInit = lib.mkIf (!config.services.greetd.enable) ''
      if test "$USER" = matyas; and test (tty) = /dev/tty1
        exec uwsm start -- hyprland.desktop
      end
    '';

    # Keep software rendering inside the guest: builders need no host GPU or display.
    environment.sessionVariables.LIBGL_ALWAYS_SOFTWARE = "1";
    environment.systemPackages = [ pkgs.jq ];
    boot.kernelModules = [ "virtio_gpu" ];
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      diskSize = 8192;
      graphics = true;
      writableStore = true;
      qemu.options = [ "-vga none" "-device virtio-gpu-pci,xres=1280,yres=800" ];
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
        nodes.pella = desktop;
        enableOCR = true;
        globalTimeout = 300;
        testScript = builtins.readFile ./desktop.py;
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
