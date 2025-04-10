local util_status_icon = require 'util_status_icon'

---@class TestsDisplay
---@field display_win number
---@field display_buf number
---@field original_test_win number
---@field original_test_buf number
---@field ns number
---@field tests_info gotest.TestInfo[] | terminal.testInfo[]
---@field _priority table<string, integer>
---@field close_display fun(self: TestsDisplay)
local Test_Display = {}
Test_Display.__index = Test_Display

--- @param tests_info gotest.TestInfo[] | terminal.testInfo[]
function Test_Display.new(tests_info)
  local self = setmetatable({}, Test_Display)
  self.display_win = -1
  self.display_buf = -1
  self.original_test_win = -1
  self.original_test_buf = -1
  self.ns = vim.api.nvim_create_namespace 'go_test_display'
  self.tests_info = tests_info
  self._priority = {
    running = 1,
    paused = 2,
    cont = 3,
    start = 4,
    fail = 5,
    pass = 6,
  }
  return self
end

---@param tests_info? gotest.TestInfo[] | terminal.testInfo[]
function Test_Display:setup(tests_info)
  self.original_test_win = vim.api.nvim_get_current_win()
  self.original_test_buf = vim.api.nvim_get_current_buf()

  if not self.display_buf or not vim.api.nvim_buf_is_valid(self.display_buf) then
    self.display_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[self.display_buf].bufhidden = 'hide'
    vim.bo[self.display_buf].buftype = 'nofile'
    vim.bo[self.display_buf].swapfile = false
  end

  if not self.display_win or not vim.api.nvim_win_is_valid(self.display_win) then
    vim.cmd 'vsplit'
    self.display_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.display_win, self.display_buf)
    vim.api.nvim_win_set_width(self.display_win, math.floor(vim.o.columns / 3))
    vim.wo[self.display_win].number = false
    vim.wo[self.display_win].relativenumber = false
    vim.wo[self.display_win].wrap = false
    vim.wo[self.display_win].signcolumn = 'no'
    vim.wo[self.display_win].foldenable = false
  end

  if tests_info then
    self:update_tracker_buffer(tests_info)
  end
  vim.api.nvim_set_current_win(self.original_test_win)
  self:setup_keymaps()
end

---@param tests_info gotest.TestInfo[] | terminal.testInfo[]
function Test_Display:parse_test_state_to_lines(tests_info)
  local lines = {}
  local tests = {}
  for _, test in pairs(tests_info) do
    if test.name then
      table.insert(tests, test)
    end
  end

  table.sort(tests, function(a, b)
    if a.status == b.status then
      return a.name < b.name
    end
    if not self._priority[a.status] and self._priority[b.status] then
      return true
    end
    if self._priority[a.status] and not self._priority[b.status] then
      return false
    end
    if not self._priority[a.status] and not self._priority[b.status] then
      return a.name < b.name
    end
    return self._priority[a.status] < self._priority[b.status]
  end)

  for _, test in ipairs(tests) do
    local status_icon = util_status_icon.get_status_icon(test.status)
    if test.status == 'fail' and test.file ~= '' then
      local filename = vim.fn.fnamemodify(test.filepath, ':t')
      table.insert(lines, string.format('%s %s -> %s:%d', status_icon, test.name, filename, test.fail_at_line))
    else
      table.insert(lines, string.format('%s %s', status_icon, test.name))
    end
  end

  return lines
end

---@param tests_info gotest.TestInfo[] | terminal.testInfo[]
function Test_Display:update_tracker_buffer(tests_info)
  local lines = self:parse_test_state_to_lines(tests_info)

  if vim.api.nvim_buf_is_valid(self.display_buf) then
    vim.api.nvim_buf_set_lines(self.display_buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(self.display_buf, self.ns, 0, -1)

    for i, line in ipairs(lines) do
      if line:match '^  ✅' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'DiagnosticOk', i - 1, 0, -1)
      elseif line:match '^  ❌' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'DiagnosticError', i - 1, 0, -1)
      elseif line:match '^  ⏸️' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'DiagnosticWarn', i - 1, 0, -1)
      elseif line:match '^  ▶️' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'DiagnosticInfo', i - 1, 0, -1)
      elseif line:match '^    ↳' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'Comment', i - 1, 0, -1)
      end
    end
  end
end

function Test_Display:assert_display_buf_win()
  assert(self.display_buf, 'display_buf is nil')
  assert(self.display_win, 'display_win is nil')
end

function Test_Display:jump_to_test_location()
  self:assert_display_buf_win()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_nr = cursor[1]
  local line = vim.api.nvim_buf_get_lines(self.display_buf, line_nr - 1, line_nr, false)[1]
  assert(line, 'No line found in display buffer')

  local test_name = line:match '[❌✅]%s+([%w_%-]+)'
  assert(test_name, 'No test name found in line: ' .. line)

  local test_info = self.tests_info[test_name]
  assert(test_info, string.format('No test info found for test: %s, %s', test_name, vim.inspect(self.tests_info)))
  assert(test_info.test_line, 'No test line found for test: ' .. test_name)
  local filepath = test_info.filepath
  vim.api.nvim_set_current_win(self.original_test_win)
  vim.cmd('edit ' .. filepath)

  if test_info.fail_at_line and test_info.fail_at_line ~= 0 then
    vim.api.nvim_win_set_cursor(0, { tonumber(test_info.fail_at_line), 0 })
  elseif test_info.test_line then
    vim.api.nvim_win_set_cursor(0, { test_info.test_line, 0 })
  else
    vim.notify(string.format('No test line found for test: %s', test_name), vim.log.levels.ERROR)
    return
  end
  vim.cmd 'normal! zz'
end

function Test_Display:setup_keymaps()
  local this = self -- Capture the current 'self' reference
  vim.keymap.set('n', 'q', function()
    this:close_display() -- Use the captured reference
  end, { buffer = this.display_buf, noremap = true, silent = true })

  vim.keymap.set('n', '<CR>', function()
    this:jump_to_test_location() -- Use the captured reference
  end, { buffer = this.display_buf, noremap = true, silent = true })
end

function Test_Display:close_display()
  if vim.api.nvim_win_is_valid(self.display_win) then
    vim.api.nvim_win_close(self.display_win, true)
    self.display_win = -1
  end
end

function Test_Display:toggle_display()
  if vim.api.nvim_win_is_valid(self.display_win) then
    vim.api.nvim_win_close(self.display_win, true)
    self.display_win = -1
  else
    self:setup()
  end
end

function Test_Display:register_command(command_name)
  local tracker = self
  vim.api.nvim_create_user_command(command_name, function() tracker:toggle_display() end, {})
end

return Test_Display
