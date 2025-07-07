# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **go-test-t.nvim**, a Neovim plugin for running and managing Go tests with terminal integration, pinning capabilities, and comprehensive test result display. It's a Lua-based plugin that provides sophisticated test management for Go development in Neovim.

## Development Environment

This is a Neovim plugin written entirely in Lua. There are no traditional build, test, or lint commands as this is a plugin that runs within Neovim's Lua runtime.

### Dependencies
- `terminal-multiplexer` (required dependency)
- `fidget.nvim` or `mini.notify` (for notifications)

## Architecture

The plugin follows a modular architecture with clear separation of concerns:

### Core Components

1. **go-test-t.lua** - Main plugin interface and orchestrator
   - Manages the overall plugin lifecycle and configuration
   - Coordinates between all other modules
   - Handles user commands and test execution orchestration
   - Processes Go test JSON output and manages test state

2. **terminal_test/** - Terminal integration subsystem
   - **terminal_test.lua** - Core terminal test execution logic
   - **pin_test.lua** - Test pinning functionality for failed/important tests
   - Manages dedicated terminals for each test execution
   - Handles terminal multiplexer integration

3. **Utility Modules** (util_*.lua)
   - **util_go_test_display.lua** - Test results display and UI management
   - **util_find_test_func.lua** - Test function discovery and parsing
   - **util_go_test_path.lua** - Go project path resolution
   - **util_go_test_quickfix.lua** - Quickfix list integration
   - **util_go_test_status_icon.lua** - Status icon management
   - **util_go_test_lsp.lua** - LSP integration utilities
   - **util_annotation.lua** - Test annotation utilities

### Key Design Patterns

- **Dependency Injection**: Core modules accept function callbacks to avoid tight coupling
- **Observer Pattern**: Display updates are triggered via callback functions
- **State Management**: Test state is centralized but accessed through well-defined interfaces
- **Modular Architecture**: Each concern is separated into its own module

### Test Execution Flow

1. User triggers test command (TestAll, TestTerm, etc.)
2. go-test-t.lua orchestrates the execution
3. Go tests run with JSON output (`go test -v --json`)
4. JSON output is parsed and test state is updated
5. Failed tests are automatically pinned via pin_test.lua
6. Results are displayed via util_go_test_display.lua
7. Terminal integration allows viewing individual test outputs

### Plugin Configuration

The plugin uses a class-based approach with configuration passed to the constructor:

```lua
local go_test = require('go-test-t').new({
  go_test_prefix = 'go test',        -- Customizable test command
  user_command_prefix = 'Go',        -- Prefix for user commands
})
```

### User Commands

All user commands are dynamically created with the configurable prefix:
- `TestAll` - Run all tests in project
- `TestPkg` - Run tests in current package
- `TestTerm` - Run nearest test in terminal
- `TestToggleDisplay` - Toggle test results display
- `TestPinned` - Run all pinned tests
- `PinTest` - Pin nearest test
- `TestReset` - Reset test results (keep pinned)
- `TestResetAll` - Reset everything including pinned tests

### Development Notes

- Core modules use dependency injection with function callbacks to avoid tight coupling - this pattern should be maintained when adding new features