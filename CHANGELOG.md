# Changelog

Notable changes to booker. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and booker aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases before 2.0.0 predate this file; their entries are reconstructed from
the commit history and are one-liners rather than full notes. The repository has
no git tags, so there are no compare links here.

## [Unreleased]

A modernization pass over library code that had gone largely untouched since
2015. No new features; the CLI takes the same arguments and prints the same
table.

### Fixed

- Searching for anything containing a regex metacharacter no longer crashes.
  The search term was interpolated straight into a `Regexp`, so `booker "c++"`
  raised `RegexpError` before it searched anything, and a term like `(a+)+$`
  could hang. Terms are now escaped and matched literally.
- A config file using YAML anchors no longer takes down the whole command.
  Psych 4 stopped permitting aliases by default, which raises
  `Psych::AliasesNotEnabled` rather than the `Psych::SyntaxError` that was being
  rescued, so booker exited with a backtrace instead of falling back to
  defaults as intended.

### Changed

These three are visible in day-to-day use; the rest of the pass is not.

- **Warnings and errors now go to stderr instead of stdout.** A parse failure
  used to print onto stdout, which is also where `--complete-raw` writes the
  feed the shell completion scripts read — so a broken bookmarks file could put
  `Warning: Bookmarks file not found or invalid.` into the completion list as
  though it were a bookmark. Anything scraping booker's stdout for diagnostics
  needs to read stderr now.
- **Color is suppressed when stdout is not a terminal, and when `NO_COLOR` is
  set.** `booker > out.txt` and `booker | less` no longer collect raw `\033[`
  escape sequences. Column widths are computed from uncolored text, so the
  table lines up either way.
- **`String#red`, `#grn`, `#window` and friends are no longer added to `String`
  globally.** They were defined on core `String` by requiring booker, which is a
  namespace a gem should not be taking; they are a refinement now, scoped to
  booker's own files. Only code that required booker as a library and relied on
  those methods is affected — the CLI is not.
- Terminal width is read through `io/console` rather than shelling out to
  `tput cols`, removing a subprocess from every run.

### Internal

- Minimum Ruby stays at 3.2; the code now actually uses the intervening decade:
  `Data.define` for the bookmark value object, endless methods, `match?`,
  `clamp` with beginless/endless ranges, block-level `rescue`, frozen constants,
  and `# frozen_string_literal: true` throughout.
- Shelling out goes through `Open3` instead of backticks plus the `$?` global.
  `Tempfile.create` and `SQLite3::Database`'s block form replace manual cleanup
  in an `ensure`. Chrome profile discovery globs with `base:`, so a profile
  directory whose name contains glob metacharacters is found correctly.
- Specs: `RSpec.describe` with `disable_monkey_patching!`, `expect` syntax
  throughout (the `should` syntax is gone), and per-example output capture so a
  failing example can show what it printed. Coverage floor raised to 95%.
- Gemspec gained a `metadata` block including `rubygems_mfa_required`;
  development dependencies moved to the `Gemfile`; `add_dependency` replaces the
  soft-deprecated `add_runtime_dependency`; the homepage is `https`. Added
  `.ruby-version`, `.standard.yml` pinned to the 3.2 floor, and a dependabot
  config.

## [2.0.0] - 2026-08-08

### Added

- Tab completion for bash and fish, alongside the existing zsh support, with
  `booker --install` detecting which shells are present.
- GitHub Actions CI across Ruby 3.2 through 4.0.

### Changed

- Library restructured from flat files under `lib/` into `lib/booker/`, with one
  parser class per browser.

## Earlier releases

Reconstructed from commit history; see the git log for detail.

- **1.3.0** — 2026-04-05 — Safari bookmark support
- **1.2.1** — 2026-02-09 — dependency updates
- **1.2.0** — 2026-02-09 — Firefox bookmark support
- **1.1.0** — 2022-10-19 — better handling of search arguments
- **1.0.0** — 2021-06-24 — trimmed dependencies
- **0.6.1**, **0.6.0** — 2018-11-08
- **0.5.1**, **0.5** — 2016-07-18
- **0.4.2** — 2016-07-17
- **0.4.1** — 2015-12-01
- **0.4** — 2015-11-20
- **0.3.2** — 2015-11-17
- **0.3** — 2015-10-20
- **0.2.2** — 2015-10-19
- **0.2.1**, **0.2** — 2015-10-17 — first published versions
