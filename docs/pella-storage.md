# Pella storage and boot

This is the storage foundation for the ASUS PN53 workstation. The initial
[Hyprland/Ghostty desktop](workstation-desktop.md) is configured separately;
Noctalia and the remaining desktop integration will follow. Nothing here installs
NixOS on the running Ubuntu system.

## Layout

Disko targets `/dev/disk/by-id/nvme-eui.e8238fa6bf530001001b448b4fa70f16`.
The GPT contains a 2 GiB FAT EFI partition at `/boot`; the remaining space is a
LUKS2 container named `cryptroot`, containing one Btrfs filesystem.

| Subvolume | Mount | Purpose |
| --- | --- | --- |
| `@root` | `/` | Recreated on every boot |
| `@root-blank` | Unmounted | Empty, read-only root baseline |
| `@nix` | `/nix` | Store, database, and system generations |
| `@home` | `/home` | Entire user homes |
| `@persist` | `/persist` | Selected machine state and runtime secrets |
| `@log` | `/var/log` | Journals and other logs |
| `@home-snapshots` | `/home/.snapshots` | Home snapshot history |
| `@persist-snapshots` | `/persist/.snapshots` | Machine-state snapshot history |

Mounted Btrfs subvolumes use `compress=zstd:3`. Subvolumes share free space; no
fixed sizes or quotas are assigned. More can be added later, but moving existing
data into a new subvolume is a separate migration. Snapshots do not recursively
capture nested subvolumes.

The initrd waits for `/dev/mapper/cryptroot`, validates the read-only baseline,
creates a replacement root, and recursively removes the previous root before
`sysroot.mount`. Only explicitly persisted state survives. There is no root archive.

Impermanence retains `/etc/machine-id`, `/var/lib/nixos`, NetworkManager state,
Secure Boot keys, `/var/lib/systemd` (including measured-boot policy), and
`/var/lib/pcrlock.d` (measured-boot components). Bluetooth and Tailscale state are
retained when those services are enabled. `/persist` and its snapshot store are
root-only. Private keys and password hashes belong on this encrypted runtime
filesystem, never in the flake or store.
NetworkManager saves connection profiles under
`/var/lib/NetworkManager/system-connections` so settings changed in the UI survive
the root reset along with its other state.

## Memory and recovery

Zram uses zstd compression with logical capacity equal to 50% of RAM; it allocates
memory as used. There is no disk swap and no hibernation. Shutdown and ordinary
suspend remain available.

Snapper snapshots `/home` hourly, retaining up to 24 hourly, 7 daily, 4 weekly,
and 3 monthly snapshots. Matyas can access home snapshots. A separate daily timer
snapshots `/persist`, retaining up to 7 daily and 4 weekly snapshots; these are
root-only because they include credentials. Counts are retention buckets, not
additive guarantees of distinct snapshots. Cleanup runs through Snapper's timer.

For file recovery, inspect `snapper -c home list` and copy the required file from
`/home/.snapshots/<number>/snapshot/`. Do not use `snapper rollback` to change the
default Btrfs subvolume: this machine mounts named subvolumes explicitly. Recover
machine-state files deliberately while the affected service is stopped. Restoring
TPM policy or signing state requires particular care because it must match the
boot artifacts and enrolled TPM policy.

Use NixOS generations for system rollback. `/`, `/nix`, and logs have no Snapper
policy. Snapshots remain on the same SSD and do not cover disk loss. Remote backup
and independent remote retention are deferred; this layout permits later Btrfs
replication without replacing the local snapshot policy.

## Installation inputs and hardware acceptance

Installation and firmware enrollment are separate, explicit operations. Before
installing, verify the disk identity again from the installer. Disko's format
operation will erase the selected disk. Do not run it from the current Ubuntu
session as part of configuration validation.

After mounting the new filesystem at `/mnt`, provision these runtime inputs:

- A nonempty password hash at `/mnt/persist/secrets/matyas-password`, owned by
  root with mode `0600`, under a root-only `secrets` directory. Mutable account
  passwords are disabled; changing this file is how the configured password is
  changed. Activation refuses a missing or empty hash.
