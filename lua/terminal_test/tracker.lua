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

local display = require 'go-test-t-display'
local tests_info_instance = {}
---@type Tracker
local tracker = {
  track_list = tests_info_instance,
  displayer = display.new(tests_info_instance),
  _original_win_id = nil,
  _win_id = nil,
  _buf_id = nil,
  _is_open = false,
}

tracker.add_test_to_tracker = function(test_command_format)
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  for _, existing_test_info in ipairs(tracker.track_list) do
    if existing_test_info.name == test_name then
      fidget.notify(string.format('Test already in tracker: %s', test_name))
      return
    end
  end
  local source_bufnr = vim.api.nvim_get_current_buf()
  local test_command = string.format(test_command_format, test_name)
  table.insert(tracker.track_list, {
    name = test_name,
    test_line = test_line,
    test_bufnr = source_bufnr,
    test_command = test_command,
    status = 'tracked',
    file = vim.fn.expand '%:p',
  })

  if not tracker._is_open then
    tracker.toggle_tracker_window()
  end
  tracker.update_tracker_window()
end

function tracker.jump_to_tracked_test_by_index(index)
  if index > #tracker.track_list then
    index = #tracker.track_list
  end
  if index < 1 then
    vim.notify(string.format('Invalid index: %d', index), vim.log.levels.ERROR)
    return
  end

  local test_info = tracker.track_list[index]
  local target_test = test_info.name

  fidget.notify(string.format('Jumping to test: %s', target_test), vim.log.levels.INFO)
  vim.api.nvim_set_current_win(tracker._original_win_id)

  if vim.api.nvim_buf_is_valid(test_info.test_bufnr) then
    vim.api.nvim_set_current_buf(test_info.test_bufnr)
    vim.api.nvim_win_set_cursor(0, { test_info.test_line, 0 })
    vim.cmd [[normal! zz]]
  else
    vim.notify('Test buffer no longer valid for: ' .. target_test, vim.log.levels.ERROR)
  end
end

function tracker.toggle_tracked_terminal_by_index(index)
  assert(index, 'No index provided')
  assert(tracker.track_list, 'No test tracked')
  assert(terminals, 'No terminal found')
  assert(index <= #tracker.track_list, 'Index out of bounds')
  local target_test = tracker.track_list[index].name
  terminals:toggle_float_terminal(target_test)
end

function tracker.reset_tracker()
  for test_name, _ in pairs(terminals.all_terminals) do
    terminals:delete_terminal(test_name)
  end
  vim.api.nvim_buf_clear_namespace(0, -1, 0, -1)
  tracker.track_list = {}

  if tracker._is_open then
    tracker.update_tracker_window()
  end
end

function tracker._create_tracker_window()
  tracker._original_win_id = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('filetype', 'test-tracker', { buf = buf })

  vim.cmd 'vsplit'
  vim.cmd 'wincmd l'
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  vim.api.nvim_win_set_width(win, tracker_win_width)
  vim.api.nvim_set_option_value('wrap', false, { win = win })
  vim.api.nvim_set_option_value('cursorline', true, { win = win })
  vim.api.nvim_set_option_value('number', false, { win = win })
  vim.api.nvim_set_option_value('relativenumber', false, { win = win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { win = win })

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      tracker._is_open = false
      tracker._win_id = nil
      tracker._buf_id = nil
    end,
  })
  tracker._win_id = win
  tracker._buf_id = buf
  tracker._is_open = true

  local function set_keymap(mode, lhs, rhs) vim.api.nvim_buf_set_keymap(buf, mode, lhs, rhs, { noremap = true, silent = true }) end
  set_keymap('n', 'q', '<cmd>lua require("terminal_test.tracker").toggle_tracker_window()<CR>')
  set_keymap('n', '<CR>', '<cmd>lua require("terminal_test.tracker").jump_to_test_under_cursor()<CR>')
  set_keymap('n', 't', '<cmd>lua require("terminal_test.tracker").toggle_terminal_under_cursor()<CR>')
  set_keymap('n', 'd', '<cmd>lua require("terminal_test.tracker").delete_test_under_cursor()<CR>')
  set_keymap('n', 'r', '<cmd>lua require("terminal_test.tracker").run_test_under_cursor()<CR>')
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { ' Test Tracker ', '' })
  vim.api.nvim_buf_set_extmark(buf, ns_id, 0, 0, { hl_group = 'Title' })
  tracker.update_tracker_window()
  vim.cmd 'wincmd p'
