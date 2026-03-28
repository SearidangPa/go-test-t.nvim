# go-test-t.nvim

Minimal Go test runner for Neovim with a side test board, terminal reruns, and failure-first feedback.

## Setup

```lua
require("go-test-t").setup({
    go_test_prefix = "go test",
    integration_test_pkg = "./integration_tests/...",
})
```

- `go_test_prefix` defaults to `"go test"`.
- `integration_test_pkg` is optional; when set, `:TestIntegration` is available.

## Recommended keymaps

```lua
local gt = require("go-test-t")

vim.keymap.set("n", "<leader>tn", gt.test_this)
vim.keymap.set("n", "<leader>tf", gt.test_file)
vim.keymap.set("n", "<leader>tt", gt.view_last_test_terminal)
vim.keymap.set("n", "<leader>tj", gt.go_to_test_location)
```

## Core features

### 1) Fast test execution loops

- `gt.test_this()`
  - Runs the nearest test under cursor.
  - If cursor is not inside a test, reruns the last test terminal session.
- `gt.test_file()`
  - Finds all `Test*` functions in current buffer and runs each test in terminals.
- `gt.view_last_test_terminal()`
  - Reopens/toggles the most recently used test terminal.
- `gt.go_to_test_location()`
  - Jumps to the source location of the last test via `gopls` symbol lookup.

### 2) Test board (`:TestBoard`)

- Opens a side board that tracks all discovered/ran tests.
- Shows status icons (`🔥` fired, `🔄` running, `✅` pass, `❌` fail, etc.).
- Failing tests can include `filename:line` when trace data is detected.
- Failed/pinned tests are surfaced first so broken tests stay visible.

Board keys:

- `r` rerun selected test in terminal
- `o` open floating terminal preview; fallback to stored output
- `<CR>` jump to test location
- `q` close board/preview

### 3) Integration workflows

- `:TestIntegration`
  - Runs the configured package using `go test ... -v --json`.
  - Streams JSON actions and updates the board live (`run`, `output`, `pass`, `fail`).
- `:TestDrive [dev|staging]` (default: `dev`)
  - Discovers integration tests (`Test_` prefix) in `./integration_tests/`.
  - Runs tests concurrently and writes a markdown report to:
    - `~/Downloads/tests_report.md`

### 4) Failure handling and visibility

- Parses terminal output for `--- PASS`, `--- FAIL`, `FATAL`, and `Error Trace:` lines.
- Adds pass/fail timestamp marks at end-of-line in the source buffer.
- Auto-pins failing tests so they are easy to rerun.
- Adds failing tests to quickfix for quick triage (`:copen`).

## Commands

- `:TestBoard` open/close the test board
- `:TestReset` clear tracked tests (and pins)
- `:TestIntegration` run configured integration package (only if configured)
- `:TestDrive [dev|staging]` run concurrent integration report (non-Windows)

## Requirements

- `gopls` for symbol-based test navigation and test-name-to-location lookups.
- `beaver` for test/function detection in current buffer.
- `terminal-multiplexer` for managing floating test terminals.

## Notes

- Uses terminal output parsing for status updates during local reruns.
- Uses Go JSON event parsing for `:TestIntegration`.
- Keep the trailing `\r\n` in generated Go test commands.
