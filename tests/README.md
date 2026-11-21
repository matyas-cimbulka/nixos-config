# Configuration tests

## Full builds

`builds/default.nix` registers actual output derivations under `checks`, discovered
from `nixosConfigurations`, their MicroVM definitions, and `homeConfigurations`.
Checks are registered on the derivation's build platform. Current targets are:

- `build-host-tycho`
- `build-host-pella`
- `build-guest-tycho-anderson`, `build-guest-tycho-behemoth`, `build-guest-tycho-thoth`
- `build-home-matyas-server`
- `build-home-matyas-workstation`

Run all host, guest, and home build targets independently of the evaluation suites:

```sh
nix build --no-link --keep-going .#checks.x86_64-linux.build-all
```

Or build one output:

```sh
nix build --no-link .#checks.x86_64-linux.build-guest-tycho-behemoth
```

`build-all` is a link farm referencing every registered build output. Building it
requires those outputs to be realized, either built locally or obtained from a
binary cache. Unlike evaluation-check success markers, these checks cover the
actual system and Home Manager artifacts. A cached result is a successful
realization; it does not mean the output was rebuilt locally.

`nix flake check` includes these builds. `nix flake check --no-build` only evaluates
them. Evaluation failures can stop the full command before builds run; targeted
build commands are useful when diagnosing a separate evaluation failure.

Builds do not activate Home Manager, switch the host, install a bootloader, start
VMs, decrypt production secrets, or contact application APIs. They may download
dependencies. Runtime-pulled Docker images are not fetched or tested by these
system builds. VM boot, networking, credential delivery, and application behavior
remain separate runtime checks.

## Deployment tests

`deployment/default.nix` discovers deployment suite modules and registers
`deployment-<suite>` checks on Tycho's target platform. `deployment/tycho.nix`
evaluates the actual host, all configured guests, and standalone Home Manager.
Guest evaluation tests are discovered from Tycho's VM definitions and exposed as
the `guests` group. Machine suites own the other deployment relationships:

- `tycho.nix`: expected VM membership, matching guest/TAP identities, bridge/NAT
  and DHCP/DNS wiring, startup dependencies, and ephemeral debugging homes.
- `behemoth.nix`: Traefik, Pocket ID, and Tailscale credential chains; ingress
  exposure; co-located Pocket ID routing; telemetry senders; remote Grafana routing.
- `anderson.nix`: Tailscale credentials, DNS/metrics exposure, resolver settings,
  and public versus internal DNS destinations.
- `thoth.nix`: Grafana signing/OAuth credentials and OAuth endpoints, local data
  sources, remote scrape targets and exporter ports, Loki/Tempo forwarding, and
  internal monitoring exposure.
- `pella.nix`: workstation identity and hardware, account and Home Manager,
  encrypted Btrfs layout, persistence, root-reset ordering, zram, local snapshot
  policies, signed measured boot, desktop keyring persistence coverage, and
  complete system derivation evaluation.
- `desktop.nix`: preview/production desktop parity, active Home Manager delivery,
  installation and credential isolation, preview launch/build registration, and
  headless runtime-check builder requirements.

`deployment/helpers.nix` supplies small assertion and configuration lookup helpers.
It is excluded from automatic module discovery. Credential checks explicitly name
the intended source, VM, service, and actual application references. The helper
checks host loading, VM forwarding, guest import, consumed paths, and host startup
dependencies. Grafana references are checked in their `$__file{...}` form. Template
checks inspect SOPS placeholders, not decrypted values.

Tests compare consumers with producer settings where practical. Independent policy
expectations pin the three intended guests, Traefik's current LAN/Tailscale port
selection (including dashboard port 8080 for debugging), and the configured ingress
tailnet IP. That IP's actual ownership still requires a live check.

