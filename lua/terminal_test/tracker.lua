local fidget = require 'fidget'

---@class Tracker
---@field track_list terminal.testInfo[]
---@field add_test_to_tracker fun(test_command_format: string)
---@field jump_to_tracked_test_by_index fun(index: integer)
---@field toggle_tracked_terminal_by_index fun(index: integer)
---@field select_delete_tracked_test fun()
---@field reset_tracker fun()
---@field toggle_tracker_window fun()
---@field update_tracker_window fun()
local tracker = {
  track_list = {},
  _win_id = nil,
  _buf_id = nil,
  _is_open = false,
}

local terminal_test = require 'terminal_test.terminal_test'
-- local make_notify = require('mini.notify').make_notify {}
local terminals = terminal_test.terminals

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

  local target_test = tracker.track_list[index].name
  fidget.notify(string.format('Jumping to test: %s', target_test), vim.log.levels.INFO)
  vim.lsp.buf_request(0, 'workspace/symbol', { query = target_test }, function(err, res)
    if err or not res or #res == 0 then
      vim.notify('No definition found for test: ' .. target_test, vim.log.levels.ERROR)
      return
    end
    local result = res[1] -- Take the first result
    local filename = vim.uri_to_fname(result.location.uri)
    local start = result.location.range.start
    vim.cmd('edit ' .. filename)
    vim.api.nvim_win_set_cursor(0, { start.line + 1, start.character })
    vim.cmd [[normal! zz]]
  end)
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
  -- Create buffer for the tracker window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'test-tracker')

  -- Set up a split window to the right
  vim.cmd 'vsplit'

  -- Move to the new window and set its buffer
  vim.cmd 'wincmd l'
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Set the width of the new window
  local width = 40 -- Fixed width for the split
  vim.api.nvim_win_set_width(win, width)

  -- Set window options
  vim.api.nvim_win_set_option(win, 'wrap', false)
  vim.api.nvim_win_set_option(win, 'cursorline', true)
  vim.api.nvim_win_set_option(win, 'number', false)
  vim.api.nvim_win_set_option(win, 'relativenumber', false)
  vim.api.nvim_win_set_option(win, 'signcolumn', 'no')

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
  vim.api.nvim_buf_add_highlight(buf, ns_id, 'Title', 0, 0, -1)

  -- Update buffer content
  tracker.update_tracker_window()

  -- Return focus to the previous window
  vim.cmd 'wincmd p'
end

-- Update the tracker window content
function tracker.update_tracker_window()
  if not tracker._win_id or not vim.api.nvim_win_is_valid(tracker._win_id) then
    return
  end

  local lines = { ' Test Tracker ', '' } -- Title and empty line

  -- Add test entries
  for i, test_info in ipairs(tracker.track_list) do
    -- Get a shorter version of test name for display
    local short_name = test_info.name
    if #short_name > 30 then
      short_name = '...' .. string.sub(short_name, -27)
    end

    -- Format status with icons
    local status_icon = '❓' -- default for unknown status
    local status = test_info.status or 'not run'

    if status == 'pass' then
      status_icon = '✅'
    elseif status == 'fail' then
      status_icon = '❌'
    elseif status == 'cont' then
      status_icon = '🔥'
    elseif status == 'start' then
      status_icon = '🏁'
    elseif status == 'not run' then
      status_icon = '⏺️'
    end

    -- Add to lines using "Test_name: <status_icon>" format for easier parsing
    local line = string.format(' %d. %s: %s', i, short_name, status_icon)

    table.insert(lines, line)
  end

  if #tracker.track_list == 0 then
    table.insert(lines, ' No tests tracked')
  end

  -- Add help footer
  table.insert(lines, '')
  local window_width = vim.api.nvim_win_get_width(tracker._win_id)
  table.insert(lines, string.rep('─', window_width - 2))
  table.insert(lines, ' Help:')
  table.insert(lines, ' q: Close')
  table.insert(lines, ' <CR>: Jump')
  table.insert(lines, ' t: Toggle')
  table.insert(lines, ' r: Run')
  table.insert(lines, ' d: Delete')

  -- Set buffer content
  vim.api.nvim_buf_set_lines(tracker._buf_id, 0, -1, false, lines)

  -- Apply highlighting
  local ns_id = vim.api.nvim_create_namespace 'test_tracker_highlight'
  vim.api.nvim_buf_clear_namespace(tracker._buf_id, ns_id, 0, -1)
  -- Highlight title
  vim.api.nvim_buf_add_highlight(tracker._buf_id, ns_id, 'Title', 0, 0, -1)

  -- Highlight footer
  local footer_start = #lines - 6 -- This should point to the separator line
  vim.api.nvim_buf_add_highlight(tracker._buf_id, ns_id, 'NonText', footer_start, 0, -1)

  -- Highlight help text lines
  for i = footer_start + 1, #lines - 1 do
    vim.api.nvim_buf_add_highlight(tracker._buf_id, ns_id, 'Comment', i, 0, -1)
  end

  -- Highlight test statuses (icons)
  for i = 3, footer_start - 1 do
    if i - 3 < #tracker.track_list then
      local status = tracker.track_list[i - 2].status or 'not run'
      local line = lines[i]
      local icon_pos = line:find ': [^%s]'
      if icon_pos then
        local hl_group = 'Normal'
        if status == 'passed' then
          hl_group = 'DiagnosticOk'
        elseif status == 'failed' then
          hl_group = 'DiagnosticError'
        elseif status == 'running' then
          hl_group = 'DiagnosticWarn'
        end

        -- Highlight the icon
        vim.api.nvim_buf_add_highlight(tracker._buf_id, ns_id, hl_group, i, icon_pos + 1, -1)
      end
    end
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

-- Helper function to get test index under cursor by parsing the line text
function tracker.get_test_index_under_cursor()
  -- Get the current cursor position
  local cursor_pos = vim.api.nvim_win_get_cursor(tracker._win_id)
  local line_nr = cursor_pos[1]

  -- Get the text of the current line
  local line_text = vim.api.nvim_buf_get_lines(tracker._buf_id, line_nr - 1, line_nr, false)[1]
  print(line_text)

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

  -- Extract the index number from the line (e.g., " 1. Test_name: ✅")
  local index = tonumber(line_text:match '^%s*(%d+)%.%s')

  if index and index <= #tracker.track_list then
    return index
  end

  -- If we couldn't extract a valid index, return nil
  return nil
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
      test_info.status = 'running'
      tracker.update_tracker_window()
      terminal_test.test_in_terminal(test_info)

      -- Also toggle the terminal to show it
      tracker.toggle_tracked_terminal_by_index(index)
    end
  end
end

return tracker