end

function tracker.update_tracker_window()
  if not tracker._win_id or not vim.api.nvim_win_is_valid(tracker._win_id) then
    vim.notify('Tracker window is not valid', vim.log.levels.WARN)
    return
  end

  local lines = { ' Test Tracker ', '' }
  for i, test_info in ipairs(tracker.track_list) do
    local status_icon = util_status_icon.get_status_icon(test_info.status)
    local line = string.format(' %d. %s: %s', i, test_info.name, status_icon)
    table.insert(lines, line)
  end

  if #tracker.track_list == 0 then
    table.insert(lines, ' No tests tracked')
  end
  table.insert(lines, '')

  local window_width = vim.api.nvim_win_get_width(tracker._win_id)
  table.insert(lines, string.rep('─', window_width - 2))
  for _, item in ipairs(help_items) do
    table.insert(lines, ' ' .. item)
  end

  vim.api.nvim_buf_set_lines(tracker._buf_id, 0, -1, false, lines)

  vim.api.nvim_buf_clear_namespace(tracker._buf_id, ns_id, 0, -1)
  vim.api.nvim_buf_set_extmark(tracker._buf_id, ns_id, 0, 0, {
    end_col = #lines[1],
    hl_group = 'Title',
  })
  local footer_start = #lines - 6
  for i = footer_start, #lines - 1 do
    vim.api.nvim_buf_set_extmark(tracker._buf_id, ns_id, i, 0, {
      end_col = #lines[i + 1],
      hl_group = 'Comment',
    })
  end
end

tracker.toggle_tracker_window = function()
  if tracker._is_open and tracker._win_id and vim.api.nvim_win_is_valid(tracker._win_id) then
    vim.api.nvim_win_close(tracker._win_id, true)
    tracker._is_open = false
    tracker._win_id = nil
    tracker._buf_id = nil
  else
    tracker._create_tracker_window()
  end
end

---@return integer?
function tracker.get_test_index_under_cursor()
  local cursor_pos = vim.api.nvim_win_get_cursor(tracker._win_id)
  local line_nr = cursor_pos[1]
  local line_text = vim.api.nvim_buf_get_lines(tracker._buf_id, line_nr - 1, line_nr, false)[1]
  if
    not line_text
    or line_text == ''
    or line_text:match '^%s*$'
    or line_text:match 'Test Tracker'
    or line_text:match 'Help:'
    or line_text:match '^%s*─+%s*$'
    or line_text:match 'No tests tracked'
  then
    return nil
  end

  local index = tonumber(line_text:match '^%s*(%d+)%.%s') -- (e.g., " 1. Test_name: ✅")
  assert(index, 'Failed to extract index from line: ' .. line_text)
  return index
end

function tracker.jump_to_test_under_cursor()
  local index = tracker.get_test_index_under_cursor()
  if index then
    tracker.jump_to_tracked_test_by_index(index)
  end
end

function tracker.toggle_terminal_under_cursor()
  local index = tracker.get_test_index_under_cursor()
  if index then
    tracker.toggle_tracked_terminal_by_index(index)
  end
end

function tracker.delete_test_under_cursor()
  local index = tracker.get_test_index_under_cursor()
  if index then
    local test_info = tracker.track_list[index]
    if test_info then
      terminals:delete_terminal(test_info.name)
      table.remove(tracker.track_list, index)
      fidget.notify(string.format('Deleted test terminal: %s', test_info.name))
      tracker.update_tracker_window()
    end
  end
end

function tracker.run_test_under_cursor()
  local index = tracker.get_test_index_under_cursor()
  if index then
    local test_info = tracker.track_list[index]
    if test_info then
      tracker.update_tracker_window()
      terminal_test.test_in_terminal(test_info, function()
        vim.schedule(function() tracker.update_tracker_window() end)
      end)
    end
  end
end

return tracker
