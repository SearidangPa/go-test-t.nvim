---@class PinTester
local pin_tester = {}
pin_tester.__index = pin_tester

---@param opts PinTesterOptions
function pin_tester.new(opts)
  opts = opts or {}
  assert(opts.go_test_prefix, 'go_test_prefix is required')
  local self = setmetatable({}, pin_tester)
  self.pinned_list = {}
  self.term_tester = require('terminal_test.terminal_test').new {
    go_test_prefix = opts.go_test_prefix,
    tests_info = self.pinned_list,
    pin_test_func = function(test_info) self:pin_test(test_info) end,
    display_title = 'Pinned Tests',
  }
  return self
end

---@param test_info terminal.testInfo
function pin_tester:pin_test(test_info)
  self.pinned_list[test_info.name] = test_info
  self.term_tester.displayer:update_buffer(self.pinned_list)
end

function pin_tester:pin_nearest_test()
  self.term_tester:test_nearest_in_terminal()
  if not vim.api.nvim_win_is_valid(self.term_tester.displayer.display_win_id) then
    self.term_tester.displayer:create_window_and_buf()
  end
  self.pinned_list = self.term_tester.tests_info
  self.term_tester.displayer:update_buffer(self.pinned_list)
end

function pin_tester:test_all_pinned()
  for _, test_info in pairs(self.pinned_list) do
    self.term_tester.terminals:delete_terminal(test_info.name)
    self.term_tester:test_in_terminal(test_info)
    self.pinned_list[test_info.name].status = 'fired'
    self.term_tester.displayer:update_buffer(self.pinned_list)
  end
  if not vim.api.nvim_win_is_valid(self.term_tester.displayer.display_win_id) then
    if #self.pinned_list > 0 then
      self.term_tester.displayer:create_window_and_buf()
    end
  end
end

return pin_tester
