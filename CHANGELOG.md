# Changelog

## 1.1.3

`seen.json` is no longer read or written through `FileView`.

### Added

- Quit in the panel's bottom-right corner disables the widget, or exits
  the live-data harness.

### Fixed

- Persistence now goes through a pinned `0700` state directory with
  no-follow type/owner/mode checks, a bounded read, bounded IDs, and an
  exclusive `0600` temp file renamed into place.

## 1.1.2

Second pass over the untrusted-input paths, found by auditing every sink
rather than only the one review flagged.

### Fixed

- Game titles can no longer carry markup or control bytes. The notification
  server advertises `body-markup` and `body-hyperlinks`, and entity decoding
  turned an escaped tag back into a live one, so a title could render a link
  or an image inside a system notification.
- A title that is exactly a known `omarchy-notification-send` flag (`-u`,
  `--glyph=…`) no longer reaches its option position, where it either
  suppressed the notification or overrode its glyph.
- Dropped `--compressed`: the download cap counts bytes on the wire, so a
  compressed response could still expand past it in memory.
- Capped the text a single row's title regex scans, bounding its backtracking.

## 1.1.1

Hardens everything parsed out of Steam's response, from marketplace review
feedback.

### Fixed

- Store links are now allowlisted to canonical `https://store.steampowered.com`
  URLs before they reach the browser launcher or a notification's `--exec`.
  Anything else falls back to the Steam search page.
- Bounded the remote response and the data parsed from it: 4 MB download cap,
  200 rows, 120-character titles, 10-digit ids.

## 1.1.0

Internal simplification. No change to what the widget does.

### Changed

- Removed the `show`, `hide`, and `state` IPC calls. `open`, `close`,
  `toggle`, and `refresh` are unchanged.
- Cut roughly a third of the code: the status hero is inlined, the async
  bookkeeping flags are gone, and the parser only accepts Steam's JSON.

## 1.0.0

First stable release.

### Highlights

- Watch Steam's free-specials search for 100% off games
- Desktop notifications for newly free games
- Click a notification or row to open the store page
- Dimmed bar icon when nothing is free
- Pulse while a refresh is in flight
- First snapshot after install is silent
- Retry with backoff when Steam is unreachable
- Optional hide-when-empty, country code, and refresh interval