- An sbctl key bundle in `/mnt/persist/var/lib/sbctl`, owned by root and protected
  with mode `0700`. Make it available at `/mnt/var/lib/sbctl` before the installer
  runs the bootloader hook. Generate keys with sbctl and stage its complete bundle
  there; do not copy keys into this repository. Unsigned boot artifacts are rejected.
- A working LUKS recovery credential stored outside this workstation, available
  before relying on TPM unlocking. The installer initially needs this credential
  to open the volume; a boot prompt is expected until TPM enrollment is complete.

Follow the locked Lanzaboote version's [Secure Boot setup guide](https://lanzaboote.org/getting-started/enable-secure-boot.html)
and [measured boot guide](https://lanzaboote.org/how-to-guides/enable-measured-boot.html).
The order is: install signed artifacts, verify them, enroll firmware keys, enable
and verify Secure Boot, boot the installed system, check `systemd-pcrlock`
support, then enroll the LUKS TPM policy. Keep the recovery credential available
throughout. Firmware key enrollment must preserve the device's required vendor
trust; follow the guide's hardware-specific instructions.

The configured policy measures PCRs 0, 4, and 7 and retains four boot generations.
Lanzaboote updates the allowed measurements on rebuild. Both the policy and
components are persisted. Enroll using `systemd-cryptenroll` with
`--tpm2-device=auto`, `--tpm2-pcrlock=/var/lib/systemd/pcrlock.json`, and
`--tpm2-with-pin=no` against the LUKS partition. No PIN is the deliberate choice
for automatic startup. TPM enrollment does not happen merely by enabling these
modules. Firmware updates or policy changes may require the recovery credential
and policy re-enrollment.

Acceptance on the physical workstation must verify Secure Boot status, signed
boot artifacts, TPM unlock without a prompt, recovery-key unlock, a system rebuild
followed by another automatic unlock, root reset with home/state retained, local
snapshot recovery, and suspend/resume. Automated validation is described in
[`tests/README.md`](../tests/README.md).

## Planned installation automation

Installation is deferred. The following workflow is agreed but is not yet
implemented in the Nix configuration or an installer script.

Use the MacBook to orchestrate `nixos-anywhere`, with Linux builds performed on
the target through `--build-on remote`. A pella-specific wrapper will retrieve
the LUKS recovery passphrase from 1Password using `op read`, supply it through
`--disk-encryption-keys`, and stage the login password hash and signing-key bundle
before installation. Disko needs an installation-only `passwordFile` for this;
the temporary installer secret must not become a boot-time key-file dependency.
Secrets must remain outside Git, the Nix store, command arguments, and logs, with
temporary material cleaned up after use. Keep the recovery passphrase accessible
from the MacBook or phone when pella is unavailable.

Enable Lanzaboote's automatic Secure Boot key enrollment as part of that workflow:

- Generate and persist signing keys during installation, keeping
  `boot.lanzaboote.allowUnsigned = false`.
- Enable `boot.lanzaboote.autoEnrollKeys.enable` and retain Microsoft certificates.
- Preserve firmware-provided certificates where supported, after checking the
  ASUS firmware requirements. Leave experimental certificate-enrollment options
  and the `allowBrickingMyMachine` override disabled.
- Initially keep `boot.lanzaboote.autoEnrollKeys.autoReboot = false` so the
  enrollment reboot is deliberate.
- Enter Secure Boot Setup Mode through the local firmware interface. Lanzaboote
  prepares enrollment files; systemd-boot enrolls them on a subsequent boot.
- Verify Secure Boot before enrolling TPM disk unlocking. An initial recovery
  passphrase prompt is expected until TPM enrollment is complete.

Automatic enrollment changes firmware trust just as manual enrollment does;
certificate compatibility on the PN53 still needs physical verification. The
existing persistence already retains the signing keys. Firmware-key enrollment
and LUKS TPM enrollment are separate steps; the installer wrapper must not assume
that enabling the former performs the latter. Driving post-boot enrollment from
the MacBook would also require an explicit SSH-access plan for the installed host.

The intended operator workflow is one installer command, one local firmware visit,
and a controlled post-boot enrollment and acceptance step. See the upstream
[`nixos-anywhere` secret provisioning guide](https://nix-community.github.io/nixos-anywhere/howtos/secrets.html)
and [Lanzaboote automatic enrollment guide](https://nix-community.github.io/lanzaboote/how-to-guides/automatically-enroll-keys.html).
