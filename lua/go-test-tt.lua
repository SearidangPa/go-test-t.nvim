local M = {}

M.test_track_list = function()
  local terminal_test = require 'terminals.terminal_test'
  local terminal_tracker = require 'terminals.terminal_tracker'

  local make_notify = require('mini.notify').make_notify {}
  for _, test_info in ipairs(terminal_tracker.track_test_list) do
    make_notify(string.format('Running test: %s', test_info.test_name)).go_test_command(test_info)
    terminal_test.test_in_terminal(test_info)
  end
end

M.setup = function()
  local terminal_test = require 'terminals.terminal_test'
  vim.api.nvim_create_user_command('TerminalTestSearch', function() terminal_test.terminals:search_terminal() end, {})
  vim.api.nvim_create_user_command('TerminalTestDelete', function() terminal_test.terminals:select_delete_terminal() end, {})
  vim.api.nvim_create_user_command('TerminalTestToggleView', terminal_test.toggle_view_enclosing_test, {})
  vim.api.nvim_create_user_command('TerminalTestToggleLast', terminal_test.toggle_last_test_teriminal, {})

  require 'test_all'
  require 'terminals.terminal_tracker'
end

return M
