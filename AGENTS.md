# Repository Guidelines

## Project Structure & Module Organization

- `pr-buddy/` contains the core Swift module: argument parsing, GitHub CLI integration, filtering, terminal input, and TUI rendering.
- `pr-buddyCLI/main.swift` is the executable entry point.
- `pr-buddyTests/PRBuddyTests.swift` contains XCTest coverage. Snapshot fixtures live in `pr-buddyTests/__Snapshots__/`.
- `fixtures/all-options-prs.json` supplies deterministic PR data for debug runs.
- `Package.swift` is the primary build definition. `Project.swift` provides an equivalent Tuist/Xcode setup.

Keep new behavior in the narrowest existing component. For example, add query behavior to `PullRequestFilter.swift`, GitHub command construction to `GitHubClient.swift`, and terminal presentation to the renderer files.

## Build, Test, and Development Commands

```sh
swift build                         # Build the debug executable
swift build -c release              # Build an optimized executable
swift run pr-buddy --help           # Run the CLI through SwiftPM
swift test                          # Run all unit and snapshot tests
swift run pr-buddy --debug-json fixtures/all-options-prs.json
tuist generate --no-open            # Regenerate the optional Xcode workspace
```

`pr-buddy` requires an installed, authenticated `gh` command for live GitHub data. Debug fixture mode avoids network and authentication dependencies.

## Coding Style & Naming Conventions

Use Swift 6 conventions and four-space indentation. Types and protocols use `UpperCamelCase`; methods, properties, and enum cases use `lowerCamelCase`. Prefer small, focused types and extensions that match the current file ownership. Use `let` by default, early `guard` exits, and Foundation APIs instead of ad hoc parsing.

No formatter or linter is configured. Match the surrounding code and run `swift test` before submitting changes. Avoid unrelated formatting churn.

## Testing Guidelines

Tests use XCTest. Name tests descriptively with the `testBehaviorUnderCondition` pattern, such as `testParseOptionsRejectsInvalidLimitAndEmptyRepo`. Add focused tests for parsing, filtering, sorting, and terminal formatting changes. Update snapshots only when an intentional visible TUI change occurs, and inspect the resulting text files before committing.

## Commit & Pull Request Guidelines

History generally uses short, imperative subjects such as `Add interactive PR filtering` and `Constrain TUI output to terminal width`. Keep commits focused and describe the user-visible result; conventional prefixes such as `feat:` are accepted but not required.

Pull requests should explain the behavior change, list verification commands, and call out TUI or snapshot changes. Link relevant issues. Include terminal output or screenshots when visual layout changes materially.

## Generated Files

Do not commit `.build/`, `Derived/`, `DerivedData/`, `.tuist-cache/`, generated `.xcodeproj`, or `.xcworkspace` directories. These are intentionally ignored.
