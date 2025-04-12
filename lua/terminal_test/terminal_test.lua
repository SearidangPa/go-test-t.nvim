local fidget = require 'fidget'
local terminal_multiplexer = require 'terminal_test.terminal_multiplexer'
local util_quickfix = require 'async_job.util_quickfix'
local display = require 'go-test-t-display'

local tests_info_instance = {}
local test_results_title = 'Terminal Test Results'

---@type terminalTest
local terminal_test = {
  terminals = terminal_multiplexer.new(),
  tests_info = tests_info_instance,
  displayer = display.new(tests_info_instance),
  ns_id = vim.api.nvim_create_namespace 'GoTestError',
}

---@param test_info terminal.testInfo
local function validate_test_info(test_info)
  assert(test_info.name, 'No test found')
  assert(test_info.test_bufnr, 'No test buffer found')
  assert(test_info.test_line, 'No test line found')
  assert(test_info.test_command, 'No test command found')
  assert(vim.api.nvim_buf_is_valid(test_info.test_bufnr), 'Invalid buffer')
end

---@param test_info terminal.testInfo
local function handle_test_passed(test_info, float_term_state, current_time, cb_update_tracker)
  if not test_info.set_ext_mark then
    vim.api.nvim_buf_set_extmark(test_info.test_bufnr, terminal_test.ns_id, test_info.test_line - 1, 0, {
      virt_text = { { string.format('✅ %s', current_time) } },
      virt_text_pos = 'eol',
    })
    test_info.set_ext_mark = true
  end
  test_info.status = 'pass'
  float_term_state.status = 'pass'
  terminal_test.tests_info[test_info.name] = test_info
  vim.schedule(function() terminal_test.displayer:update_tracker_buffer(terminal_test.tests_info, test_results_title) end)
  if cb_update_tracker then
    cb_update_tracker(test_info)
  end
end

---@param test_info terminal.testInfo
local function handle_test_failed(test_info, float_term_state, current_time, cb_update_tracker)
  if not test_info.set_ext_mark then
    vim.api.nvim_buf_set_extmark(test_info.test_bufnr, terminal_test.ns_id, test_info.test_line - 1, 0, {
      virt_text = { { string.format('❌ %s', current_time) } },
      virt_text_pos = 'eol',
    })
    test_info.set_ext_mark = true
  end
  test_info.status = 'fail'
  float_term_state.status = 'fail'
  terminal_test.tests_info[test_info.name] = test_info
  util_quickfix.add_fail_test(test_info)
  vim.schedule(function() terminal_test.displayer:update_tracker_buffer(terminal_test.tests_info, test_results_title) end)
  if cb_update_tracker then
    cb_update_tracker(test_info)
  end
end

---@param test_info terminal.testInfo
local function handle_error_trace(line, test_info, cb_update_tracker)
  local file, line_num
  if vim.fn.has 'win32' == 1 then
    file, line_num = string.match(line, 'Error Trace:%s+([%w%p]+):(%d+)')
  else
    file, line_num = string.match(line, 'Error Trace:%s+([^:]+):(%d+)')
  end

  if file and line_num then
    local error_bufnr = vim.fn.bufnr(file)
    if error_bufnr then
      vim.fn.sign_define('GoTestError', { text = '❌', texthl = 'DiagnosticError' })
      vim.fn.sign_place(0, 'GoTestErrorGroup', 'GoTestError', error_bufnr, { lnum = line_num })
    end
    test_info.status = 'fail'
    test_info.fail_at_line = line_num
    terminal_test.tests_info[test_info.name] = test_info
    vim.schedule(function() terminal_test.displayer:update_tracker_buffer(terminal_test.tests_info, test_results_title) end)
    util_quickfix.add_fail_test(test_info)
    if cb_update_tracker then
      cb_update_tracker(test_info)
    end
  end
end

---@param test_info terminal.testInfo
local function process_one_line(line, test_info, float_term_state, current_time, cb_update_tracker)
  local make_notify = require('mini.notify').make_notify {}
  handle_error_trace(line, test_info, cb_update_tracker)

  if string.match(line, '--- FAIL') then
    make_notify(string.format('%s fail', test_info.name), vim.log.levels.ERROR)
    handle_test_failed(test_info, float_term_state, current_time, cb_update_tracker)
    return true
  elseif string.match(line, '--- PASS') then
    make_notify(string.format('%s pass', test_info.name), vim.log.levels.INFO)
    handle_test_passed(test_info, float_term_state, current_time, cb_update_tracker)
    return true
  end
end