```sh
nix eval --json .#lib.deploymentTests
nix eval --json .#lib.deploymentTests.behemoth
nix eval --json .#lib.deploymentTests.thoth
nix build --no-link .#checks.x86_64-linux.deployment-tycho \
  .#checks.x86_64-linux.deployment-guests \
  .#checks.x86_64-linux.deployment-behemoth \
  .#checks.x86_64-linux.deployment-anderson \
  .#checks.x86_64-linux.deployment-thoth
```

These checks force the existing evaluation assertions and build only success
markers. They do not build or activate systems, read secret contents, or verify
runtime credential delivery. They also run with `nix flake check`.

## Storage runtime test

```sh
nix build --no-link -L .#checks.x86_64-linux.runtime-pella-storage
```

`runtime/pella-storage.nix` uses Disko's installation test library with the real
pella modules and layout on an 8 GiB disposable virtual disk. It formats and
installs that disk, boots it, exercises Snapper recovery and cleanup, then reboots
to verify root reset, nested-subvolume deletion, persistent data, saved network
profiles, machine identity, and snapshot survival. The physical SSD is never
passed to QEMU.

The fixture replaces hardware detection, boot signing, and TPM unlocking with
virtual hardware, ordinary systemd-boot, and a test-only LUKS key. It also reduces
LUKS memory cost and Snapper's minimum cleanup age for the small VM. Production
retention counts remain in effect. This verifies storage behavior; firmware key
enrollment, measured boot, physical TPM unlocking, and real suspend remain manual
hardware acceptance checks. The test is registered with `nix flake check`.

Disko shares the host store over 9p to avoid copying the full system into each
image. Home Manager activation is disabled in this fixture because its Nix daemon
cannot change ownership of that shared store. The account and Home Manager
configuration still evaluate and build through the production checks; their live
activation needs a separate test on a writable store. The restart check shuts down
and starts the same virtual disk because Disko's custom QEMU exits on guest reboot.

## Desktop preview and runtime test

On an x86_64 Linux desktop, build and launch the interactive preview with:

```sh
nix run .#desktop-preview
```

Build the preview without starting it, including on a remote Linux builder:

```sh
nix build --no-link .#checks.x86_64-linux.build-desktop-preview
```

`runtime/desktop.nix` supplies one desktop fixture to the preview and automated
test. It imports the real workstation profile, including Matyas's Home Manager
configuration, Hyprland, UWSM, Noctalia Greeter, Ghostty, fonts, and GNOME Keyring.
It also carries Chrome, 1Password, VS Code, and Nautilus. The test checks 1Password's
real tray item and system helpers without signing into an account, plus browser
defaults, native Wayland app windows, editable editor settings, and the file-manager
shortcut. It trusts its controlled editor fixture through VS Code's UI and checks
that the configured Nix language server starts. Accounts, extension downloads,
SSH approvals, and Tailscale login are separate manual acceptance checks.
Tailscale is selected by pella rather than the
shared workstation profile, so the preview does not enroll in the tailnet.
It uses virtual hardware and an ordinary disposable filesystem instead of pella's
physical disk, LUKS, TPM, or installation credentials. Home Manager activation is enabled; the
guest gets a writable overlay over the read-only shared Nix store. Its writable
layer stays on the VM disk alongside the Nix database, so packages and derivations
created with Nix survive shutting down and reopening the preview.

The preview allocates four CPUs and 4 GiB RAM. Both the greeter and Hyprland
explicitly use 1920x1080 (16:9) at scale 1, using a virtual GPU and guest Mesa
software rendering. This avoids the interactive viewer selecting a smaller
preferred mode. Production keeps automatic monitor detection; desktop parity
checks exclude only these preview display overrides. The preview's greeter command
explicitly permits wlroots software rendering and forces software cursors;
production keeps normal renderer and hardware cursor selection.
No host GPU is passed through.
The graphical greeter opens the password step for the VM's single `matyas` account;
enter the VM-only password `test-only` to start Hyprland through UWSM. Real password
authentication also creates and unlocks the login keyring through PAM. There are no
forwarded host ports, production private keys, or Tailscale enrollment. The shared
home configuration includes Matyas's public signing key and author identity.

