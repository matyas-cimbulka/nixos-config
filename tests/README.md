# Composition tests

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
creates a success marker; it does not build the fixture systems. Future system
builds and VM tests registered under `checks` will also run with the full command.
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

Failures are kept as ordinary failing expectations for a later bug-fix pass.
They are not skipped or treated as expected successes. See
[known-failures.md](known-failures.md) for the recorded findings. Inspect one
failing test directly for its error, for example:

```sh
nix eval --json .#lib.compositionTests.alloy.active-alloy-requires-http-interfaces
```

These tests do not build systems, boot VMs, validate Alloy configuration syntax,
test network reachability, or contact Loki. Full deployment builds and runtime
tests are separate layers. No production credentials are used.