---@param test_info terminal.testInfo
local function process_buffer_lines(buf, first_line, last_line, test_info, float_term_state, cb_update_tracker)
  local lines = vim.api.nvim_buf_get_lines(buf, first_line, last_line, false)
  local current_time = os.date '%H:%M:%S'

  for _, line in ipairs(lines) do
    local detach = process_one_line(line, test_info, float_term_state, current_time, cb_update_tracker)
    if detach then
      test_info.fidget_handle:finish()
      return true -- Detach requested by handler
    end
  end
end

---@param test_info terminal.testInfo
function terminal_test.test_in_terminal(test_info, cb_update_tracker)
  validate_test_info(test_info)
  terminal_test.terminals:toggle_float_terminal(test_info.name)
  local float_term_state = terminal_test.terminals:toggle_float_terminal(test_info.name)
  vim.api.nvim_chan_send(float_term_state.chan, test_info.test_command .. '\n')

  vim.api.nvim_buf_attach(float_term_state.buf, false, {
    on_lines = function(_, buf, _, first_line, last_line)
      return process_buffer_lines(buf, first_line, last_line, test_info, float_term_state, cb_update_tracker)
    end,
  })
end

function terminal_test.test_buf_in_terminals(test_command_format)
  local source_bufnr = vim.api.nvim_get_current_buf()
  local util_find_test = require 'util_find_test'
  local all_tests_in_buf = util_find_test.find_all_tests_in_buf(source_bufnr)
  terminal_test.displayer:create_window_and_buf()

  for test_name, test_line in pairs(all_tests_in_buf) do
    terminal_test.terminals:delete_terminal(test_name)
    local test_command = string.format(test_command_format, test_name)

    ---@type terminal.testInfo
    local test_info = {
      name = test_name,
      test_line = test_line,
      test_bufnr = source_bufnr,
      test_command = test_command,
      status = 'start',
      filepath = vim.fn.expand '%:p',
      set_ext_mark = false,
      fidget_handle = fidget.progress.handle.create {
        lsp_client = {
          name = test_name,
        },
      },
    }
    terminal_test.tests_info[test_name] = test_info
    terminal_test.test_in_terminal(test_info)
    vim.schedule(function() terminal_test.displayer:update_tracker_buffer(terminal_test.tests_info, test_results_title) end)
  end
end

---@param test_command_format string
function terminal_test.test_nearest_in_terminal(test_command_format)
  assert(test_command_format, 'No test command format found')
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_name, 'Not inside a test function')
  assert(test_line, 'No test line found')

  terminal_test.terminals:delete_terminal(test_name)
  terminal_test.test_in_terminal {
    name = test_name,
    test_line = test_line,
    test_bufnr = vim.api.nvim_get_current_buf(),
    test_command = string.format(test_command_format, test_name),
    status = 'start',
    filepath = vim.fn.expand '%:p',
    set_ext_mark = false,
    fidget_handle = fidget.progress.handle.create {
      lsp_client = {
        name = test_name,
      },
    },
  }
end

function terminal_test.test_tracked_in_terminal()
  local terminal_tracker = require 'terminals.track_test_terminal'
  for _, test_info in ipairs(terminal_tracker.track_test_list) do
    terminal_test.test_in_terminal(test_info)
  end
end

--- === View Teriminal ===

function terminal_test.view_enclosing_test()
  local util_find_test = require 'util_find_test'
  local test_name, _ = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  local float_terminal_state = terminal_test.terminals:toggle_float_terminal(test_name)
  assert(float_terminal_state, 'Failed to create floating terminal')

  -- Need this duplication. Otherwise, the keymap is bind to the buffer for for some reason
  local close_term = function()
    if vim.api.nvim_win_is_valid(float_terminal_state.footer_win) then
      vim.api.nvim_win_hide(float_terminal_state.footer_win)
    end
    if vim.api.nvim_win_is_valid(float_terminal_state.win) then
      vim.api.nvim_win_hide(float_terminal_state.win)
    end
  end
  vim.keymap.set('n', 'q', close_term, { buffer = float_terminal_state.buf })
end

function terminal_test.view_last_test_teriminal()
  local test_name = terminal_test.terminals.last_terminal_name
  if not test_name then
    vim.notify('No last test terminal found', vim.log.levels.WARN)
    return
  end
  terminal_test.terminals:toggle_float_terminal(test_name)
end

vim.api.nvim_create_user_command('TerminalTestToggleDisplay', function() terminal_test.displayer:toggle_display() end, {})
vim.api.nvim_create_user_command('TerminalTestLoadStuckTest', function() util_quickfix.load_non_passing_tests_to_quickfix(terminal_test.tests_info) end, {})

return terminal_test
