{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check failsEvaluation failedAssertion;
  module = config.flake.modules.nixos.ephemeral-root;
  active = mkSystem [ module ] {
    deployment.ephemeralRoot.device = "/dev/mapper/testroot";
    fileSystems."/" = {
      device = "/dev/mapper/testroot";
      fsType = "btrfs";
      options = [ "subvol=@root" ];
    };
  };
  disabled = mkSystem [ module ] { deployment.ephemeralRoot.enable = false; };
  missingDevice = mkSystem [ module ] {};
  sameBaseline = extend active { deployment.ephemeralRoot.blankSubvolume = "@root"; };
  wrongFilesystem = extend active { fileSystems."/".fsType = lib.mkForce "ext4"; };
  reset = active.config.boot.initrd.systemd.services.reset-root;
in
{
  flake.lib.compositionTests.ephemeral-root = {
    reset-runs-once-per-boot = check "Root reset must remain active so initrd dependency reloads cannot run it twice."
      (reset.serviceConfig.RemainAfterExit or false);
    reset-orders-after-device-before-root = check "Root reset must require decrypted storage and finish before sysroot.mount."
      (builtins.elem "dev-mapper-testroot.device" reset.requires
        && builtins.elem "dev-mapper-testroot.device" reset.after
        && builtins.elem "sysroot.mount" reset.before
        && builtins.elem "sysroot.mount" reset.requiredBy);
    disabled-root-does-not-require-device = check "Disabling root reset must remove its unit without forcing deployment settings."
      (!(disabled.config.boot.initrd.systemd.services ? reset-root));
    selected-root-requires-device = check "Selected root reset must require an explicit decrypted device."
      (failsEvaluation missingDevice.config.boot.initrd.systemd.services.reset-root.script);
    baseline-cannot-be-the-active-root = check "The blank baseline must never be the root selected for deletion."
      (failedAssertion sameBaseline "Ephemeral root and its read-only baseline must be different subvolumes.");
    requires-matching-btrfs-root = check "Root reset must reject an unrelated root filesystem."
      (failedAssertion wrongFilesystem "Ephemeral root requires / to mount the selected Btrfs device and root subvolume.");
  };
}
