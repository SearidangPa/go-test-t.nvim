local util_status_icon = require 'util_status_icon'

---@class GoTestDisplay
local Test_Display = {}
Test_Display.__index = Test_Display

---@class Test_Display_Options
---@field display_title string
---@field tests_info?  table<string, terminal.testInfo>
---@field toggle_term_func fun(test_name: string)
---@field rerun_in_term_func fun(test_name: string)

---@param display_opts Test_Display_Options
function Test_Display.new(display_opts)
  assert(display_opts, 'No display options found')
  assert(display_opts.display_title, 'No display title found')
  assert(display_opts.toggle_term_func, 'No toggle term function found')
  assert(display_opts.rerun_in_term_func, 'No rerun in term function found')
  local self = setmetatable({}, Test_Display)
  self.display_win_id = -1
  self.display_bufnr = -1
  self.original_test_win = -1
  self.original_test_buf = -1
  self.ns_id = vim.api.nvim_create_namespace 'go_test_display'
  self.tests_info = display_opts.tests_info or {}
  self.display_title = display_opts.display_title
  self.toggle_term_func = display_opts.toggle_term_func
  self.rerun_in_term_func = display_opts.rerun_in_term_func
  return self
end

function Test_Display:reset(tests_info)
  self.tests_info = tests_info
  self:update_buffer(tests_info)
end

function Test_Display:toggle_display()
  if vim.api.nvim_win_is_valid(self.display_win_id) then
    vim.api.nvim_win_close(self.display_win_id, true)
    self.display_win_id = -1
  else
    self:create_window_and_buf()
  end
end

---@param tests_info table<string, terminal.testInfo>
function Test_Display:update_buffer(tests_info)
  assert(tests_info, 'No test info found')
  self.tests_info = tests_info
  if not self.display_bufnr or not vim.api.nvim_buf_is_valid(self.display_bufnr) then
    return
  end

  local lines = self:_parse_test_state_to_lines(tests_info)
  lines = self:_add_display_help_text(lines)
  vim.api.nvim_buf_set_lines(self.display_bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_extmark(self.display_bufnr, self.ns_id, 0, 0, {
    end_col = #lines[1],
    hl_group = 'Title',
  })
  for i = #lines - #self._help_text_lines, #lines - 1 do
    if i >= 0 and i < #lines then
      vim.api.nvim_buf_set_extmark(self.display_bufnr, self.ns_id, i, 0, {
        end_col = #lines[i + 1],
        hl_group = 'Comment',
      })
    end
  end
end

function Test_Display:create_window_and_buf()
  self.original_test_win = vim.api.nvim_get_current_win()
  self.original_test_buf = vim.api.nvim_get_current_buf()

  if not self.display_bufnr or not vim.api.nvim_buf_is_valid(self.display_bufnr) then
    self.display_bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[self.display_bufnr].bufhidden = 'hide'
    vim.bo[self.display_bufnr].buftype = 'nofile'
    vim.bo[self.display_bufnr].swapfile = false
  end

  if not self.display_win_id or not vim.api.nvim_win_is_valid(self.display_win_id) then
    vim.cmd 'vsplit'
    self.display_win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.display_win_id, self.display_bufnr)
    vim.api.nvim_win_set_width(self.display_win_id, math.floor(vim.o.columns / 3))
    vim.api.nvim_win_set_height(self.display_win_id, math.floor(vim.o.lines - 2))
    vim.wo[self.display_win_id].number = false
    vim.wo[self.display_win_id].relativenumber = false
    vim.wo[self.display_win_id].wrap = false
    vim.wo[self.display_win_id].signcolumn = 'no'
    vim.wo[self.display_win_id].foldenable = false
  end

  vim.api.nvim_set_current_win(self.original_test_win)
  self:_setup_keymaps()
end

--- === Private Functions ===

