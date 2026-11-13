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

## Testing workflow

- Use test-driven development by default for configuration behavior changes and
  bug fixes. Add or update a focused test first, then run it and confirm that it
  fails for the intended reason before changing the implementation. An existing
  failing test that reproduces the issue satisfies this first step.
- Make the smallest configuration change that turns the focused test green.
  Re-run the affected suite and the composition suite, checking for regressions
  against the recorded baseline. Refactor only while preserving those results.
- Test the intended behavior through the real modules and merged configuration.
  Do not weaken or skip expectations merely to make the suite pass. Separate
  mistakes in test fixtures from actual configuration failures.
- Keep unrelated known failures visible and report them separately from new
  failures. Update [the findings inventory](tests/known-failures.md) when fixes
  change the baseline; do not expand a focused change to fix unrelated findings.
- For documentation, formatting, and behavior-preserving reorganizations, use
  appropriate existing checks and output comparisons rather than inventing a
  failing test. Choose build or runtime tests when evaluation cannot establish
  the behavior being changed.
- Follow [the testing guide](tests/README.md) for suite organization and commands.
  This workflow does not change the teaching mode or edit authorization rules.

## Nix style

- Group settings with a shared attribute prefix into one attribute set, such as
  `systemd.services = { ... };` or `sops = { secrets = { ... }; templates = { ... }; };`.
  Keep short lists on one line and avoid unnecessary wrapper blocks and blank
  lines. Prefer compact grouping without changing module or conditional boundaries.
- Avoid broad formatter changes during focused edits; preserve the repository's
  compact-list style.
