local M = {}

M.setup = function()
  vim.api.nvim_create_user_command('GoTestSearch', function() M.terminals_tests:search_terminal() end, {})
  vim.api.nvim_create_user_command('GoTestDelete', function() M.terminals_tests:select_delete_terminal() end, {})
  vim.api.nvim_create_user_command('GoTestNormalBuf', test_normal_buf, {})
  vim.api.nvim_create_user_command('GoTestNormal', go_normal_test, {})
  vim.api.nvim_create_user_command('GoTestDriveDev', drive_test_dev, {})
  vim.api.nvim_create_user_command('GoTestDriveStaging', drive_test_staging, {})
  vim.api.nvim_create_user_command('GoTestDriveStagingBuf', drive_test_staging_buf, {})
  vim.api.nvim_create_user_command('GoTestDriveDevBuf', drive_test_dev_buf, {})
  vim.api.nvim_create_user_command('GoTestWindowsBuf', windows_test_buf, {})
  vim.api.nvim_create_user_command('GoTestIntegration', go_integration_test, {})

  vim.keymap.set('n', '<leader>G', go_integration_test, { desc = 'Go integration test' })
  vim.keymap.set('n', '<leader>st', function() M.terminals_tests:search_terminal() end, { desc = 'Select test terminal' })
  vim.keymap.set('n', '<leader>tf', function() M.terminals_tests:search_terminal(true) end, { desc = 'Select test terminal with pass filter' })
  vim.keymap.set('n', '<leader>tg', toggle_view_enclosing_test, { desc = 'Toggle go test terminal' })
  vim.keymap.set('n', '<leader>tl', toggle_last_test, { desc = 'Toggle last go test terminal' })
end

return M
