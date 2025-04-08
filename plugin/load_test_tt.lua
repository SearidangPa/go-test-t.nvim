vim.api.nvim_create_user_command('ReloadTestT', function()
  -- Easy Reloading
  package.loaded['test-tt'] = nil
  require('test-tt').setup()
end, {})
