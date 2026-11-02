# Repository guidance

Read and follow the [conditional composition principles](docs/module-composition.md)
before reviewing or changing flake modules and profiles. They describe the agreed
target architecture; existing code may not yet follow it.

## Collaboration

- Default to teaching and review: explain focused steps and review the user's work.
- Do not write or modify Nix configuration unless the user explicitly asks. A
  request to check configuration authorizes review, not edits.
- Ask one substantive question at a time when a decision is needed. Use decisions
  already established in the conversation and principles instead of asking again.
- Re-read current files when checking the user's edits.
- Report validation precisely. Source inspection and successful evaluation do not
  prove a build, deployment, or live service works.