The launcher stores the VM disk at
`${XDG_STATE_HOME:-$HOME/.local/state}/nixos-config/desktop-preview/pella-preview.qcow2`,
outside the checkout. Changes made inside the preview survive closing its window
and launching it again. Stop the VM and remove that disposable disk to reset it,
or select a separate disk with `NIX_DISK_IMAGE=/absolute/path/preview.qcow2`.
Rebuilding uses the current declarative desktop configuration with the saved home
state. The preview never switches the host system or activates the host home.

The read-only store layer is borrowed from the host; its contents can change
between preview launches, including after host garbage collection. The guest
database can therefore retain registrations for borrowed paths that are no longer
visible. After registering the current system closure, the preview automatically
runs `nix-store --store local --verify` before starting the Nix daemon. This checks
path existence and clears stale metadata without hashing every file's contents.
Guest-created store paths, the home directory, and UI settings remain on disk.
Restart an older preview with `nix run .#desktop-preview` to get this startup repair;
manual `sudo nix-store --verify` after each configuration update is unnecessary.

The automated script in `runtime/desktop.py` waits for Home Manager activation,
checks pointer clicks in Noctalia Greeter's appearance menu, logs in, and checks
the UWSM graphical session, unlocked keyring, Noctalia service, and virtual monitor.
Its keyring client opens a Secret Service session and checks the Login collection
through the same connection.
It also checks that UWSM startup messages stay off the TTY but reach the journal,
and builds and runs a local offline flake as Matyas before and after a VM power
cycle to verify writable-store persistence. It also reproduces stale metadata for
a borrowed source path and requires Nix to work after restart without a manual
repair. The guest daemon removes only the isolated fixture through its writable
overlay; assertions confirm the host export stays read-only and retains the file.
It opens Ghostty
using Super+Return and checks keyboard input, then opens three scrolling columns
to verify their geometry and directional focus. Super+Tab must load the native
ScrollOverview plugin without configuration errors and enter its keyboard submap.
Selecting an off-screen column must focus it without changing its size. The test
also navigates vertically through an empty workspace to a fourth window on another
workspace, checks Enter and Escape restore the normal keymap, and captures both
overview views for visual review. It also clicks an overview window to check
pointer selection through the custom submap. The test then exercises workspace movement,
the Noctalia launcher and control center over a terminal, notification delivery,
UI overrides across service restart, and password lock/unlock. Incorrect passwords
are rejected by both the greeter and lock screen, and logout must return to the
graphical greeter.
It captures screenshots for visual review. It uses a fresh disposable disk,
not the interactive preview's saved state. Visual approval of colors, layout, and
spacing remains a separate review; the runtime test checks startup and interaction.

Run the automated test or build its driver for direct debugging:

```sh
nix build --no-link -L .#checks.x86_64-linux.runtime-desktop
nix build --out-link /tmp/desktop-test-driver .#packages.x86_64-linux.desktop-test-driver
mkdir -p /tmp/desktop-test-output
env -u DISPLAY -u WAYLAND_DISPLAY /tmp/desktop-test-driver/bin/nixos-test-driver \
  -o /tmp/desktop-test-output
```

The driver saves screenshots and logs in its output directory. For an interactive
Python session, append `--interactive`, then use `start_all()`, `test_script()`,
and commands such as `pella.screenshot("review")` or `pella.send_key("meta_l-ret")`.
Only one driver using these default machine/network state paths should run per
user at a time.

Both `build-desktop-preview` and `runtime-desktop` are registered with
`nix flake check`. `nix flake check --no-build` only evaluates them; a full check
realizes the preview and runs the VM test unless a cached result is reused.
Remote builders can build the preview artifacts without a display or GPU. Running
the preview remains an explicit local action on x86_64 Linux; building it remotely
from a Mac does not make the Linux launcher executable on macOS.

