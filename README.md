# pr-buddy

`pr-buddy` is a macOS terminal UI for finding and acting on GitHub pull requests. It uses the GitHub CLI to fetch PR data, then provides keyboard-driven filtering, sorting, viewing, checkout, and browser actions.

When run in a terminal, `pr-buddy` opens an interactive picker with two views:

- PRs matching the command-line filters
- Open PRs that involve the authenticated GitHub user (`involves:@me`)

When stdin is not a terminal, it prints the matching PRs as a table instead.

## Requirements

- macOS 26.1 or later
- Swift 6.0 or later
- [GitHub CLI](https://cli.github.com/) installed and authenticated

Authenticate GitHub CLI before running `pr-buddy`:

```sh
gh auth login
gh auth status
```

## Build and install

Build a release executable with Swift Package Manager:

```sh
swift build -c release
```

Run it directly:

```sh
.build/release/pr-buddy
```

Or install it somewhere on your `PATH`:

```sh
mkdir -p ~/.local/bin
cp .build/release/pr-buddy ~/.local/bin/pr-buddy
```

## Usage

Run inside a local GitHub repository to query that repository:

```sh
pr-buddy
```

Query a repository explicitly:

```sh
pr-buddy --repo owner/project
```

Combine GitHub search with local filters:

```sh
pr-buddy \
  --repo owner/project \
  --search 'review-requested:@me' \
  --label bug,urgent \
  --status open,approved \
  --changed-files 2..20 \
  --reviews 1..
```

Available options:

| Option | Description |
| --- | --- |
| `-R, --repo <owner/repo>` | Repository to query; defaults to the current repository. |
| `-s, --search <query>` | GitHub search query passed to `gh pr list --search`. |
| `-l, --label <label>` | Required label; repeat or use comma-separated values. All labels must match. |
| `--status <status>` | Match `open`, `closed`, `merged`, `draft`, `ready`, `approved`, `changes_requested`, or `review_required`. Repeat or use comma-separated values. |
| `--min-files <count>` | Minimum number of changed files. |
| `--max-files <count>` | Maximum number of changed files. |
| `--changed-files <range>` | Exact count or range: `3`, `2..8`, `..5`, or `10..`. |
| `--reviews <range>` | Exact review count or range: `3`, `2..8`, `..5`, or `10..`. |
| `--limit <count>` | Maximum PRs fetched before local filtering; defaults to `50`. |

Use `pr-buddy --help` for the generated command reference.

## Interactive controls

| Key | Action |
| --- | --- |
| `Up` / `Down`, `j` / `k` | Move through PRs. |
| `Left` / `Right`, `h` / `l` | Move between sortable headers. |
| `Enter` | View the selected PR, or change the selected column's sort order. |
| `v` | View the selected PR with `gh pr view`. |
| `c` | Check out the selected PR with `gh pr checkout`. |
| `o` | Open the selected PR in a browser. |
| `Tab` | Toggle between the main and `involves:@me` views. |
| `/` | Filter the displayed PR list by text. |
| `r` | Refresh both views. |
| `q` | Quit. |

The `Updated`, `Files`, and `Review` headers cycle through ascending, descending, and unsorted order when selected and activated with `Enter`.

### Interactive filtering

Press `/` to narrow the displayed PR list with a text query. Text matches PR numbers, titles, authors, branches, and labels. Multiple terms must all match.

```text
checkout alex
#142
needs-review cli
```

While editing a filter, press `Enter` to apply it, `Ctrl-U` to clear it, or `Esc` to cancel.

## Non-interactive output

Redirect stdin to print a table without opening the full-screen interface:

```sh
pr-buddy --repo owner/project </dev/null
```

## Development

Run the test suite:

```sh
swift test
```

Debug builds can use the included fixture instead of calling GitHub:

```sh
swift run pr-buddy --debug-json fixtures/all-options-prs.json
```

The repository also includes a Tuist project definition. If Tuist is installed, regenerate the Xcode workspace with:

```sh
tuist generate --no-open
```

The main modules are:

- `pr-buddyCLI`: executable entry point
- `pr-buddy`: option parsing, GitHub integration, filtering, terminal input, and rendering
- `pr-buddyTests`: unit and snapshot tests
