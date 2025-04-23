local util_status_icon = require 'util_status_icon'

---@class GoTestDisplay
local Test_Display = {}
Test_Display.__index = Test_Display

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
  self.current_buffer_lines = {}
  self.ns_id = vim.api.nvim_create_namespace 'go_test_display'
  self.display_title = display_opts.display_title
  self.toggle_term_func = display_opts.toggle_term_func
  self.rerun_in_term_func = display_opts.rerun_in_term_func
  self.pin_test_func = display_opts.pin_test_func
  self.unpin_test_func = display_opts.unpin_test_func
  self.get_tests_info_func = display_opts.get_tests_info_func
  self.get_pinned_tests_func = display_opts.get_pinned_tests_func

  vim.api.nvim_set_hl(0, 'GoTestPinned', { fg = '#5097A4', bold = true, underline = true })
  return self
end

function Test_Display:reset() self:update_display_buffer {} end

function Test_Display:toggle_display(do_not_close)
  do_not_close = do_not_close or false
  if vim.api.nvim_win_is_valid(self.display_win_id) then
    if do_not_close then
      return
    end
    vim.api.nvim_win_close(self.display_win_id, true)
    self.display_win_id = -1
  else
    self:create_window_and_buf()
    self:update_display_buffer(self.get_tests_info_func())
  end
end

---@param tests_info? table<string, terminal.testInfo>
---@param self GoTestDisplay
function Test_Display:update_display_buffer(tests_info, pin_triggered)
  tests_info = tests_info or {}
  tests_info = vim.list_extend(self.get_tests_info_func(), tests_info)

  if not self.display_bufnr or not vim.api.nvim_buf_is_valid(self.display_bufnr) then
    return
  end

  local new_lines = self:_parse_test_state_to_lines(tests_info)
  new_lines = self:_add_display_help_text(new_lines)

  pin_triggered = pin_triggered or false
  if vim.deep_equal(new_lines, self.current_buffer_lines) and not pin_triggered then
    return
  end
  self.current_buffer_lines = new_lines

  vim.schedule(function()
    vim.api.nvim_buf_set_lines(self.display_bufnr, 0, -1, false, new_lines)
    vim.api.nvim_buf_set_extmark(self.display_bufnr, self.ns_id, 0, 0, {
      end_col = #new_lines[1],
      hl_group = 'Title',
    })

    local line_idx = 1
    for _, test_info in pairs(self.get_pinned_tests_func()) do
      assert(test_info, 'No test info found')
      assert(test_info.name, 'No test name found')
      for i = 1, #new_lines do
        local line = new_lines[i]
        if line:match(test_info.name) then
          vim.api.nvim_buf_set_extmark(self.display_bufnr, self.ns_id, i - 1, 0, {
            end_line = i - 1,
            end_col = #line,
            hl_group = 'GoTestPinned',
          })
          break
        end
      end
      line_idx = line_idx + 1
    end

    for i = #new_lines - #self._help_text_lines, #new_lines - 1 do
      if i >= 0 and i < #new_lines then
        vim.api.nvim_buf_set_extmark(self.display_bufnr, self.ns_id, i, 0, {
          end_col = #new_lines[i + 1],
          hl_group = 'Comment',
        })
      end
    end
  end)
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

---@param tests terminal.testInfo[]
function Test_Display:_sort_tests_by_status(tests)
  table.sort(tests, function(a, b)
    local priority = {
      fail = 1,
      paused = 2,
      cont = 3,
      start = 4,
      running = 5,
      pass = 6,
    }

    local pinned_tests = self.get_pinned_tests_func()
    local is_a_pinned = pinned_tests[a.name] ~= nil
    local is_b_pinned = pinned_tests[b.name] ~= nil

    if is_a_pinned and not is_b_pinned then
      return true
    elseif not is_a_pinned and is_b_pinned then
      return false
    end

    local a_priority = priority[a.status] or 999
    local b_priority = priority[b.status] or 999

    if a_priority ~= b_priority then
      return a_priority < b_priority
    end

    return a.name < b.name
  end)
end

