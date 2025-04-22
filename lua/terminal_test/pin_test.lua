---@class PinTester
local pin_tester = {}
pin_tester.__index = pin_tester

---@param opts PinTesterOptions
function pin_tester.new(opts)
  opts = opts or {}
  assert(opts.go_test_prefix, 'go_test_prefix is required')
  local self = setmetatable({}, pin_tester)
  self.pinned_list = {}
  self.update_display_buffer_func = opts.update_buffer_func
  self.toggle_display_func = opts.toggle_display_func
  self.test_in_terminal_func = opts.test_in_terminal_func
  self.test_nearest_in_terminal_func = opts.test_nearest_in_terminal_func
  return self
end

function pin_tester:is_test_pinned(test_name) return self.pinned_list[test_name] ~= nil end

---@param test_info terminal.testInfo
function pin_tester:pin_test(test_info)
  self.pinned_list[test_info.name] = test_info
  self.update_display_buffer_func(self.pinned_list)
end

function pin_tester:pin_nearest_test()
  local test_info = self.test_nearest_in_terminal_func()
  self.pinned_list[test_info.name] = test_info
  self.toggle_display_func()
  self.update_display_buffer_func(self.pinned_list)
end

function pin_tester:test_all_pinned()
  for _, test_info in pairs(self.pinned_list) do
    self.pinned_list[test_info.name].status = 'fired'
    self.test_in_terminal_func(test_info)
  end
  self.toggle_display_func()
  self.update_display_buffer_func(self.pinned_list)
end

return pin_tester
