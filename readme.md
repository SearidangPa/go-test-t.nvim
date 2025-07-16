<p align="center">
<img src="https://github.com/user-attachments/assets/819eb2ae-7ccd-4d64-a74c-0b6a84cdcbcb" width="200" alt="">
</p>

## What is go-test-t?

Running, viewing, and navigating between code and terminal for Go tests 

## Features

- **Real-time Results**: Live test output with JSON parsing
- **Quickfix Integration**: Failed tests appear in quickfix list
- **Multiple Test Scopes**: Run all tests, package tests, or individual tests
- **Test Pinning**: Pin failing tests for visual tracking when rerunning
- **Terminal Integration**: Run tests in dedicated terminals with multiplexer support. 


## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'SearidangPa/terminal-multiplexer', -- Required dependency
  event = 'VeryLazy',
  lazy = true,
},
{
  'SearidangPa/go-test-t.nvim',
  ft = 'go',
  lazy = true,
  opts = {
    go_test_prefix = 'go test -race -count=1',   -- Command prefix for running tests
  },
}
```


## Commands

The plugin provides several user commands:

| Command | Description |
|---------|-------------|
| `TestAll` | Run all tests in the project |
| `TestPkg` | Run tests in current package only |
| `Test` | Run nearest test in terminal (or last test if none found) |
| `TestFile` | Run all tests in current buffer in terminals |
| `TestBoard` | Toggle test results display window |
| `TestLocation` | Go to the location of the last test |
| `TestViewLast` | Toggle last test terminal |

## Usage Examples

### Basic Usage

```lua
-- Run all tests
:TestAll

-- Run tests in current package
:TestPkg

-- Run test under cursor in terminal
:Test

-- Toggle results display
:TestBoard
```




### Display Buffer Keybinds
The test display buffer provides local keybinds for efficient test management:

| Key | Action | Description |
|-----|--------|-------------|
| `q` | Close | Close the test display window |
| `<CR>` | Jump | Navigate to test function in source code |
| `r` | Rerun | Rerun test in terminal |
| `o` | Output | Show full test output in floating window |



## Credit

* Many thanks to [Teej](https://www.youtube.com/@teej_dv) for many great Neovim tutorials that inspired this plugin.

