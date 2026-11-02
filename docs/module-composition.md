# Conditional composition principles

These principles describe the agreed target architecture for this flake. Existing
modules may still need cleanup to follow them.

## Feature ownership and profile membership

- A feature module owns the configuration for that feature, its prerequisite
  checks, and its contributions to conditional integrations.
- Only profiles define their members. Feature modules must not add themselves to
  profiles. Reading a profile should reveal the features it selects.
- Keep features self-contained and reusable. Avoid creating a separate module for
  every pair of cooperating features.
- Physical file boundaries need not match feature boundaries: implementation can
  span files without introducing more independently selected features.

## Conditional activation and explicit opt-out

- Integrations inspect the final configuration of the current system, regardless
  of which module enabled a service. Import order must not determine behaviour.
- Applicable integrations are on by default and allow an explicit opt-out.
  Explicit choices take precedence over automatic defaults.
- Use `lib.mkIf` for conditional configuration. Imports must be resolved before the
  configuration they produce; do not make imports depend on that same system's
  service enable flags.
- The complete integration follows its activation condition, including application
  flags, generated configuration, listeners, firewall rules, and systemd changes.
- Supporting configuration follows the effective enable state of the service it
  supports. An opt-out must not leave integration-specific configuration behind.
- These conditions operate within one evaluated system. A host and each MicroVM
  guest have separate configurations; remote services require explicit wiring.

## Hard requirements

- Validate hard dependencies with NixOS assertions and clear, actionable messages.
  Do not silently disable a selected feature because its requirements are missing.
- Check the actual declared capability required, rather than the name of an
  imported feature. For example, Docker-specific containers require the appropriate
  OCI backend and any networks or credential references they consume.
- Modules declaring required third-party options must be available. Assertions
  cannot replace the option declarations supplied by SOPS or MicroVM modules.
- Assertions validate declared configuration. They do not establish runtime
  readiness, credential availability, DNS resolution, or remote service health.

## Deployment settings

- Profiles explicitly supply deployment-specific settings: remote endpoints,
  network interfaces, binding information, credential references, and storage
  assignments where required.
- Represent these settings through typed Nix options. Reuse existing NixOS options
  where they express the requirement; add feature-specific options where needed.
  Generate process environment variables only when the application consumes them.
- Deployment-specific values are mandatory, with no defaults tied to the current
  infrastructure, such as Thoth's hostname or `lan0`. Ordinary application defaults
  can remain in feature modules.
- Require a value only while its consuming feature or integration is active.
  Missing required values must fail evaluation clearly. An automatically enabled
  integration must not silently opt out because its settings are missing.
- Keep secret contents runtime-only. Configuration supplies references; SOPS or
  the deployment's credential mechanism supplies the contents.

## Explicit wiring across machines

- Keep cross-machine wiring explicit in profiles. Do not introduce a shared
  deployment inventory or automatic cross-machine discovery as part of this design.
- Give each connection an obvious owner. The monitoring profile supplies remote
  scrape targets; the ingress profile supplies remote proxy destinations; the
  relevant deployment profiles supply DNS, credentials, and storage wiring.
- Define repeated values once within a profile where practical, then reuse them.
  Features translate the supplied values into application configuration.
- Moving a workload can require updates to its source and destination composition,
  monitoring, proxy, and DNS wiring. Keep those locations few and predictable;
  local conditional composition does not update remote consumers automatically.

## Network exposure

- Features own their ports and firewall contributions. Profiles supply the
  permitted interfaces through deployment settings.
- Allow separate deployment interfaces for different endpoint purposes, such as
  application traffic, administration, and metrics. A profile may assign the same
  interface to several purposes.
- Firewall rules and listeners contributed for a feature or integration follow its
  effective enable state.
- Container publication must enforce the same exposure policy. Docker-published
  ports bypass ordinary NixOS firewall rules, so interface-specific host firewall
  openings alone are insufficient. Account for publication and forwarding when
  implementing container features; binding to an address is not automatically an
  incoming-interface restriction. See
  [Docker port publishing](https://docs.docker.com/engine/network/port-publishing/).

## Shared integration infrastructure

- Each shared integration resource has one owner, normally the receiving feature.
- Sending features own their sending configuration. Receiving features own shared
  receivers, listeners, processing pipelines, and forwarding infrastructure.
- For example, Traefik owns its tracing flags, while Alloy owns the shared trace
  receiver and pipeline forwarding to Tempo. Other senders reuse that
  infrastructure rather than redefine it.
- Rely on the application's normal handling of unavailable observability services.
  Replace unsuitable integrations instead of adding custom failover machinery to
  this flake. Avoid turning optional observability into hard application service
  dependencies.

## Common server policy and MicroVM mechanics

- Server role and MicroVM platform are independent concerns. Share common server
  policy and keep MicroVM-specific mechanics in a platform feature.
- Hosts and guests use the Matyas account and the same shared Home Manager
  configuration for identical tools and settings, replacing the guest test setup.
- Each system has independent home-directory state. Do not share the host's
  `/home/matyas` with guests.
- MicroVM platform configuration handles guest-specific networking, store sharing,
  and persistence. Deployment profiles supply instance-specific values and storage
  assignments. Secret delivery may differ between host and guest.

## cAdvisor example

| Concern | Owner |
| --- | --- |
| Exporter configuration, listening port, firewall contribution, Docker prerequisite assertion | cAdvisor feature |
| Automatic cAdvisor activation when Docker and Alloy are enabled, with explicit opt-out | Alloy feature |
| Permitted metrics interface and required binding information | Deployment profile |
| Prometheus's remote scrape target | Monitoring profile |

In particular, cAdvisor's firewall and systemd adjustments follow whether cAdvisor
is actually enabled. Enabling Docker and Alloy supplies an overridable default;
explicitly disabling cAdvisor removes those supporting contributions.

When reviewing the cleanup, consider each feature alone, applicable combinations,
explicit opt-outs, missing hard requirements, and missing active deployment
settings. Distinguish source review, evaluation, generated configuration checks,
and runtime validation when reporting results.