---@param tests_info  table<string, terminal.testInfo>
function Test_Display:_parse_test_state_to_lines(tests_info)
  assert(tests_info, 'No test info found')

  ---@type terminal.testInfo[]
  local tests_table = {}
  local buf_lines = { self.display_title }

  for _, test in pairs(tests_info) do
    assert(test, 'No test info found')
    assert(test.name, 'No test name found')
    if test.name then
      table.insert(tests_table, test)
    end
  end
  self:_sort_tests_by_status(tests_table)

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
  local tests_info = self:get_tests_info_func()
  local test_info = tests_info[test_name]

  assert(test_info, 'No test info found for test: ' .. test_name)
  if test_info.filepath and test_info.test_line then
    self:_jump_to_test_location(test_info.filepath, test_info.test_line, test_name)
    return
  end

  require('util_lsp').action_from_test_name(test_name, function(lsp_param) self:_jump_to_test_location(lsp_param.filepath, lsp_param.test_line, test_name) end)
end

function Test_Display:_jump_to_test_location(filepath, test_line, test_name)
  assert(test_name, 'No test name found for test')
  assert(filepath, 'No filepath found for test: ' .. test_name)
  assert(test_line, 'No test line found for test: ' .. test_name)

  vim.api.nvim_set_current_win(self.original_test_win)
  vim.cmd('edit ' .. filepath)

  if test_line then
    local pos = { test_line, 0 }
    vim.api.nvim_win_set_cursor(0, pos)
    vim.cmd 'normal! zz'
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

  map('n', 'p', function()
    local self_ref = self
    local test_name = this:_get_test_name_from_cursor()
    assert(test_name, 'No test name found')
    local tests_info = self_ref:get_tests_info_func()
    local test_info = tests_info[test_name]
    assert(test_info, 'No test info found for test: ' .. test_name)
    self_ref.pin_test_func(test_info)
    vim.schedule(function() self_ref:update_display_buffer(tests_info, true) end)
  end, map_opts)

  map('n', 'u', function()
    local self_ref = self
    local test_name = this:_get_test_name_from_cursor()
    assert(test_name, 'No test name found')
    local tests_info = self_ref:get_tests_info_func()
    local test_info = tests_info[test_name]
    assert(test_info, 'No test info found for test: ' .. test_name)
    self_ref.unpin_test_func(test_info.name)
    vim.schedule(function() self_ref:update_display_buffer(tests_info, true) end)
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
  ' <CR>    ===  Jump to test code',
  ' t       ===  Toggle test terminal',
  ' r       ===  (Re)Run test in terminal',
  ' p       ===  Pin test',
  ' u       ===  Unpin test',
}

require 'terminal-multiplexer'
---@param float_terminal_state TerminalMultiplexer.FloatTermState
---@param terminal_name string
function Test_Display._create_two_third_float_window(terminal_multiplexer, float_terminal_state, terminal_name)
  local total_width = math.floor(vim.o.columns)
  local width = math.floor(total_width * 2 / 3) - 2 -- Use 2/3 of the screen width
  local height = math.floor(vim.o.lines)
  local row = 0 -- Start from the top
  local col = 0 -- Start from the left

  if float_terminal_state.bufnr == -1 then
    float_terminal_state.bufnr = vim.api.nvim_create_buf(false, true)
  end

  float_terminal_state.footer_buf = vim.api.nvim_create_buf(false, true)
  local padding = string.rep(' ', width - #terminal_name - 1)
  local footer_text = padding .. terminal_name
  vim.api.nvim_buf_set_lines(float_terminal_state.footer_buf, 0, -1, false, { footer_text })
  vim.api.nvim_buf_set_extmark(float_terminal_state.footer_buf, terminal_multiplexer.ns_id, 0, 0, {
    end_row = 0,
    end_col = #footer_text,
    hl_group = 'Title',
  })

  vim.api.nvim_buf_set_extmark(float_terminal_state.footer_buf, terminal_multiplexer.ns_id, 0, #padding, {
    end_row = 0,
    end_col = #footer_text,
    hl_group = 'TerminalNameUnderline',
  })

  float_terminal_state.win = vim.api.nvim_open_win(float_terminal_state.bufnr, true, {
    relative = 'editor',
    width = width,
    height = height - 3,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
  })

  vim.api.nvim_win_call(float_terminal_state.win, function() vim.cmd 'normal! G' end)
  float_terminal_state.footer_win = vim.api.nvim_open_win(float_terminal_state.footer_buf, false, {
    relative = 'editor', -- Changed from 'win' to 'editor' for consistent positioning
    width = width,
    height = 1,
    row = height - 3,
    col = col,
    style = 'minimal',
    border = 'none',
  })
end

return Test_Display