The runtime derivation declares `kvm` and `nixos-test` through the NixOS test
framework. Configure a suitable x86_64 Linux builder with those supported features
and ensure its actual build users can open `/dev/kvm` inside the sandbox. Merely
advertising a feature does not grant device access. The graphical runtime check
requires KVM explicitly and fails immediately if the build user cannot access it,
instead of spending minutes rendering through CPU emulation. No check is
conditionally skipped based on the evaluator's devices, display environment, or
builder availability.

To collect results even when individual assertions fail:

```sh
nix eval --json .#lib.deploymentTests --apply '
  suites: builtins.mapAttrs
    (_: tests: builtins.mapAttrs
      (_: result: (builtins.tryEval (builtins.deepSeq result true)).success)
      tests)
    suites
'
```

As with composition diagnostics, `false` is a failing test, not an expected-success
exception. Some evaluation errors are not caught by `tryEval`.

## Development VCS runtime test

`runtime/vcs.nix` registers `runtime-vcs` with flake checks. It activates the real
shared Home Manager Git and Jujutsu modules with test author data, generates an
ephemeral SSH key inside the VM, loads it into an agent, and removes the private-key
file. Both tools must then create commits whose SSH signatures verify through Git.
This exercises agent-backed signing without a real account, private key in the
Nix store, remote Git server, or 1Password vault. It does not prove account-backed
1Password authorization; that is a manual workstation acceptance check.

```sh
nix build --no-link -L .#checks.x86_64-linux.runtime-vcs
```

## Composition tests

Run all composition assertions or one suite from the repository root:

```sh
nix eval --json .#lib.compositionTests
nix eval --json .#lib.compositionTests.alloy
```

Every suite is also registered as `composition-<suite>` under
`checks.x86_64-linux`, including `composition-docker`, `composition-grafana`,
`composition-microvm-platform`, and `composition-home-git`:

```sh
nix flake check --no-build
nix flake check
nix build --no-link .#checks.x86_64-linux.composition-docker
```

`--no-build` evaluates flake outputs and the composition assertions. The full
check command also builds registered checks. A composition check's build only
creates a success marker; it does not build the fixture systems. The system builds
registered above also run with the full command, as will future registered VM tests.
The targeted `nix eval` commands evaluate only the requested test results.

Every named test should return `true`. A failed expectation stops evaluation with
its diagnostic. To inspect all cases despite an assertion failure:

```sh
nix eval --json .#lib.compositionTests --apply '
  suites: builtins.mapAttrs
    (_: tests: builtins.mapAttrs
      (_: value: (builtins.tryEval (builtins.deepSeq value true)).success)
      tests)
    suites
'
```

In that diagnostic output, `false` means the test failed; it is not a passing
negative test. `tryEval` catches assertion failures and thrown errors, but not
every evaluation error, so an unhandled error can still stop this command.

## Organization

The file layout mirrors the reusable source modules:

```text
composition/
  default.nix
  helpers.nix
  services/       # One suite per service; integrations follow their owner.
  containers/     # Traefik and Pocket ID, including network and tracing integration.
  platforms/      # MicroVM networking, store sharing, and persistent SSH identity.
  profiles/       # Base, server, and workstation policy composition.
  users/          # Matyas account and independence from Home Manager and server policy.
  home/           # CLI groups, home profiles, and vcs/{git,jujutsu}.nix.
```

`composition/default.nix` is a flake-parts module. It discovers suite modules recursively using
import-tree, excluding itself and `helpers.nix`. It declares the mergeable result
option, supplies shared helpers, and creates one flake check per suite. Assertions
are forced before constructing check derivations, so `--no-build` checks them too.
The current fixtures and check wrappers target `x86_64-linux`.

Each suite is an outer flake-parts module that contributes results under
`flake.lib.compositionTests.<suite>`. Inside it, fixtures import real NixOS feature
modules into small NixOS configurations. The outer `config` is the flake-parts
configuration; a fixture's `.config` is a separate NixOS configuration.

