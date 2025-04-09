local make_notify = require('mini.notify').make_notify {}
local terminal_test_ns = vim.api.nvim_create_namespace 'GoTestError'
local terminal_multiplexer = require 'terminal_test.terminal_multiplexer'

---@class terminalTest
---@field terminalTest.terminals TerminalMultiplexer
---@field terminalTest.test_in_terminal fun(test_info: terminal.testInfo)
---@field terminalTest.test_buf_in_terminals fun(test_command_format: string)
---@field terminalTest.test_nearest_in_terminal fun(test_command_format: string)
---@field terminalTest.test_tracked_in_terminal fun()
---@field terminalTest.view_enclosing_test fun()
---@field terminalTest.view_last_test_teriminal fun()
local terminal_test = {}
terminal_test.terminals = terminal_multiplexer.new()

---@class terminal.testInfo
---@field test_name string
---@field test_line number
---@field test_bufnr number
---@field test_command string
---@field status string

local function validate_test_info(info)
  assert(info.test_name, 'No test found')
  assert(info.test_bufnr, 'No test buffer found')
  assert(info.test_line, 'No test line found')
  assert(info.test_command, 'No test command found')
  assert(vim.api.nvim_buf_is_valid(info.test_bufnr), 'Invalid buffer')
end

---@param opts terminal.testInfo
terminal_test.test_in_terminal = function(opts)
  validate_test_info(opts)
  terminal_test.terminals:toggle_float_terminal(opts.test_name)
  local float_term_state = terminal_test.terminals:toggle_float_terminal(opts.test_name)
  assert(float_term_state, 'Failed to create floating terminal')
  vim.api.nvim_chan_send(float_term_state.chan, opts.test_command .. '\n')

  vim.api.nvim_buf_attach(float_term_state.buf, false, {
    on_lines = function(_, buf, _, first_line, last_line)
      local lines = vim.api.nvim_buf_get_lines(buf, first_line, last_line, false)
      local current_time = os.date '%H:%M:%S'
      local error_line

      for _, line in ipairs(lines) do
        if string.match(line, '--- FAIL') then
          vim.api.nvim_buf_set_extmark(opts.test_bufnr, terminal_test_ns, opts.test_line - 1, 0, {
            virt_text = { { string.format('❌ %s', current_time) } },
            virt_text_pos = 'eol',
          })
          opts.status = 'failed'
          float_term_state.status = 'failed'

          make_notify(string.format('Test failed: %s', opts.test_name))
          vim.notify(string.format('Test failed: %s', opts.test_name), vim.log.levels.WARN, { title = 'Test Failure' })
          return true
        elseif string.match(line, '--- PASS') then
          vim.api.nvim_buf_set_extmark(opts.test_bufnr, terminal_test_ns, opts.test_line - 1, 0, {
            virt_text = { { string.format('✅ %s', current_time) } },
            virt_text_pos = 'eol',
          })
          opts.status = 'passed'
          float_term_state.status = 'passed'

          make_notify(string.format('Test passed: %s', opts.test_name))
          return true -- detach from the buffer
        end

        -- Pattern matches strings like "Error Trace:    /Users/path/file.go:21"
        local file, line_num = string.match(line, 'Error Trace:%s+([^:]+):(%d+)')

        if file and line_num then
          error_line = tonumber(line_num)

          -- Try to find the buffer for this file
          local error_bufnr
          for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
            local buf_name = vim.api.nvim_buf_get_name(buf_id)
            if buf_name:match(file .. '$') then
              error_bufnr = buf_id
              break
            end
          end

          if error_bufnr then
            vim.fn.sign_define('GoTestError', { text = '✗', texthl = 'DiagnosticError' })
            vim.fn.sign_place(0, 'GoTestErrorGroup', 'GoTestError', error_bufnr, { lnum = error_line })
          end
        end
      end

      if error_line then
        return true
      end
      return false
    end,
  })
end

terminal_test.test_buf_in_terminals = function(test_command_format)
  local source_bufnr = vim.api.nvim_get_current_buf()
  local util_find_test = require 'util_find_test'
  local all_tests_in_buf = util_find_test.find_all_tests_in_buf(source_bufnr)
  for test_name, test_line in pairs(all_tests_in_buf) do
    terminal_test.terminals:delete_terminal(test_name)
    local test_command = string.format(test_command_format, test_name)
    local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command }
    terminal_test.test_in_terminal(test_info)
  end
end

---@param test_command_format string
terminal_test.test_nearest_in_terminal = function(test_command_format)
  assert(test_command_format, 'No test command format found')
  local source_bufnr = vim.api.nvim_get_current_buf()
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_name, 'Not inside a test function')
  assert(test_line, 'No test line found')
  terminal_test.terminals:delete_terminal(test_name)
  assert(test_name, 'No test found')
  local test_command = string.format(test_command_format, test_name)
  local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command }
  terminal_test.test_in_terminal(test_info)
end

terminal_test.test_tracked_in_terminal = function()
  local terminal_tracker = require 'terminals.track_test_terminal'
  for _, test_info in ipairs(terminal_tracker.track_test_list) do
    make_notify(string.format('Running test: %s', test_info.test_name)).go_test_command(test_info)
    terminal_test.test_in_terminal(test_info)
  end
end

--- === View Teriminal ===

terminal_test.view_enclosing_test = function()
  local util_find_test = require 'util_find_test'
  local test_name, _ = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  local float_terminal_state = terminal_test.terminals:toggle_float_terminal(test_name)
  assert(float_terminal_state, 'Failed to create floating terminal')

  -- Need this duplication. Otherwise, the keymap is bind to the buffer for for some reason
  local close_term = function()
    if vim.api.nvim_win_is_valid(float_terminal_state.footer_win) then
      vim.api.nvim_win_hide(float_terminal_state.footer_win)
    end
    if vim.api.nvim_win_is_valid(float_terminal_state.win) then
      vim.api.nvim_win_hide(float_terminal_state.win)
    end
  end
  vim.keymap.set('n', 'q', close_term, { buffer = float_terminal_state.buf })
end

terminal_test.view_last_test_teriminal = function()
  local test_name = terminal_test.terminals.last_terminal_name
  if not test_name then
    make_notify 'No last test found'
    return
  end
  terminal_test.terminals:toggle_float_terminal(test_name)
end

return terminal_test
