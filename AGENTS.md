# Repository guidance

Read and follow the [conditional composition principles](docs/module-composition.md)
before reviewing or changing flake modules and profiles. They describe the agreed
target architecture; existing code may not yet follow it.

- For new and existing modules, prefer typed options and conditional composition
  within the owning module over adding separately named modules for configuration
  variants or integrations. Profiles explicitly select features and configure their
  options; applicable integrations remain on by default with explicit opt-out.
- Follow the [VCS configuration plan](docs/vcs-configuration.md) when extending
  Git, Jujutsu, or development credential delivery.
- Machine names—servers, VMs, and workstations—are inspired by *The Expanse*
  books and TV series. Follow this convention when proposing new names.
- The Matyas account on infrastructure MicroVMs is for debugging. Ephemeral homes
  are intentional; preserve tools and settings declaratively rather than adding
  home-directory persistence.

## Collaboration

- Default to teaching and review: explain focused steps and review the user's work.
- Work one focused step at a time. After an authorized change, explain the result
  and validation before proceeding to the next cleanup.
- Do not write or modify Nix configuration unless the user explicitly asks. A
  request to check configuration authorizes review, not edits.
- Ask one substantive question at a time when a decision is needed. Use decisions
  already established in the conversation and principles instead of asking again.
- Re-read current files when checking the user's edits.
- Report validation precisely. Source inspection and successful evaluation do not
  prove a build, deployment, or live service works.
- For changes intended only to reorganize configuration, compare evaluated
  outputs before and after where practical. Identify intentional behaviour
  changes separately.

## Nix style

- Group settings with a shared attribute prefix into one attribute set, such as
  `systemd.services = { ... };` or `sops = { secrets = { ... }; templates = { ... }; };`.
  Keep short lists on one line and avoid unnecessary wrapper blocks and blank
  lines. Prefer compact grouping without changing module or conditional boundaries.
- Avoid broad formatter changes during focused edits; preserve the repository's
  compact-list style.
