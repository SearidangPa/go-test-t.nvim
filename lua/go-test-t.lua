local M = {}

M.setup = function()
  local terminal_test = require 'terminal_test.terminal_test'
  vim.api.nvim_create_user_command('TerminalTestSearch', function() terminal_test.terminals:search_terminal() end, {})
  vim.api.nvim_create_user_command('TerminalTestDelete', function() terminal_test.terminals:select_delete_terminal() end, {})
  vim.api.nvim_create_user_command('TerminalTestToggleView', terminal_test.view_enclosing_test, {})
  vim.api.nvim_create_user_command('TerminalTestToggleLast', terminal_test.view_last_test_teriminal, {})

  require 'async_job.go_test'
  require 'terminal_test.tracker'
end

return M
