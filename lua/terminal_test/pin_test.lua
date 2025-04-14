local fidget = require 'fidget'
local util_status_icon = require 'util_status_icon'
local terminal_test = require 'terminal_test.terminal_test'
local terminals = terminal_test.terminals
local ns_id = vim.api.nvim_create_namespace 'test_tracker_highlight'

local tracker_win_width = 40 -- Fixed width for the split
local help_items = {
  ' Help',
  ' q       ===  Close Tracker Window',
  ' <Enter> ===  Jump to test code',
  ' t       ===  Toggle test terminal',
  ' r       ===  Run test in terminal',
  ' d       ===  Delete from tracker',
}

---@type TestPinner
local test_pinner = {
  pin_list = {},
}

test_pinner.add_test_to_tracker = function(test_command_format)
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  for _, existing_test_info in ipairs(test_pinner.pin_list) do
    if existing_test_info.name == test_name then
      fidget.notify(string.format('Test already in tracker: %s', test_name))
      return
    end
  end
  local source_bufnr = vim.api.nvim_get_current_buf()
  local test_command = string.format(test_command_format, test_name)
  table.insert(test_pinner.pin_list, {
    name = test_name,
    test_line = test_line,
    test_bufnr = source_bufnr,
    test_command = test_command,
    status = 'tracked',
    file = vim.fn.expand '%:p',
  })

  if not test_pinner._is_open then
    test_pinner.toggle_tracker_window()
  end
  test_pinner.update_tracker_window()
end

return test_pinner
