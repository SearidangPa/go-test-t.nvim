local M = {}

M.setup = function()
  local term_test = require 'terminal_test'
  vim.api.nvim_create_user_command('GoTestSearch', function() M.terminals_tests:search_terminal() end, {})
  vim.api.nvim_create_user_command('GoTestDelete', function() M.terminals_tests:select_delete_terminal() end, {})
  vim.api.nvim_create_user_command('GoTestNormalBuf', term_test.test_normal_buf, {})
  vim.api.nvim_create_user_command('GoTestNormal', term_test.go_normal_test, {})
  vim.api.nvim_create_user_command('GoTestDriveDev', term_test.drive_test_dev, {})
  vim.api.nvim_create_user_command('GoTestDriveStaging', term_test.drive_test_staging, {})
  vim.api.nvim_create_user_command('GoTestDriveStagingBuf', term_test.drive_test_staging_buf, {})
  vim.api.nvim_create_user_command('GoTestDriveDevBuf', term_test.drive_test_dev_buf, {})
  vim.api.nvim_create_user_command('GoTestWindowsBuf', term_test.windows_test_buf, {})
  vim.api.nvim_create_user_command('GoTestIntegration', term_test.go_integration_test, {})

  vim.keymap.set('n', '<leader>G', term_test.go_integration_test, { desc = 'Go integration test' })
  vim.keymap.set('n', '<leader>st', function() M.terminals_tests:search_terminal() end, { desc = 'Select test terminal' })
  vim.keymap.set('n', '<leader>tf', function() M.terminals_tests:search_terminal(true) end, { desc = 'Select test terminal with pass filter' })
  vim.keymap.set('n', '<leader>tg', term_test.toggle_view_enclosing_test, { desc = 'Toggle go test terminal' })
  vim.keymap.set('n', '<leader>tl', term_test.toggle_last_test, { desc = 'Toggle last go test terminal' })

  require 'test_all'

  require 'tracker'
end

return M
