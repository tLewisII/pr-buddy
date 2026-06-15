# Slash Command Interface Plan

## Goal

Replace the current `/` text-filter shortcut with a Codex-style slash command
interface. Pressing `/` should open a searchable command popup. Users can type
to filter commands, select one with the keyboard, complete it, and execute it.

## Initial Commands

The first command registry should expose the existing interactive actions:

| Command | Description |
| --- | --- |
| `/filter` | Filter pull requests by text |
| `/checkout` | Check out the selected pull request |
| `/open` | Open the selected pull request in a browser |
| `/refresh` | Refresh pull requests |
| `/main` | Switch to the main pull request view |
| `/attention` | Switch to the `involves:@me` view |
| `/quit` | Exit pr-buddy |

Keep command order intentional rather than alphabetical, with common actions
near the top. Put command metadata in one centralized registry so filtering,
rendering, completion, help text, and dispatch use the same source of truth.

## Interaction Model

1. Pressing `/` from the pull request list enters command mode with an empty
   query and displays all available commands.
2. Typing updates the query and filters command names case-insensitively.
3. Up and down arrows move the selected command and wrap at the ends.
4. `Tab` completes the selected command in the input line without executing it.
5. `Enter` executes the selected or exactly typed command.
6. `Backspace` edits the query. Backspacing an empty query exits command mode.
7. `Ctrl-U` clears the query while keeping command mode open.
8. `Escape` cancels command mode without changing application state.
9. Terminal resize events redraw the popup and preserve a valid selection.
10. If there are no matches, show a clear `No matching commands` row and do
    not dispatch anything on `Enter`.

Use a bottom-anchored input line such as `/fi_` and render the popup immediately
above it. Each popup row should show `/command` and its description. Highlight
the selected row using the TUI's existing inverted-selection style.

## Implementation Steps

### 1. Add the command model and registry

- Add a focused type for command metadata and actions, for example
  `SlashCommand`, `SlashCommandAction`, and `SlashCommandRegistry`.
- Keep it in the narrowest suitable module; create `SlashCommand.swift` if the
  model does not fit an existing file cleanly.
- Include the command name, description, action, and aliases only if aliases are
  actually needed.
- Add pure functions for filtering and exact command lookup so they are easy to
  unit test.

### 2. Add command-mode state and input handling

- Replace the `/` branch in `InteractiveSession.handleCharacter` that currently
  opens `editTextFilter`.
- Add command-mode state containing the query, selected index, and popup scroll
  position if needed.
- Handle character input, arrows, `Tab`, `Enter`, `Backspace`, `Ctrl-U`,
  `Escape`, interrupts, end-of-input, and terminal resize events.
- Clamp or reset selection when filtering changes the visible command list.
- Keep the command loop small by moving pure state transitions into focused
  helpers where practical.

### 3. Centralize action dispatch

- Refactor existing view, checkout, open, refresh, view-switching, and quit
  behavior so slash commands and any retained direct shortcuts call the same
  dispatch path.
- Do not duplicate GitHub command execution or state mutations.
- Preserve existing error handling, messages, selection behavior, and terminal
  restoration.
- `/filter` should invoke the existing text-filter editor. It may start with the
  current filter value, matching current behavior.

### 4. Render the command popup

- Extend `TUIRenderer` with a command-popup representation rather than building
  formatted popup strings inside `InteractiveSession`.
- Render as many rows as fit while reserving space for the normal list and the
  bottom command input line.
- Support selection highlighting, popup scrolling, width clipping, descriptions,
  and the no-matches state.
- Reuse `bottomAnchored` and existing formatting helpers where appropriate.
- Ensure narrow and short terminals degrade cleanly without out-of-bounds ranges
  or negative height calculations.

### 5. Update user-facing help

- Change list header hints from `/ filter` to wording that communicates command
  discovery, such as `/ commands`.
- Update the fallback help message in `InteractiveSession`.
- Update the interactive-key documentation in `PRBuddy.swift`.
- Remove documentation implying that `/` directly edits the text filter.

### 6. Add tests

Add focused XCTest coverage for:

- Empty query returns all commands in presentation order.
- Matching is case-insensitive and uses command-name prefixes.
- Exact command lookup and unknown-command behavior.
- Selection movement, wrapping, clamping, and reset after query changes.
- `Tab` completion.
- `Enter` dispatch for every initial command.
- `Escape`, empty-query backspace, and `Ctrl-U` behavior.
- No-match behavior.
- Resize handling and narrow/short terminal rendering.
- `/filter` opening the existing filter flow without changing its semantics.
- Shared dispatch behavior between slash commands and retained shortcuts.

Prefer testing pure command state and rendering inputs directly instead of
requiring a live terminal event loop.

### 7. Update snapshots and verify

- Update snapshots only for intentional visible changes to header hints or popup
  rendering.
- Inspect every changed file in `pr-buddyTests/__Snapshots__/`.
- Run:

```sh
swift test
swift run pr-buddy --debug-json fixtures/all-options-prs.json
```

In the fixture smoke test, verify opening `/`, filtering, navigation, completion,
dispatch, cancellation, `/filter`, and terminal resizing.

## Migration Decision

Retain the existing single-key shortcuts during the first implementation. This
keeps current workflows working while slash commands become the discoverable
interface. Update the header to emphasize `/ commands`, but do not remove
`j`/`k`, arrow, `Enter`, `c`, `r`, `Tab`, or `q` handling in the same
change. Shortcut removal can be considered separately after the slash interface
has shipped and stabilized.

## Completion Criteria

- `/` opens a complete command list instead of immediately opening text filter.
- Typing filters the list and keyboard navigation behaves consistently.
- Commands execute through shared action code with existing shortcuts.
- `/filter` preserves current filtering behavior.
- Popup rendering works at normal and constrained terminal sizes.
- Help text and snapshots describe the new interface.
- `swift test` passes and fixture-mode smoke testing succeeds.
