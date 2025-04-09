local M = {}
local terminal_test = require 'terminal_test.terminal_test'
local make_notify = require('mini.notify').make_notify {}
local map = vim.keymap.set
local terminals_tests = terminal_test.terminals

M.track_test_list = {}

M.view_tests_tracked = function()
  if vim.api.nvim_win_is_valid(M.view_tracker) then
    vim.api.nvim_win_close(M.view_tracker, true)
    return
  end

  local all_tracked_tests = { '', '' }

  for _, test_info in ipairs(M.track_test_list) do
    if test_info.status == 'failed' then
      table.insert(all_tracked_tests, '\t' .. '❌' .. '  ' .. test_info.test_name)
    elseif test_info.status == 'passed' then
      table.insert(all_tracked_tests, '\t' .. '✅' .. '  ' .. test_info.test_name)
    else
      table.insert(all_tracked_tests, '\t' .. '⏳' .. '  ' .. test_info.test_name)
    end
  end

  local width = math.floor(vim.o.columns * 0.5)
  local height = math.floor(vim.o.lines * 0.3)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, all_tracked_tests)
  M.view_tracker = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = 'Go Test Tracker',
    title_pos = 'center',
  })
  vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(M.view_tracker, true) end, { buffer = buf })
end

M.add_test_to_tracker = function(test_command_format)
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  for _, existing_test_info in ipairs(M.track_test_list) do
    if existing_test_info.test_name == test_name then
      make_notify(string.format('Test already in tracker: %s', test_name))
      return
    end
  end
  local source_bufnr = vim.api.nvim_get_current_buf()
  local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command_format }
  table.insert(M.track_test_list, test_info)
end

vim.keymap.set('n', '<leader>at', M.add_test_to_tracker, { desc = '[A]dd [T]est to tracker' })

local function jump_to_tracked_test_by_index(index)
  if index > #M.track_test_list then
    index = #M.track_test_list
  end
  if index < 1 then
    vim.notify(string.format('Invalid index: %d', index), vim.log.levels.ERROR)
    return
  end

  local target_test = M.track_test_list[index].test_name

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

for _, idx in ipairs { 1, 2, 3, 4, 5, 6 } do
  map('n', string.format('<leader>%d', idx), function() jump_to_tracked_test_by_index(idx) end, { desc = string.format('Jump to tracked test %d', idx) })
end

local function toggle_tracked_test_by_index(index)
  if index > #M.track_test_list then
    index = #M.track_test_list
  end
  local target_test = M.track_test_list[index].test_name
  terminals_tests:toggle_float_terminal(target_test)
end

for _, idx in ipairs { 1, 2, 3, 4, 5, 6 } do
  map('n', string.format('<localleader>v%d', idx), function() toggle_tracked_test_by_index(idx) end, { desc = string.format('Toggle tracked test %d', idx) })
end

function M.delete_tracked_test()
  local opts = {
    prompt = 'Select tracked test to delete',
    format_item = function(item) return item end,
  }

  local all_tracked_test_names = {}
  for _, testInfo in ipairs(M.track_test_list) do
    table.insert(all_tracked_test_names, testInfo.test_name)
  end

  local handle_choice = function(tracked_test_name)
    for index, testInfo in ipairs(M.track_test_list) do
      if testInfo.test_name == tracked_test_name then
        terminals_tests:delete_terminal(tracked_test_name)
        table.remove(M.track_test_list, index)
        make_notify(string.format('Deleted test terminal from tracker: %s', tracked_test_name))
        break
      end
    end
  end

  vim.ui.select(all_tracked_test_names, opts, function(choice) handle_choice(choice) end)
end

---Reset all test terminals
---@return nil
M.reset_test = function()
  for test_name, _ in pairs(terminals_tests.all_terminals) do
    terminals_tests:delete_terminal(test_name)
  end

  vim.api.nvim_buf_clear_namespace(0, -1, 0, -1)
  M.track_test_list = {}
end

return M
