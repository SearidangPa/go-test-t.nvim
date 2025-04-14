---@class PinTester
local pin_tester = {}
pin_tester.__index = pin_tester

function pin_tester.new(opts)
  opts = opts or {}
  local self = setmetatable({}, pin_tester)
  self.pinned_list = {}
  local term_test_command_format = opts.term_test_command_format or 'go test ./... -v -run %s\r'
  self.term_tester = require('terminal_test.terminal_test').new {
    tests_info = self.pinned_list,
    term_test_command_format = term_test_command_format,
  }
  return self
end

function pin_tester:pin_test()
  local test_info = self.term_tester:test_nearest_in_terminal()
  table.insert(self.pinned_list, test_info)
  self.term_tester.displayer:update_buffer(self.pinned_list)
  self.term_tester.displayer:toggle_display()
end

return pin_tester
