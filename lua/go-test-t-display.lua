local util_status_icon = require 'util_status_icon'

---@class TestsDisplay
---@field display_win number
---@field display_buf number
---@field original_test_win number
---@field original_test_buf number
---@field ns_id number
---@field tests_info gotest.TestInfo[] | terminal.testInfo[]
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
  self.ns_id = vim.api.nvim_create_namespace 'go_test_display'
  self.tests_info = tests_info
  return self
end

function Test_Display:create_window_and_buf()
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

  vim.api.nvim_set_current_win(self.original_test_win)
  self:setup_keymaps()
end

local function sort_tests_by_status(tests)
  table.sort(tests, function(a, b)
    if a.status == b.status then
      return a.name < b.name
    end
    local priority = {
      running = 1,
      paused = 2,
      cont = 3,
      start = 4,
      fail = 5,
      pass = 6,
    }
    if not priority[a.status] and priority[b.status] then
      return true
    end
    if priority[a.status] and not priority[b.status] then
      return false
    end
    if not priority[a.status] and not priority[b.status] then
      return a.name < b.name
    end
    return priority[a.status] < priority[b.status]
  end)
end

---@param tests_info table<string, gotest.TestInfo> | table<string, terminal.testInfo>
---@param buf_title string
function Test_Display:parse_test_state_to_lines(tests_info, buf_title)
  assert(tests_info, 'No test info found')
  assert(buf_title, 'No buffer title found')
  local tests_table = {}
  local buf_lines = { buf_title }

  for _, test in pairs(tests_info) do
    if test.name then
      table.insert(tests_table, test)
    end
  end
  sort_tests_by_status(tests_table)

  for _, test in ipairs(tests_table) do
    local status_icon = util_status_icon.get_status_icon(test.status)
    if test.status == 'fail' and test.filepath ~= '' and test.fail_at_line then
      local filename = vim.fn.fnamemodify(test.filepath, ':t')
      table.insert(buf_lines, string.format('%s %s -> %s:%d', status_icon, test.name, filename, test.fail_at_line))
    else
      table.insert(buf_lines, string.format('%s %s', status_icon, test.name))
    end
  end

  return buf_lines
end

---@param tests_info gotest.TestInfo[] | terminal.testInfo[]
---@param buf_title string
function Test_Display:update_tracker_buffer(tests_info, buf_title)
  if not self.display_buf or not vim.api.nvim_buf_is_valid(self.display_buf) then
    return
  end
  assert(tests_info, 'No test info found')
  assert(buf_title, 'No buffer title found')
  local lines = self:parse_test_state_to_lines(tests_info, buf_title)
  if vim.api.nvim_buf_is_valid(self.display_buf) then
    vim.api.nvim_buf_set_lines(self.display_buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_extmark(self.display_buf, self.ns_id, 0, 0, {
      end_col = #lines[1],
      hl_group = 'Title',
    })
  end
end

function Test_Display:assert_display_buf_win()
  assert(self.display_buf, 'display_buf is nil in jump_to_test_location')
  assert(self.display_win, 'display_win is nil in jump_to_test_location')
end

local icons = '🔥❌✅🔄⏸️🪵⏺️🏁'

function Test_Display:get_test_name_from_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_nr = cursor[1]
  local line = vim.api.nvim_buf_get_lines(self.display_buf, line_nr - 1, line_nr, false)[1]
  assert(line, 'No line found in display buffer')
  local test_name = line:match('[' .. icons:gsub('.', '%%%1') .. ']%s+([%w_%-]+)')
  assert(test_name, 'No test name found in line: ' .. line)
  return test_name
end

function Test_Display:jump_to_test_location()
  self:assert_display_buf_win()
  local test_name = self:get_test_name_from_cursor()
  local test_info = self.tests_info[test_name]
  assert(test_info, 'No test info found for test: ' .. test_name)
  vim.api.nvim_set_current_win(self.original_test_win)
  if not test_info.test_line then
    Test_Display:_jump_to_test_location_using_lsp(test_info.name)
    return
  end

  assert(test_info.filepath, 'No filepath found for test: ' .. test_name)
  vim.cmd('edit ' .. test_info.filepath)

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

function Test_Display:_jump_to_test_location_using_lsp(test_name)
  vim.lsp.buf_request(0, 'workspace/symbol', { query = test_name }, function(err, res)
    if err or not res or #res == 0 then
      vim.notify('No definition found for test: ' .. test_name, vim.log.levels.WARN)
    else
      local result = res[1] -- Take the first result
      local filename = vim.uri_to_fname(result.location.uri)
      local start = result.location.range.start

      vim.cmd('edit ' .. filename)
      vim.api.nvim_win_set_cursor(0, { start.line + 1, start.character })
    end
  end)
end

function Test_Display:setup_keymaps()
  local this = self -- Capture the current 'self' reference
  local map_opts = { buffer = self.display_buf, noremap = true, silent = true }
  local map = vim.keymap.set

  map('n', 'q', function() this:close_display() end, map_opts)
  map('n', '<CR>', function() this:jump_to_test_location() end, map_opts)

  local lua_command_format = 'require("terminal_test.terminal_test").terminals:toggle_float_terminal("%s")'
  map('n', 't', function()
    local test_name = this:get_test_name_from_cursor()
    assert(test_name, 'No test name found')
    vim.cmd([[lua ]] .. string.format(lua_command_format, test_name))
  end, map_opts)

  -- terminal_test.terminals:toggle_float_terminal(test_name)
  -- set_keymap('n', 't', '<cmd>lua require("terminal_test.tracker").toggle_terminal_under_cursor()<CR>')
  -- set_keymap('n', 'd', '<cmd>lua require("terminal_test.tracker").delete_test_under_cursor()<CR>')
  -- set_keymap('n', 'r', '<cmd>lua require("terminal_test.tracker").run_test_under_cursor()<CR>')
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
    self:create_window_and_buf()
  end
end

-- Create a user command for each instance
function Test_Display:register_command(command_name)
  local tracker = self
  vim.api.nvim_create_user_command(command_name, function() tracker:toggle_display() end, {})
end

return Test_Display
