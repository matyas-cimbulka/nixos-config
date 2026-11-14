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
    uses-production-desktop = check "The preview must select the real workstation desktop and generate the same personal configuration as pella."
      (machine.programs.hyprland.enable && machine.programs.hyprland.withUWSM
        && machine.services.gnome.gnome-keyring.enable && machine.networking.networkmanager.enable
        && home.wayland.windowManager.hyprland.configType == "lua"
        && toString home.xdg.configFile."hypr/hyprland.lua".source
          == toString productionHome.xdg.configFile."hypr/hyprland.lua".source
        && home.programs.ghostty.settings == productionHome.programs.ghostty.settings);
    activates-home-on-writable-store = check "Home Manager must actually activate in the preview, with a writable guest store overlay."
      (machine.virtualisation.writableStore && machine.systemd.services.home-manager-matyas.enable
        && builtins.elem "multi-user.target" machine.systemd.services.home-manager-matyas.wantedBy);
    isolates-installation-and-credentials = check "The preview must use disposable virtual storage and test credentials without production disk, TPM, Tailscale, or SSH access."
      (!(machine.boot.initrd.luks.devices ? cryptroot) && !machine.security.tpm2.enable
        && !machine.services.tailscale.enable && !machine.services.openssh.enable
        && machine.users.users.matyas.hashedPasswordFile == null
        && machine.users.users.matyas.initialPassword == "test-only"
        && machine.users.users.matyas.openssh.authorizedKeys.keys == []
        && machine.virtualisation.forwardPorts == []
        && lib.all (mount: !(lib.hasInfix "nvme" mount.device)) (builtins.attrValues machine.fileSystems));
    builds-preview-without-starting-it = check "The flake check must build the runnable VM, while the explicit app starts the same artifact."
      (config.flake.packages.x86_64-linux.desktop-preview.drvPath == previewBuild.drvPath
        && config.flake.apps.x86_64-linux.desktop-preview.program == "${previewBuild}/bin/desktop-preview");
    keeps-rendering-inside-guest = check "The desktop fixture must render without binding a host GPU or requiring a host display."
      (machine.environment.sessionVariables.LIBGL_ALWAYS_SOFTWARE == "1"
        && builtins.elem "-device virtio-gpu-pci,xres=1280,yres=800" machine.virtualisation.qemu.options
        && lib.all (option: !(lib.hasInfix "/dev/dri" option) && !(lib.hasInfix "gl=on" option)) machine.virtualisation.qemu.options);
    registers-headless-smoke-test = check "The proven headless desktop test must run through flake checks and declare its remote-builder requirements."
      (config.flake.checks.x86_64-linux ? runtime-desktop
        && config.flake.checks.x86_64-linux.runtime-desktop.drvPath
          == smoke.drvPath
        # runTest wraps the derivation; inspect the actual builder attributes.
        && smoke.config.rawTestDerivation.requiredSystemFeatures == [ "kvm" "nixos-test" ]);
  };
}