local function _sort_tests_by_status(tests)
  table.sort(tests, function(a, b)
    if a.status == b.status then
      return a.name < b.name
    end
    local priority = {
      fail = 1,
      paused = 2,
      cont = 3,
      start = 4,
      running = 5,
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

---@param tests_info  table<string, terminal.testInfo>
function Test_Display:_parse_test_state_to_lines(tests_info)
  assert(tests_info, 'No test info found')
  local tests_table = {}
  local buf_lines = { self.display_title }

  for _, test in pairs(tests_info) do
    if test.name then
      table.insert(tests_table, test)
    end
  end
  _sort_tests_by_status(tests_table)

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

function Test_Display:_add_display_help_text(buf_lines)
  if self.display_win_id and vim.api.nvim_win_is_valid(self.display_win_id) then
    local window_width = vim.api.nvim_win_get_width(self.display_win_id)
    table.insert(buf_lines, string.rep('─', window_width - 2))
  end
  for _, item in ipairs(self._help_text_lines) do
    table.insert(buf_lines, ' ' .. item)
  end
  return buf_lines
end

function Test_Display:_assert_display_buf_win()
  assert(self.display_bufnr, 'display_buf is nil in jump_to_test_location')
  assert(self.display_win_id, 'display_win is nil in jump_to_test_location')
end

local icons = '🔥❌✅🔄⏸️🪵⏺️🏁'

function Test_Display:_get_test_name_from_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_nr = cursor[1]
  local line = vim.api.nvim_buf_get_lines(self.display_bufnr, line_nr - 1, line_nr, false)[1]
  assert(line, 'No line found in display buffer')
  local test_name = line:match('[' .. icons:gsub('.', '%%%1') .. ']%s+([%w_%-]+)')
  assert(test_name, 'No test name found in line: ' .. line)
  return test_name
end

function Test_Display:_jump_to_test_location_from_cursor()
  self:_assert_display_buf_win()
  local test_name = self:_get_test_name_from_cursor()
  local test_info = self.tests_info[test_name]
  assert(test_info, 'No test info found for test: ' .. test_name)
  if test_info.filepath and test_info.test_line then
    self:_jump_to_test_location(test_info.filepath, test_info.test_line, test_name, test_info.fail_at_line)
    return
  end

  require('util_lsp').action_from_test_name(
    test_name,
    function(lsp_param) self:_jump_to_test_location(lsp_param.filepath, lsp_param.test_line, test_name, test_info.fail_at_line) end
  )
end

function Test_Display:_jump_to_test_location(filepath, test_line, test_name, fail_at_line)
  assert(test_name, 'No test name found for test')
  assert(filepath, 'No filepath found for test: ' .. test_name)
  assert(test_line, 'No test line found for test: ' .. test_name)

  vim.api.nvim_set_current_win(self.original_test_win)
  vim.cmd('edit ' .. filepath)

  if fail_at_line then
    vim.api.nvim_win_set_cursor(0, { tonumber(fail_at_line), 0 })
    vim.cmd 'normal! zz'
  elseif test_line then
    local pos = { test_line, 0 }
    vim.api.nvim_win_set_cursor(0, pos)
    vim.cmd 'normal! zz'
  else
  end
end

function Test_Display:_setup_keymaps()
  local this = self -- Capture the current 'self' reference
  local map_opts = { buffer = self.display_bufnr, noremap = true, silent = true }
  local map = vim.keymap.set

  map('n', 'q', function() this:_close_display() end, map_opts)
  map('n', '<CR>', function() this:_jump_to_test_location_from_cursor() end, map_opts)

  map('n', 't', function()
    local test_name = this:_get_test_name_from_cursor()
    assert(test_name, 'No test name found')
    self.toggle_term_func(test_name)
  end, map_opts)

  map('n', 'r', function()
    local test_name = this:_get_test_name_from_cursor()
    assert(test_name, 'No test name found')
    self.rerun_in_term_func(test_name)
  end, map_opts)

  map('n', 'K', function()
    local test_name = this:_get_test_name_from_cursor()
    assert(test_name, 'No test name found')
    local status = self.tests_info[test_name].status
    print('Status of ' .. test_name .. ': ' .. status)
  end, map_opts)
end

function Test_Display:_close_display()
  if vim.api.nvim_win_is_valid(self.display_win_id) then
    vim.api.nvim_win_close(self.display_win_id, true)
    self.display_win_id = -1
  end
end

Test_Display._help_text_lines = {
  ' Help 🧊',
  ' q       ===  Close Tracker Window',
  ' <CR> ===  Jump to test code',
  ' t       ===  Toggle test terminal',
  ' r       ===  Run test in terminal',
  ' d       ===  Delete from tracker',
}

return Test_Display
