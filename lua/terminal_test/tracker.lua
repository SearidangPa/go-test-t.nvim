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
---@field _create_tracker_window fun()
---@field _win_id integer|nil
---@field _buf_id integer|nil
---@field _is_open boolean
local tracker = {
  track_list = {}, ---@type terminal.testInfo[]
  _win_id = nil,
  _buf_id = nil,
  _is_open = false,
}

local terminal_test = require 'terminal_test.terminal_test'
local make_notify = require('mini.notify').make_notify {}
local terminals = terminal_test.terminals

tracker.add_test_to_tracker = function(test_command_format)
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  for _, existing_test_info in ipairs(tracker.track_list) do
    if existing_test_info.name == test_name then
      make_notify(string.format('Test already in tracker: %s', test_name))
      return
    end
  end
  local source_bufnr = vim.api.nvim_get_current_buf()
  table.insert(tracker.track_list, {
    name = test_name,
    test_line = test_line,
    test_bufnr = source_bufnr,
    test_command = test_command_format,
    status = 'start',
  })

  if tracker._is_open then
    tracker.update_tracker_window()
  end
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

-- Create the tracker window
function tracker._create_tracker_window()
  -- Create buffer for the tracker window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'test-tracker')

  -- Get dimensions for the window
  local width = math.floor(vim.o.columns * 0.2) -- 20% of screen width
  local height = vim.o.lines - 4
  local col = vim.o.columns - width - 1
  local row = 2

  -- Set window options
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' Test Tracker ',
    title_pos = 'center',
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, false, opts)

  -- Set window options
  -- vim.api.nvim_set_option_value('winhl', 'Normal:Normal,FloatBorder:FloatBorder', { win = win })
  vim.api.nvim_win_set_option(win, 'winhighlight', 'Normal:Normal,FloatBorder:FloatBorder')
  vim.api.nvim_win_set_option(win, 'wrap', false)
  vim.api.nvim_win_set_option(win, 'cursorline', true)

  -- Save window and buffer IDs
  tracker._win_id = win
  tracker._buf_id = buf
  tracker._is_open = true

  -- Set up keymaps for the tracker window
  local function set_keymap(mode, lhs, rhs) vim.api.nvim_buf_set_keymap(buf, mode, lhs, rhs, { noremap = true, silent = true }) end

  -- Close window with q or <Esc>
  set_keymap('n', 'q', '<cmd>lua require("test_tracker").toggle_tracker_window()<CR>')

  -- Jump to test under cursor
  set_keymap('n', '<CR>', '<cmd>lua require("test_tracker").jump_to_test_under_cursor()<CR>')

  -- Toggle terminal for test under cursor
  set_keymap('n', 't', '<cmd>lua require("test_tracker").toggle_terminal_under_cursor()<CR>')

  -- Delete test under cursor
  set_keymap('n', 'd', '<cmd>lua require("test_tracker").delete_test_under_cursor()<CR>')

  -- Run test under cursor
  set_keymap('n', 'r', '<cmd>lua require("test_tracker").run_test_under_cursor()<CR>')

  -- Update buffer content
  tracker.update_tracker_window()
end

-- Update the tracker window content
function tracker.update_tracker_window()
  if not tracker._win_id or not vim.api.nvim_win_is_valid(tracker._win_id) then
    return
  end

  local lines = {}

  -- Add test entries
  for i, test_info in ipairs(tracker.track_list) do
    -- Get a shorter version of test name for display (max 30 chars)
    local short_name = test_info.name
    if #short_name > 30 then
      short_name = '...' .. string.sub(short_name, -27)
    end

    -- Format status
    local status = test_info.status or 'not run'

    -- Add to lines (with padding)
    local line = string.format(' %s%s%s ', short_name, string.rep(' ', 30 - #short_name), status)

    table.insert(lines, line)
  end

  if #tracker.track_list == 0 then
    table.insert(lines, ' No tests tracked')
  end

  -- Add help footer
  table.insert(lines, '')
  table.insert(lines, string.rep('─', vim.api.nvim_win_get_width(tracker._win_id) - 2))
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

  -- Highlight footer
  local footer_start = #lines - 6 -- This should point to the separator line
  vim.api.nvim_buf_add_highlight(tracker._buf_id, ns_id, 'NonText', footer_start, 0, -1)

  -- Highlight help text lines
  for i = footer_start + 1, #lines - 1 do
    vim.api.nvim_buf_add_highlight(tracker._buf_id, ns_id, 'Comment', i, 0, -1)
  end

  -- Highlight test statuses
  for i = 3, footer_start - 1 do
    if i - 3 < #tracker.track_list then
      local test_info = tracker.track_list[i - 2]
      if test_info and test_info.status then
        local status_col_start = 32
        local status_col_end = status_col_start + #test_info.status + 1

        -- Different highlight based on status
        local hl_group = 'Normal'
        if test_info.status == 'passed' then
          hl_group = 'DiagnosticOk'
        elseif test_info.status == 'failed' then
          hl_group = 'DiagnosticError'
        elseif test_info.status == 'running' then
          hl_group = 'DiagnosticWarn'
        end

        vim.api.nvim_buf_add_highlight(tracker._buf_id, ns_id, hl_group, i - 1, status_col_start, status_col_end)
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

-- Helper function to get test index under cursor
function tracker.get_test_index_under_cursor()
  local cursor_pos = vim.api.nvim_win_get_cursor(tracker._win_id)
  local line_nr = cursor_pos[1]

  -- Accounting for header (2 lines) and only considering test lines
  if line_nr >= 3 and line_nr < 3 + #tracker.track_list then
    return line_nr - 2
  end

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
      make_notify(string.format('Deleted test terminal: %s', test_info.name))
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

      -- Run the test
      local formatted_command = string.format(test_info.test_command, test_info.name)
      fidget.notify('Running test: ' .. formatted_command, vim.log.levels.INFO)
      terminal_test.test_in_terminal(test_info)
      -- terminal_test.test_in_terminal(test_info.name, formatted_command, {
      --   on_stdout = function(_, data)
      --     -- Simple success/failure detection
      --     if data and data:match 'test passed' then
      --       test_info.status = 'passed'
      --     elseif data and data:match 'test failed' then
      --       test_info.status = 'failed'
      --     end
      --     tracker.update_tracker_window()
      --   end,
      --   on_exit = function(_, code)
      --     if code == 0 then
      --       test_info.status = 'passed'
      --     else
      --       test_info.status = 'failed'
      --     end
      --     tracker.update_tracker_window()
      --   end,
      -- })

      -- Also toggle the terminal to show it
      tracker.toggle_tracked_terminal_by_index(index)
    end
  end
end

return tracker
