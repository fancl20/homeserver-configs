## Coding

### Coding style

Coding style should follow the project documentation under `docs/`, as well
as any guidelines provided in this section. If not specified, maintain
consistent style across the codebase.

Prefer fail-fast over defensive programming: validate external input once,
where it enters, and let internal failures surface instead of masking them.

A comment states what the code does plus the facts a reader cannot derive
from it. Edit comments in place so they read as written fresh for the
current design, not as an accumulation of past edits.

## Commit change

### Before commit

Review changes to ensure they conform to all style requirements, and run
the project's checks (tests, linters, generators) where they exist.

Pause and wait for human review before committing changes to the codebase.
It's acceptable to amend a local commit if a later commit is a refinement
of the first.

### Commit message

As an agent bot, all commits should start with 🤖. Commit messages should
follow the repository's existing commit style and include only a one-line
summary.

## Documentation guidelines

- Base documentation on code found within the repository; do not invent
  facts, commands, code, API names, or output.
- Match the style of surrounding documentation and keep it concise and
  easy to understand.
- Proactively raise concerns and propose alternatives if changes might
  hinder understanding or accessibility.

## General requirements

- Use a neutral and calm tone for all messages and keep text concise.
- If something is unclear or ambiguous, seek confirmation or clarification
  from the user before making changes based on assumptions.
- Edit toward the intended end state instead of appending, and drop
  statements that exist only to negate what was there before.
