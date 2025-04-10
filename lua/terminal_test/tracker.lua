local fidget = require 'fidget'
local terminal_test = require 'terminal_test.terminal_test'
local terminals = terminal_test.terminals

---@type Tracker
local tracker = {
  track_list = {},
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

  -- Jump directly to the buffer and line where the test was found
  if vim.api.nvim_buf_is_valid(test_info.test_bufnr) then
    vim.api.nvim_set_current_buf(test_info.test_bufnr)
    vim.api.nvim_win_set_cursor(0, { test_info.test_line, 0 })
    vim.cmd [[normal! zz]]
  else
    vim.notify('Test buffer no longer valid for: ' .. target_test, vim.log.levels.ERROR)
  end
end

function tracker.toggle_tracked_terminal_by_index(index)
  if index > #tracker.track_list then
    index = #tracker.track_list
  end
  local target_test = tracker.track_list[index].name
  terminals:toggle_float_terminal(target_test)
end

function tracker.reset_tracker()
  for test_name, _ in pairs(terminals.all_terminals) do
    terminals:delete_terminal(test_name)
  end
  vim.api.nvim_buf_clear_namespace(0, -1, 0, -1)
  tracker.track_list = {}

  -- Update the tracker window if it's open
  if tracker._is_open then
    tracker.update_tracker_window()
  end
end

-- Create the tracker window as a split window instead of floating
function tracker._create_tracker_window()
  tracker._original_win_id = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('filetype', 'test-tracker', { buf = buf })

  vim.cmd 'vsplit'

  -- Move to the new window and set its buffer
  vim.cmd 'wincmd l'
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Set the width of the new window
  local width = 40 -- Fixed width for the split
  vim.api.nvim_win_set_width(win, width)

  -- Set window options
  vim.api.nvim_set_option_value('wrap', false, { win = win })
  vim.api.nvim_set_option_value('cursorline', true, { win = win })
  vim.api.nvim_set_option_value('number', false, { win = win })
  vim.api.nvim_set_option_value('relativenumber', false, { win = win })
  vim.api.nvim_set_option_value('signcolumn', 'no', { win = win })

  -- Add a buffer-local auto command to close the window properly
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      tracker._is_open = false
      tracker._win_id = nil
      tracker._buf_id = nil
    end,
  })

  -- Save window and buffer IDs
  tracker._win_id = win
  tracker._buf_id = buf
  tracker._is_open = true

  local function set_keymap(mode, lhs, rhs) vim.api.nvim_buf_set_keymap(buf, mode, lhs, rhs, { noremap = true, silent = true }) end

  set_keymap('n', 'q', '<cmd>lua require("terminal_test.tracker").toggle_tracker_window()<CR>')
  set_keymap('n', '<CR>', '<cmd>lua require("terminal_test.tracker").jump_to_test_under_cursor()<CR>')
  set_keymap('n', 't', '<cmd>lua require("terminal_test.tracker").toggle_terminal_under_cursor()<CR>')
  set_keymap('n', 'd', '<cmd>lua require("terminal_test.tracker").delete_test_under_cursor()<CR>')
  set_keymap('n', 'r', '<cmd>lua require("terminal_test.tracker").run_test_under_cursor()<CR>')

  -- Add a title to the window
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { ' Test Tracker ', '' })
  local ns_id = vim.api.nvim_create_namespace 'test_tracker_highlight'
  vim.api.nvim_buf_set_extmark(buf, ns_id, 0, 0, { hl_group = 'Title' })
  -- Update buffer content
  tracker.update_tracker_window()

  -- Return focus to the previous window
  vim.cmd 'wincmd p'
end

function tracker.update_tracker_window()
  if not tracker._win_id or not vim.api.nvim_win_is_valid(tracker._win_id) then
    return
  end
  local lines = { ' Test Tracker ', '' }
  for i, test_info in ipairs(tracker.track_list) do
    local short_name = test_info.name
    if #short_name > 30 then
      short_name = '...' .. string.sub(short_name, -27)
    end
    local status_icon = '❓'
    local status = test_info.status or 'not run'
    if status == 'pass' then
      status_icon = '✅'
    elseif status == 'fail' then
      status_icon = '❌'
    elseif status == 'cont' then
      status_icon = '🔥'
    elseif status == 'start' then
      status_icon = '🚀'
    elseif status == 'not run' then
      status_icon = '⏺️'
    elseif status == 'tracked' then
      status_icon = '🏁'
    else
      vim.notify('Unknown status: ' .. status, vim.log.levels.WARN)
    end
    local line = string.format(' %d. %s: %s', i, short_name, status_icon)
    table.insert(lines, line)
  end
  if #tracker.track_list == 0 then
    table.insert(lines, ' No tests tracked')
  end
  table.insert(lines, '')
  local window_width = vim.api.nvim_win_get_width(tracker._win_id)
  table.insert(lines, string.rep('─', window_width - 2))
  table.insert(lines, ' Help:')
  table.insert(lines, ' q: Close')
  table.insert(lines, ' <CR>: Jump')
  table.insert(lines, ' t: Toggle')
  table.insert(lines, ' r: Run')
  table.insert(lines, ' d: Delete')
  vim.api.nvim_buf_set_lines(tracker._buf_id, 0, -1, false, lines)
  local ns_id = vim.api.nvim_create_namespace 'test_tracker_highlight'
  vim.api.nvim_buf_clear_namespace(tracker._buf_id, ns_id, 0, -1)
  vim.api.nvim_buf_set_extmark(tracker._buf_id, ns_id, 0, 0, { hl_group = 'Title' })
  local footer_start = #lines - 6
  vim.api.nvim_buf_set_extmark(tracker._buf_id, ns_id, footer_start, 0, { hl_group = 'Comment' })
  for i = footer_start + 1, #lines - 1 do
    vim.api.nvim_buf_set_extmark(tracker._buf_id, ns_id, i, 0, { hl_group = 'Comment' })
  end
end

-- Toggle tracker window visibility
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
  -- Get the current cursor position
  local cursor_pos = vim.api.nvim_win_get_cursor(tracker._win_id)
  local line_nr = cursor_pos[1]

  -- Get the text of the current line
  local line_text = vim.api.nvim_buf_get_lines(tracker._buf_id, line_nr - 1, line_nr, false)[1]

  -- If the line is empty or we're in the header/footer section, return nil
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

-- Action functions for keymaps
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
      -- Update status
      tracker.update_tracker_window()
      terminal_test.test_in_terminal(test_info)

      -- Also toggle the terminal to show it
      tracker.toggle_tracked_terminal_by_index(index)
    end
  end
end

return tracker
