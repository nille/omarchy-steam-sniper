# Changelog

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
