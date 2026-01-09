---@class termTester
local terminal_test = {}
terminal_test.__index = terminal_test

---@param opts termTest.Options
function terminal_test.new(opts)
  assert(opts, 'No options found')
  assert(opts.pin_test_func, 'No pin test function found')
  assert(opts.go_test_prefix, 'No go test prefix found')
  assert(opts.ns_id, 'No namespace ID found')

  local self = setmetatable({}, {
    __index = function(t, key)
      if key == 'terminal_multiplexer' then
        -- Lazy load and cache the terminal multiplexer
        local multiplexer = require('terminal-multiplexer').new {}
        rawset(t, 'terminal_multiplexer', multiplexer)
        return multiplexer
      end
      -- Fall back to class methods and properties
      return terminal_test[key]
    end,
  })
  self.go_test_prefix = opts.go_test_prefix

  self.get_test_info_func = opts.get_test_info_func
  self.add_test_info_func = opts.add_test_info_func
  self.toggle_display_func = opts.toggle_display_func
  self.update_display_buffer_func = opts.update_display_buffer_func

  self.ns_id = opts.ns_id
  self.pin_test_func = opts.pin_test_func
  self.get_pinned_tests_func = opts.get_pinned_tests_func
  return self
end

function terminal_test:toggle_term_func(test_name)
  local test_info = self.terminal_multiplexer.all_terminals[test_name]
  if not test_info then
    self:retest_in_terminal_by_name(test_name)
  else
    self.terminal_multiplexer:toggle_float_terminal(test_name)
  end
end

function terminal_test:reset()
  for test_name, _ in pairs(self.terminal_multiplexer.all_terminals) do
    self.terminal_multiplexer:delete_terminal(test_name)
  end
end

---@param test_info terminal.testInfo
function terminal_test:test_in_terminal(test_info, do_not_close_terminal, delete_terminal_after)
  self:_validate_test_info(test_info)
  self:_clear_test_extmarks(test_info)
  self.terminal_multiplexer:delete_terminal(test_info.name)
  self.add_test_info_func(test_info)

  self:_auto_update_test_line(test_info)
  local float_term_state
  if do_not_close_terminal then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('G', true, false, true), 'n', false)
    float_term_state = self.terminal_multiplexer:toggle_float_terminal(test_info.name)
  else
    float_term_state = self.terminal_multiplexer:spawn(test_info.name)
  end

  vim.api.nvim_chan_send(float_term_state.chan, test_info.test_command .. '\n')

  local self_ref = self
  vim.schedule(function()
    vim.api.nvim_buf_attach(float_term_state.bufnr, false, {
      on_lines = function(_, buf, _, first_line, last_line) return self_ref:_process_buffer_lines(buf, first_line, last_line, test_info, delete_terminal_after) end,
    })
  end)
end

function terminal_test:test_nearest_in_terminal()
  local util_find_test = require 'go-test-t.util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_line, 'No test line found')
  assert(test_name, 'No test name found')

  local util_path = require 'go-test-t.util_path'
  local test_command

  if vim.bo.filetype == 'lua' then
    local rel_path = vim.fn.expand '%:.'
    local escaped_test_name = test_name:gsub('"', '\\"')
    -- Quote the FILE argument as well in case of spaces
    test_command = string.format('make test-file FILE="%s" FILTER="%s"', rel_path, escaped_test_name)
  else
    local intermediate_path = util_path.get_intermediate_path()
    test_command = string.format('%s %s -v -run %s\r\n', self.go_test_prefix, intermediate_path, test_name)
  end

  assert(test_name, 'No test name found')
  ---@type terminal.testInfo
  local test_info = {
    name = test_name,
    test_line = test_line,
    test_bufnr = vim.api.nvim_get_current_buf(),
    test_command = test_command,
    status = 'fired',
    filepath = vim.fn.expand '%:p',
    set_ext_mark = false,
    output = {},
  }

  self:test_in_terminal(test_info, true)
  return test_info
end

