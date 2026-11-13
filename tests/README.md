# Configuration tests

## Full builds

`builds/default.nix` registers actual output derivations under `checks`, discovered
from `nixosConfigurations`, their MicroVM definitions, and `homeConfigurations`.
Checks are registered on the derivation's build platform. Current targets are:

- `build-host-tycho`
- `build-guest-tycho-anderson`, `build-guest-tycho-behemoth`, `build-guest-tycho-thoth`
- `build-home-matyas-server`

Run all build targets independently of the evaluation suites:

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
  profiles/       # Base and server policy composition.
  users/          # Matyas account and embedded Home Manager.
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
unauthenticated VCS baseline; deferred development credential providers are not
implemented or tested.

Failures remain ordinary failing expectations until fixed; they are not skipped
or treated as expected successes. Run one regression test directly, for example:

```sh
nix eval --json .#lib.compositionTests.alloy.active-alloy-requires-http-interfaces
```

These tests do not build systems, boot VMs, validate Alloy configuration syntax,
test network reachability, or contact Loki. Full deployment builds and runtime
tests are separate layers. No production credentials are used.
