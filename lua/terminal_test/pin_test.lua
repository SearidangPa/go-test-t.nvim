---@class PinTester
local pin_tester = {}
pin_tester.__index = pin_tester

---@param opts PinTesterOptions
function pin_tester.new(opts)
  opts = opts or {}
  local self = setmetatable({}, pin_tester)
  self.pinned_list = {}
  self.update_display_buffer_func = opts.update_display_buffer_func
  self.toggle_display_func = opts.toggle_display_func
  self.retest_in_terminal_by_name = opts.retest_in_terminal_by_name
  self.test_nearest_in_terminal_func = opts.test_nearest_in_terminal_func
  self.add_test_info_func = opts.add_test_info_func
  return self
end

function pin_tester:is_test_pinned(test_name) return self.pinned_list[test_name] ~= nil end

---@param test_info terminal.testInfo
function pin_tester:pin_test(test_info)
  vim.notify(string.format('Pinning %s', test_info.name), vim.log.levels.INFO)
  self.pinned_list[test_info.name] = test_info
end

function pin_tester:unpin_test(test_name)
  vim.notify(string.format('Unpinning %s', test_name), vim.log.levels.INFO)
  self.pinned_list[test_name] = nil
end

function pin_tester:pin_nearest_test()
  local test_info = self.test_nearest_in_terminal_func()
  self.pinned_list[test_info.name] = test_info
  self.add_test_info_func(test_info)
  self.toggle_display_func(true)
  self.update_display_buffer_func(self.pinned_list)
end

function pin_tester:test_all_pinned()
  for _, test_info in pairs(self.pinned_list) do
    self.pinned_list[test_info.name].status = 'fired'
    test_info.status = 'fired'
    self.add_test_info_func(test_info)
    vim.notify(string.format('Retesting pinned %s', test_info.name), vim.log.levels.INFO)
    self.retest_in_terminal_by_name(test_info.name)
  end
  self.toggle_display_func(true)
  self.update_display_buffer_func(self.pinned_list)
end

return pin_tester