function terminal_test:retest_in_terminal_by_name(test_name)
  assert(test_name, 'No test name found')

  local self_ref = self
  require('go-test-t.util_lsp').action_from_test_name(test_name, function(lsp_param)
    local util_path = require 'go-test-t.util_path'
    local intermediate_path = util_path.get_intermediate_path(lsp_param.filepath)
    assert(intermediate_path, 'No intermediate path found')
    local test_command = string.format('%s %s -v -run %s\r\n', self.go_test_prefix, intermediate_path, test_name)

    ---@type terminal.testInfo
    local test_info = {
      test_line = lsp_param.test_line,
      filepath = lsp_param.filepath,
      test_bufnr = lsp_param.test_bufnr,
      name = test_name,
      test_command = test_command,
      status = 'fired',
      set_ext_mark = false,
      output = {},
    }
    self_ref:test_in_terminal(test_info, true)
  end)
end

function terminal_test:test_buf_in_terminals()
  local source_bufnr = vim.api.nvim_get_current_buf()
  local util_find_test = require 'go-test-t.util_find_test'
  local all_tests_in_buf = util_find_test.find_all_tests_in_buf(source_bufnr)
  self.toggle_display_func(true)

  for test_name, test_line in pairs(all_tests_in_buf) do
    local util_path = require 'go-test-t.util_path'
    local intermediate_path = util_path.get_intermediate_path()
    assert(intermediate_path, 'No intermediate path found')
    local test_command = string.format('%s %s -v -run %s\r\n', self.go_test_prefix, intermediate_path, test_name)

    ---@type terminal.testInfo
    local test_info = {
      name = test_name,
      test_line = test_line,
      test_bufnr = source_bufnr,
      test_command = test_command,
      status = 'fired',
      filepath = vim.fn.expand '%:p',
      set_ext_mark = false,
      output = {},
    }
    self.add_test_info_func(test_info)
    self.update_display_buffer_func(test_info)
    self:_auto_update_test_line(test_info)
    self:test_in_terminal(test_info, false, true)
  end
end

function terminal_test:toggle_last_test_terminal()
  local test_name = self.terminal_multiplexer.last_terminal_name
  if not test_name then
    vim.notify('No last test terminal found', vim.log.levels.WARN)
    return
  end
  self.terminal_multiplexer:toggle_float_terminal(test_name)
end

---@param terminal_name string
---@return number?
function terminal_test:preview_terminal(terminal_name)
  local float_terminal_state = self.terminal_multiplexer.all_terminals[terminal_name]
  if not float_terminal_state then
    vim.notify('No terminal found', vim.log.levels.WARN)
    return nil
  end
  assert(float_terminal_state.bufnr, 'No buffer found for terminal')

  local total_width = math.floor(vim.o.columns)
  local width = math.floor(total_width * 3 / 4) - 2
  local height = math.floor(vim.o.lines)
  float_terminal_state.win = vim.api.nvim_open_win(float_terminal_state.bufnr, true, {
    relative = 'editor',
    width = width,
    height = height - 3,
    row = 0,
    col = 0,
    style = 'minimal',
    border = 'rounded',
  })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('G', true, false, true), 'n', false)
  return float_terminal_state.win
end

--------------------------------------- === Private === ---------------------------------------

---@param test_info terminal.testInfo
function terminal_test:_clear_test_extmarks(test_info)
  if test_info.test_bufnr and test_info.test_line then
    local extmarks = vim.api.nvim_buf_get_extmarks(test_info.test_bufnr, self.ns_id, { test_info.test_line - 1, 0 }, { test_info.test_line - 1, -1 }, {})
    for _, extmark in ipairs(extmarks) do
      vim.api.nvim_buf_del_extmark(test_info.test_bufnr, self.ns_id, extmark[1])
    end
  end
end

---@param test_info terminal.testInfo
function terminal_test._auto_update_test_line(_, test_info)
  local augroup = vim.api.nvim_create_augroup('TestLineTracker_' .. test_info.name, { clear = true })
  local util_lsp = require 'go-test-t.util_lsp'

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup,
    buffer = test_info.test_bufnr,
    callback = function()
      util_lsp.action_from_test_name(test_info.name, function(new_info)
        if new_info.test_line ~= test_info.test_line then
          test_info.test_line = new_info.test_line
          test_info.test_bufnr = new_info.test_bufnr
          test_info.filepath = new_info.filepath
        end
      end)
    end,
  })

  return augroup
