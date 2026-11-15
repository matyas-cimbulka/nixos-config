{ config, lib, deploymentHelpers, ... }:
let
  inherit (deploymentHelpers) check;
  preview = config.flake.lib.desktopPreview;
  machine = preview.config;
  home = machine.home-manager.users.matyas;
  productionHome = config.flake.nixosConfigurations.pella.config.home-manager.users.matyas;
  previewBuild = config.flake.checks.x86_64-linux.build-desktop-preview;
  smoke = config.flake.packages.x86_64-linux.desktop-smoke;
in
{
  flake.lib.deploymentTests.desktop = {
    exposes-shared-preview = check "The desktop preview must expose its shared VM configuration for preview and runtime checks."
      (config.flake.lib ? desktopPreview);
    uses-production-desktop = check "The preview must share pella's desktop configuration apart from its virtual monitor settings."
      (machine.programs.hyprland.enable && machine.programs.hyprland.withUWSM
        && machine.services.displayManager.noctalia-greeter.enable && machine.services.greetd.enable
        && builtins.removeAttrs machine.services.displayManager.noctalia-greeter.settings [ "output" ]
          == builtins.removeAttrs config.flake.nixosConfigurations.pella.config.services.displayManager.noctalia-greeter.settings [ "output" ]
        && machine.services.gnome.gnome-keyring.enable && machine.networking.networkmanager.enable
        && home.programs.noctalia.enable && machine.time.timeZone == config.flake.nixosConfigurations.pella.config.time.timeZone
        && toString home.xdg.configFile."noctalia/config.toml".source
          == toString productionHome.xdg.configFile."noctalia/config.toml".source
        && home.wayland.windowManager.hyprland.configType == "lua"
        && builtins.removeAttrs home.wayland.windowManager.hyprland.settings [ "monitor" ]
          == builtins.removeAttrs productionHome.wayland.windowManager.hyprland.settings [ "monitor" ]
        && home.wayland.windowManager.hyprland.extraConfig == productionHome.wayland.windowManager.hyprland.extraConfig
        && home.programs.ghostty.settings == productionHome.programs.ghostty.settings);
    activates-home-on-writable-store = check "Home Manager must actually activate in the preview, with a writable guest store overlay."
      (machine.virtualisation.writableStore && machine.systemd.services.home-manager-matyas.enable
        && builtins.elem "multi-user.target" machine.systemd.services.home-manager-matyas.wantedBy);
    keeps-nix-store-with-its-database = check "The persistent preview must retain writable store paths alongside its Nix database across reboot."
      (machine.virtualisation.writableStore && !machine.virtualisation.writableStoreUseTmpfs);
    pins-only-the-virtual-display = check "Both preview screens must explicitly use 1920x1080 at scale 1 while pella keeps automatic monitor detection."
      (machine.services.displayManager.noctalia-greeter.settings.output.width == 1920
        && machine.services.displayManager.noctalia-greeter.settings.output.height == 1080
        && machine.services.displayManager.noctalia-greeter.settings.output.scale == 1.0
        && home.wayland.windowManager.hyprland.settings.monitor.mode == "1920x1080@60"
        && home.wayland.windowManager.hyprland.settings.monitor.scale == 1.0
        && productionHome.wayland.windowManager.hyprland.settings.monitor.mode == "preferred"
        && productionHome.wayland.windowManager.hyprland.settings.monitor.scale == "auto");
    isolates-installation-and-credentials = check "The preview must use disposable virtual storage and test credentials without production disk, TPM, Tailscale, or SSH access."
      (!(machine.boot.initrd.luks.devices ? cryptroot) && !machine.security.tpm2.enable
        && !machine.services.tailscale.enable && !machine.services.openssh.enable
        && machine.users.users.matyas.hashedPasswordFile == null
        && machine.users.users.matyas.initialPassword == "test-only"
        && machine.services.getty.autologinUser == null
        && machine.users.users.matyas.openssh.authorizedKeys.keys == []
        && machine.virtualisation.forwardPorts == []
        && lib.all (mount: !(lib.hasInfix "nvme" mount.device)) (builtins.attrValues machine.fileSystems));
    builds-preview-without-starting-it = check "The flake check must build the runnable VM, while the explicit app starts the same artifact."
      (config.flake.packages.x86_64-linux.desktop-preview.drvPath == previewBuild.drvPath
        && config.flake.apps.x86_64-linux.desktop-preview.program == "${previewBuild}/bin/desktop-preview");
    keeps-rendering-inside-guest = check "The desktop fixture must render at 1920x1080 without binding a host GPU or requiring a host display."
      (machine.environment.sessionVariables.LIBGL_ALWAYS_SOFTWARE == "1"
        && lib.hasInfix "WLR_RENDERER_ALLOW_SOFTWARE=1" machine.services.greetd.settings.default_session.command
        && lib.hasInfix "WLR_NO_HARDWARE_CURSORS=1" machine.services.greetd.settings.default_session.command
        && !(lib.hasInfix "WLR_RENDERER_ALLOW_SOFTWARE" config.flake.nixosConfigurations.pella.config.services.greetd.settings.default_session.command)
        && !(lib.hasInfix "WLR_NO_HARDWARE_CURSORS" config.flake.nixosConfigurations.pella.config.services.greetd.settings.default_session.command)
        && builtins.elem "-device virtio-gpu-pci,xres=1920,yres=1080" machine.virtualisation.qemu.options
        && lib.all (option: !(lib.hasInfix "/dev/dri" option) && !(lib.hasInfix "gl=on" option)) machine.virtualisation.qemu.options);
    registers-headless-smoke-test = check "The proven headless desktop test must run through flake checks and declare its remote-builder requirements."
      (config.flake.checks.x86_64-linux ? runtime-desktop
        && config.flake.checks.x86_64-linux.runtime-desktop.drvPath
          == smoke.drvPath
        # runTest wraps the derivation; inspect the actual builder attributes.
        && smoke.config.rawTestDerivation.requiredSystemFeatures == [ "kvm" "nixos-test" ]
        && smoke.config.qemu.forceAccel);
  };
}