- `services/docker.nix` owns Docker defaults and overrides.
- `platforms/ephemeral-root.nix` owns root-reset activation, required device
  settings, mount ordering, and protection against conflicting root/baseline names.
- `services/home-manager.nix` owns shared package policy and delivery for multiple
  users, plus Hyprland package, session, and UWSM environment coordination;
  `profiles/server.nix` owns selection of the Matyas server home and tools.
- `profiles/workstation.nix` owns workstation Home Manager selection, NetworkManager
  ownership and user access, password-protected sudo, overridable network defaults,
  independence from server and deployment services, and NixOS/Home Manager
  Hyprland selection, session registration, package coherence, and startup ownership;
  desktop keyring login hooks, greetd inheritance, and explicit opt-out. The server
  profile suite also checks that desktop keyring support remains unselected.
- `services/noctalia.nix` owns system support, recommended-services opt-out, and
  disabled-feature cleanup. `home/noctalia.nix` owns per-user service selection,
  generated baseline, and conditional Hyprland integration. Shared Home Manager
  tests cover system package overrides, personal overrides, and multiple users.
- `home/profiles.nix` owns personal desktop selection and generated minimal
  Hyprland bindings while preserving the shared CLI environment.
- `services/alloy.nix` owns Alloy settings, Loki integration, the shared trace
  receiver, and automatic cAdvisor
  integration with Docker, including its opt-outs and supporting configuration.
- `services/cadvisor.nix` owns standalone cAdvisor behavior, prerequisites, deployment
  settings, and explicit service disabling.
- `helpers.nix` contains ordinary functions, not an automatically imported module.

To add a suite, create a `.nix` module in the matching `composition/` subdirectory that defines
`flake.lib.compositionTests.<name>` as an attribute set of boolean expectations.
Suite names are flat and unique even though files are grouped in directories.
Home Manager suites use `home-` prefixes; platform, user, and profile suites use
names such as `microvm-platform`, `matyas-user`, and `server-profile`.
Keep fixtures in that suite; neither a central import list nor separate flake-check
registration is needed. Put helper-only files outside the discovery directory or
add them to the exclusion filter.

The original tests use explicit `assert` expressions. Later cases use `check`,
which wraps the same assertion pattern. `mkSystem` creates a minimal fixture, and
`mkHome` creates a standalone Home Manager fixture. `extend` adds settings to an
existing NixOS fixture. List definitions normally concatenate;
fixtures replacing a deployment interface list use `lib.mkForce` deliberately.

## Validation boundaries

Nix is lazy. Tests force the values relevant to the behavior being checked.
`failsEvaluation` uses `deepSeq` and `tryEval` for missing-setting cases; inactive
cases force supporting configuration too. Generated Alloy text is inspected without
recursively forcing package attributes. NixOS prerequisite assertions are checked
explicitly in `config.assertions`; merely reading a service enable flag does not
enforce that list. Minimal fixtures intentionally omit boot and filesystem setup,
so this suite does not require every system-level assertion to pass.

Tracing cases cover receiver activation from native OCI container declarations,
shared receiver ownership, proxy-network prerequisites, runtime endpoint settings,
sender opt-outs, and removal of unused receiver configuration. They inspect the
generated configuration; they do not send actual traces.

All reusable NixOS and Home Manager modules are in scope. Machine-specific host
and guest deployment modules are outside this suite. Home Manager cases test
standalone tool selection, shared profile membership, shell integration, and the
unauthenticated VCS baseline and optional development identity/signing settings.
The VCS runtime test covers SSH-agent signing; real 1Password authorization remains
a manual acceptance check.

Failures remain ordinary failing expectations until fixed; they are not skipped
or treated as expected successes. Run one regression test directly, for example:

```sh
nix eval --json .#lib.compositionTests.alloy.active-alloy-requires-http-interfaces
```

These tests do not build systems, boot VMs, validate Alloy configuration syntax,
test network reachability, or contact Loki. Full deployment builds and runtime
tests are separate layers. No production credentials are used.