end

---@param buf number
---@param first_line number
---@param last_line number
---@param test_info terminal.testInfo
function terminal_test:_process_buffer_lines(buf, first_line, last_line, test_info, delete_terminal_after)
  local lines = vim.api.nvim_buf_get_lines(buf, first_line, last_line, false)
  local current_time = os.date '%H:%M:%S'

  for _, line in ipairs(lines) do
    local detach = self:_process_one_line(line, test_info, current_time)
    if detach then
      if test_info.status == 'pass' and delete_terminal_after then
        vim.schedule(function() self.terminal_multiplexer:delete_terminal(test_info.name) end)
      end
      return true
    end
  end
end

---@param test_info terminal.testInfo
---@param current_time string
function terminal_test:_handle_test_passed(test_info, current_time)
  if not test_info.set_ext_mark then
    self:_clear_test_extmarks(test_info)
    vim.api.nvim_buf_set_extmark(test_info.test_bufnr, self.ns_id, test_info.test_line - 1, 0, {
      virt_text = { { string.format('✅ %s', current_time) } },
      virt_text_pos = 'eol',
    })
    test_info.set_ext_mark = true
  end
  test_info.status = 'pass'
  self.add_test_info_func(test_info)
  self.update_display_buffer_func(test_info)
end

function terminal_test:_handle_test_failed(test_info, current_time)
  if not test_info.set_ext_mark then
    self:_clear_test_extmarks(test_info)
    vim.api.nvim_buf_set_extmark(test_info.test_bufnr, self.ns_id, test_info.test_line - 1, 0, {
      virt_text = { { string.format('❌ %s', current_time) } },
      virt_text_pos = 'eol',
    })
    test_info.set_ext_mark = true
  end
  test_info.status = 'fail'
  self.pin_test_func(test_info)
  require('go-test-t.util_quickfix').add_fail_test(test_info)

  self.add_test_info_func(test_info)
  self.update_display_buffer_func(test_info)
end

---@param line string
---@param test_info terminal.testInfo
function terminal_test:_handle_error_trace(line, test_info)
  local file, line_num
  if vim.fn.has 'win32' == 1 then
    file, line_num = string.match(line, 'Error Trace:%s+([%w%p]+):(%d+)')
  else
    file, line_num = string.match(line, 'Error Trace:%s+([^:]+):(%d+)')
  end

  if file and line_num then
    local error_bufnr = vim.fn.bufnr(file)
    if error_bufnr and vim.api.nvim_buf_is_valid(error_bufnr) then
      vim.fn.sign_define('GoTestError', { text = '❌', texthl = 'DiagnosticError' })
      vim.fn.sign_place(0, 'GoTestErrorGroup', 'GoTestError', error_bufnr, { lnum = line_num })
    end
    test_info.status = 'fail'
    test_info.fail_at_line = line_num
    self.pin_test_func(test_info)
    self.add_test_info_func(test_info)
    self.update_display_buffer_func(test_info)
    require('go-test-t.util_quickfix').add_fail_test(test_info)
  end
end

---@param line string
---@param test_info terminal.testInfo
---@param current_time string
function terminal_test:_process_one_line(line, test_info, current_time)
  self:_handle_error_trace(line, test_info)

  if string.match(line, '--- FAIL') or string.match(line, 'FATAL') then
    vim.notify(string.format('%s fail', test_info.name), vim.log.levels.ERROR)
    self:_handle_test_failed(test_info, current_time)
    return true
  elseif string.match(line, '--- PASS') then
    vim.notify(string.format('%s pass', test_info.name), vim.log.levels.INFO)
    self:_handle_test_passed(test_info, current_time)
    -- delete the terminal after test pass
    return true
  end
end

---@param test_info terminal.testInfo
function terminal_test._validate_test_info(_, test_info)
  assert(test_info.name, 'No test found')
  assert(test_info.test_line, 'No test line found')
  assert(test_info.test_command, 'No test command found')
  assert(test_info.test_bufnr, 'No test buffer found')
  assert(vim.api.nvim_buf_is_valid(test_info.test_bufnr), 'Invalid buffer')
end

return terminal_test
