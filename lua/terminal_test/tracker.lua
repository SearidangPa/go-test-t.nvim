local tracker = {
  track_list = {}, ---@type terminal.testInfo[]
}

---@class tracker
---@field track_list terminal.testInfo[]
---@field add_test_to_tracker fun(test_command_format: string)
---@field jump_to_tracked_test_by_index fun(index: integer)
---@field toggle_tracked_terminal_by_index fun(index: integer)
---@field delete_tracked_test fun()
---@field reset_test fun()

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
end

vim.keymap.set('n', '<leader>at', tracker.add_test_to_tracker, { desc = '[A]dd [T]est to tracker' })

tracker.jump_to_tracked_test_by_index = function(index)
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

tracker.toggle_tracked_terminal_by_index = function(index)
  if index > #tracker.track_list then
    index = #tracker.track_list
  end
  local target_test = tracker.track_list[index].name
  terminals:toggle_float_terminal(target_test)
end

function tracker.delete_tracked_test()
  local opts = {
    prompt = 'Select tracked test to delete',
    format_item = function(item) return item end,
  }

  local all_tracked_test_names = {}
  for _, testInfo in ipairs(tracker.track_list) do
    table.insert(all_tracked_test_names, testInfo.name)
  end

  local handle_choice = function(tracked_test_name)
    for index, testInfo in ipairs(tracker.track_list) do
      if testInfo.name == tracked_test_name then
        terminals:delete_terminal(tracked_test_name)
        table.remove(tracker.track_list, index)
        make_notify(string.format('Deleted test terminal from tracker: %s', tracked_test_name))
        break
      end
    end
  end

  vim.ui.select(all_tracked_test_names, opts, function(choice) handle_choice(choice) end)
end

tracker.reset_tracker = function()
  for test_name, _ in pairs(terminals.all_terminals) do
    terminals:delete_terminal(test_name)
  end

  vim.api.nvim_buf_clear_namespace(0, -1, 0, -1)
  tracker.track_list = {}
end

return tracker
