vim.api.nvim_create_user_command('ReloadTesTT', function()
  -- Easy Reloading
  package.loaded['go-test-tt'] = nil
  require('go-test-tt').setup()
end, {})
