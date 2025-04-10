local util_quickfix = {}

local function add_direct_file_entries(test, qf_entries)
  assert(test.file, 'File not found for test: ' .. test.name)
  -- Find the file in the project
  local cmd = string.format("find . -name '%s' | head -n 1", test.file)
  local filepath = vim.fn.system(cmd):gsub('\n', '')

  if filepath ~= '' then
    table.insert(qf_entries, {
      filename = filepath,
      lnum = test.fail_at_line,
      text = string.format('%s', test.name),
    })
  end

  return qf_entries
end

-- Helper function to resolve test locations via LSP
local function resolve_test_locations(tests_to_resolve, qf_entries, on_complete)
  local resolved_count = 0
  local total_to_resolve = #tests_to_resolve

  -- If no tests to resolve, call completion callback immediately
  if total_to_resolve == 0 then
    on_complete(qf_entries)
    return
  end

  for _, test in ipairs(tests_to_resolve) do
    vim.lsp.buf_request(0, 'workspace/symbol', { query = test.name }, function(err, res)
      if err or not res or #res == 0 then
        vim.notify('No definition found for test: ' .. test.name, vim.log.levels.WARN)
      else
        local result = res[1] -- Take the first result
        local filename = vim.uri_to_fname(result.location.uri)
        local start = result.location.range.start

        table.insert(qf_entries, {
          filename = filename,
          lnum = start.line + 1,
          col = start.character + 1,
          text = string.format('%s', test.name),
        })
      end

      resolved_count = resolved_count + 1

      -- When all tests are resolved, call the completion callback
      if resolved_count == total_to_resolve then
        on_complete(qf_entries)
      end
    end)
  end
end

local function populate_quickfix_list(qf_entries)
  if #qf_entries > 0 then
    vim.fn.setqflist(qf_entries, 'a')
    vim.notify('Loaded ' .. #qf_entries .. ' failing tests to quickfix list', vim.log.levels.INFO)
  else
    vim.notify('No failing tests found', vim.log.levels.INFO)
  end
end

---@param tests_info terminal.testInfo[] | gotest.TestInfo[]
util_quickfix.load_non_passing_tests_to_quickfix = function(tests_info)
  local qf_entries = {}
  local tests_to_resolve = {}

  for _, test in pairs(tests_info) do
    if test.status == 'pass' then
      goto continue
    end

    if test.fail_at_line ~= 0 then
      qf_entries = add_direct_file_entries(test, qf_entries)
    else
      table.insert(tests_to_resolve, test)
    end
    ::continue::
  end

  resolve_test_locations(tests_to_resolve, qf_entries, populate_quickfix_list)
  return qf_entries
end

---@param test_info terminal.testInfo | gotest.TestInfo
util_quickfix.add_fail_test = function(test_info)
  local qf_entries = {}
  local tests_to_resolve = {}
  assert(test_info, 'No test info provided')
  assert(test_info.status, 'No test status provided')
  assert(test_info.name, 'No test name provided')
  assert(test_info.test_bufnr, 'No test buffer number provided')
  assert(test_info.test_line, 'No test line provided')
  if test_info.status ~= 'fail' then
    return
  end

  if test_info.fail_at_line ~= 0 then
    qf_entries = add_direct_file_entries(test_info, qf_entries)
  else
    table.insert(tests_to_resolve, test_info)
  end

  resolve_test_locations(tests_to_resolve, qf_entries, populate_quickfix_list)
  return qf_entries
end

return util_quickfix
