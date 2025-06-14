# go-test-t.nvim

A powerful Neovim plugin for running and managing Go tests with terminal integration, pinning capabilities, and comprehensive test result display.

<p align="center">
  <img src="https://github.com/user-attachments/assets/819eb2ae-7ccd-4d64-a74c-0b6a84cdcbcb" width="300" alt="go-test-t.nvim Screenshot">
</p>

## Features

- **Terminal Integration**: Run tests in dedicated terminals with multiplexer support
- **Test Pinning**: Pin failing tests for quick re-execution
- **Real-time Results**: Live test output with JSON parsing
- **Test Discovery**: Automatically find and run enclosing tests
- **Quickfix Integration**: Failed tests appear in quickfix list
- **Visual Feedback**: Status icons and namespace highlighting
- **Multiple Test Scopes**: Run all tests, package tests, or individual tests

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
   'SearidangPa/terminal-multiplexer', -- Required dependency
    event = 'VeryLazy', -- Load when Neovim is ready
    lazy = true, -- Load on demand
},
{
  'SearidangPa/go-test-t.nvim',
  ft = 'go',
  lazy = true,             -- Load on Go filetype
  events = 'VeryLazy',     -- Load after Neovim is ready
  config = function()
    local go_test = require('go-test-t').new({
      go_test_prefix = 'go test',        -- Custom test command prefix
      user_command_prefix = '',          -- Prefix for user commands
    })
  end,
}
```


## Configuration

```lua
local go_test = require('go-test-t').new({
  go_test_prefix = 'go test',        -- Command prefix for running tests
  user_command_prefix = 'Go',        -- Prefix for user commands (e.g., 'GoTestAll')
})

-- Optionally change test prefix later
go_test:set_go_test_prefix({ go_test_prefix = 'go test --race' })
```

## Commands

The plugin provides several user commands (prefixed with your `user_command_prefix`):

| Command | Description |
|---------|-------------|
| `TestAll` | Run all tests in the project |
| `TestPkg` | Run tests in current package only |
| `TestTerm` | Run nearest test in terminal (or last test if none found) |
| `TestTermBuf` | Run all tests in current buffer in terminals |
| `TestTermView` | Run nearest test with terminal view |
| `TestTermViewLast` | Toggle last test terminal |
| `TestTermSearch` | Search and select terminal |
| `TestToggleDisplay` | Toggle test results display window |
| `TestPinned` | Run all pinned tests |
| `PinTest` | Pin nearest test for quick re-execution |
| `TestReset` | Reset test results (keep pinned tests) |
| `TestResetAll` | Reset everything including pinned tests |

## Usage Examples

### Basic Usage

```lua
-- Run all tests
:TestAll

-- Run tests in current package
:TestPkg

-- Run test under cursor in terminal
:TestTerm

-- Toggle results display
:TestToggleDisplay
```

### Test Pinning Workflow

1. Run tests with `:TestAll`
2. Failed tests are automatically pinned
3. Use `:TestPinned` to re-run only failed tests
4. Manually pin specific tests with `:PinTest`

### Key Mappings Example

```lua
vim.keymap.set('n', '<leader>ta', '<cmd>TestAll<cr>', { desc = 'Run all tests' })
vim.keymap.set('n', '<leader>tp', '<cmd>TestPkg<cr>', { desc = 'Run package tests' })
vim.keymap.set('n', '<leader>tt', '<cmd>TestTerm<cr>', { desc = 'Run nearest test' })
vim.keymap.set('n', '<leader>td', '<cmd>TestToggleDisplay<cr>', { desc = 'Toggle test display' })
vim.keymap.set('n', '<leader>tr', '<cmd>TestPinned<cr>', { desc = 'Run pinned tests' })
```

## Features in Detail

### Terminal Integration
- Each test runs in its own dedicated terminal
- Terminal multiplexer manages multiple test terminals
- View test output in real-time
- Navigate between test terminals easily

### Test Pinning
- Failed tests are automatically pinned for quick access
- Manually pin tests you want to run repeatedly
- Run all pinned tests with a single command
- Persistent across test sessions

### Smart Test Discovery
- Automatically finds the enclosing test function
- Falls back to last run test if no enclosing test found
- Supports Go test naming conventions

### Visual Feedback
- Status icons show test states (running, passed, failed)
- Namespace highlighting for test results
- Integration with quickfix list for failed tests
- Real-time display updates

## Requirements

- Neovim >= 0.8.0
- Go toolchain
- Required Lua dependencies:
  - `terminal-multiplexer`
  - `fidget.nvim` (for notifications)
  - `mini.notify` (for notifications)

## Architecture

The plugin consists of several modules:

- **go-test-t.lua**: Main plugin interface and test orchestration
- **terminal_test/**: Terminal integration and multiplexer management  
- **util_*.lua**: Utility modules for test discovery, display, paths, etc.
- **go-test-quickfix.lua**: Quickfix list integration

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Credit

* Many thanks to [Teej](https://www.youtube.com/@teej_dv) for many great Neovim tutorials that inspired this plugin.

## License

MIT License - see LICENSE file for details.
