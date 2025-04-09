local M = {}

M.setup = function()
  local terminal_test = require 'terminals.terminal_test'
  vim.api.nvim_create_user_command('TerminalTestSearch', function() terminal_test.terminals:search_terminal() end, {})
  vim.api.nvim_create_user_command('TerminalTestDelete', function() terminal_test.terminals:select_delete_terminal() end, {})
  vim.api.nvim_create_user_command('TerminalTestToggleView', terminal_test.view_enclosing_test, {})
  vim.api.nvim_create_user_command('TerminalTestToggleLast', terminal_test.view_last_test_teriminal, {})

  require 'async_job.test_vim_fn'
  require 'terminals.track_test_terminal'
end

--- === Terminal Test ===
M.test_tracked_in_terminal = function()
  local terminal_test = require 'terminals.terminal_test'
  local terminal_tracker = require 'terminals.track_test_terminal'

  local make_notify = require('mini.notify').make_notify {}
  for _, test_info in ipairs(terminal_tracker.track_test_list) do
    make_notify(string.format('Running test: %s', test_info.test_name)).go_test_command(test_info)
    terminal_test.test_in_terminal(test_info)
  end
end

---@param test_command_format string
M.test_nearest_in_terminal = function(test_command_format)
  local terminal_test = require 'terminals.terminal_test'
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

M.test_buf_in_terminals = function(test_command_format)
  local make_notify = require('mini.notify').make_notify {}
  local terminal_test = require 'terminals.terminal_test'
  local source_bufnr = vim.api.nvim_get_current_buf()
  local util_find_test = require 'util_find_test'
  local all_tests_in_buf = util_find_test.find_all_tests_in_buf(source_bufnr)
  for test_name, test_line in pairs(all_tests_in_buf) do
    terminal_test.terminals:delete_terminal(test_name)
    local test_command = string.format(test_command_format, test_name)
    local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command }
    make_notify(string.format('Running test: %s', test_name))
    terminal_test.test_in_terminal(test_info)
  end
end

return M
