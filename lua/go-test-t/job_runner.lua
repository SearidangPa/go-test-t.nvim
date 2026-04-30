---@class termTester
local job_runner = {}
job_runner.__index = job_runner

local util_quickfix_cache

local function get_util_quickfix()
    util_quickfix_cache = util_quickfix_cache
        or require("go-test-t.util_quickfix")
    return util_quickfix_cache
end

local function regex_escape(value)
    return (value:gsub("([^%w_])", "\\%1"))
end

local function prefix_to_args(prefix)
    local raw_args = vim.split(vim.trim(prefix), "%s+", { trimempty = true })
    local args = {}
    local env = {}
    local has_env = false

    for _, arg in ipairs(raw_args) do
        local key, value = arg:match("^([%a_][%w_]*)=(.*)$")
        if key and #args == 0 then
            env[key] = value
            has_env = true
        else
            table.insert(args, arg)
        end
    end

    return args, has_env and env or nil
end

local function command_to_string(args)
    return table.concat(args, " ")
end

local function format_value(value)
    if type(value) == "table" then
        local ok, encoded = pcall(vim.json.encode, value)
        if ok then
            return encoded
        end
        return vim.inspect(value)
    end
    return tostring(value)
end

local function format_logrus_line(entry)
    local time = entry.time and tostring(entry.time) or ""
    local msg = entry.msg or entry.message or ""
    msg = tostring(msg)

    local fields = {}
    for key, value in pairs(entry) do
        if key ~= "time" and key ~= "msg" and key ~= "message" then
            table.insert(
                fields,
                string.format("%s=%s", key, format_value(value))
            )
        end
    end
    table.sort(fields)

    local line = ""
    if time ~= "" then
        line = time .. ": "
    end
    line = line .. msg
    if #fields > 0 then
        line = line .. ", " .. table.concat(fields, ", ")
    end
    return line
end

local function format_output_line(output)
    local line = vim.trim((output or ""):gsub("\r", ""))
    if line == "" then
        return nil
    end

    local ok, decoded = pcall(vim.json.decode, line)
    if ok and type(decoded) == "table" and (decoded.msg or decoded.message) then
        return format_logrus_line(decoded)
    end

    local json_start = line:find("{", 1, true)
    if json_start then
        ok, decoded = pcall(vim.json.decode, line:sub(json_start))
        if
            ok
            and type(decoded) == "table"
            and (decoded.msg or decoded.message)
        then
            return format_logrus_line(decoded)
        end
    end

    return line
end

---@param opts termTest.Options
function job_runner.new(opts)
    assert(opts, "No options found")
    assert(opts.pin_test_func, "No pin test function found")
    assert(opts.go_test_prefix, "No go test prefix found")
    assert(opts.ns_id, "No namespace ID found")

    local self = setmetatable({}, job_runner)
    self.go_test_prefix = opts.go_test_prefix
    self.get_test_info_func = opts.get_test_info_func
    self.add_test_info_func = opts.add_test_info_func
    self.toggle_display_func = opts.toggle_display_func
    self.update_display_buffer_func = opts.update_display_buffer_func
    self.ns_id = opts.ns_id
    self.pin_test_func = opts.pin_test_func
    self.get_pinned_tests_func = opts.get_pinned_tests_func

    self.last_test_name = nil
    self.running_jobs = {}
    self.test_jobs = {}
    self.output_buffers = {}
    return self
end

function job_runner:_build_go_test_args(pkg, run_pattern)
    local args, env = prefix_to_args(self.go_test_prefix)
    vim.list_extend(args, { pkg, "-v", "-json" })
    if run_pattern and run_pattern ~= "" then
        vim.list_extend(args, { "-run", run_pattern })
    end
    return args, env
end

function job_runner:_ensure_output_buffer(test_info)
    if
        test_info.output_bufnr
        and vim.api.nvim_buf_is_valid(test_info.output_bufnr)
    then
        vim.bo[test_info.output_bufnr].filetype = "test"
        return test_info.output_bufnr
    end

    local bufnr = self.output_buffers[test_info.name]
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        bufnr = vim.api.nvim_create_buf(false, true)
        vim.bo[bufnr].buftype = "nofile"
        vim.bo[bufnr].bufhidden = "hide"
        vim.bo[bufnr].swapfile = false
        vim.bo[bufnr].filetype = "test"
        pcall(vim.api.nvim_buf_set_name, bufnr, "go-test://" .. test_info.name)
        self.output_buffers[test_info.name] = bufnr
    end

    test_info.output_bufnr = bufnr
    return bufnr
end

function job_runner:_replace_output_buffer(test_info, lines)
    local bufnr = self:_ensure_output_buffer(test_info)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or {})
    vim.bo[bufnr].modifiable = false
end

function job_runner:_append_output(test_info, line)
    if not line or line == "" then
        return
    end

    test_info.output = test_info.output or {}
    table.insert(test_info.output, line)

    local bufnr = self:_ensure_output_buffer(test_info)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { line })
    vim.bo[bufnr].modifiable = false

    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        if vim.api.nvim_win_is_valid(win) then
            local line_count = vim.api.nvim_buf_line_count(bufnr)
            pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })
        end
    end
end

function job_runner:_clear_test_extmarks(test_info)
    if test_info.test_bufnr and test_info.test_line then
        local extmarks = vim.api.nvim_buf_get_extmarks(
            test_info.test_bufnr,
            self.ns_id,
            { test_info.test_line - 1, 0 },
            { test_info.test_line - 1, -1 },
            {}
        )
        for _, extmark in ipairs(extmarks) do
            vim.api.nvim_buf_del_extmark(
                test_info.test_bufnr,
                self.ns_id,
                extmark[1]
            )
        end
    end
end

function job_runner:_mark_source(test_info, status)
    if not (test_info.test_bufnr and test_info.test_line) then
        return
    end
    if not vim.api.nvim_buf_is_valid(test_info.test_bufnr) then
        return
    end

    self:_clear_test_extmarks(test_info)
    local icon
    if status == "fail" then
        icon = "❌"
    elseif status == "skip" then
        icon = "⏭️"
    else
        icon = "✅"
    end

    vim.api.nvim_buf_set_extmark(
        test_info.test_bufnr,
        self.ns_id,
        test_info.test_line - 1,
        0,
        {
            virt_text = {
                { string.format("%s %s", icon, os.date("%H:%M:%S")) },
            },
            virt_text_pos = "eol",
        }
    )
end

function job_runner._auto_update_test_line(_, test_info)
    if not test_info.test_bufnr then
        return nil
    end

    local group_name = "TestLineTracker_" .. test_info.name:gsub("[^%w_]", "_")
    local augroup = vim.api.nvim_create_augroup(group_name, { clear = true })
    local util_lsp = require("go-test-t.util_lsp")

    vim.api.nvim_create_autocmd("BufWritePost", {
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

function job_runner:_handle_error_trace(line, test_info)
    local file, line_num
    if vim.fn.has("win32") == 1 then
        file, line_num = string.match(line, "Error Trace:%s+([%w%p]+):(%d+)")
    else
        file, line_num = string.match(line, "Error Trace:%s+([^:]+):(%d+)")
    end

    if not (file and line_num) then
        return
    end

    test_info.status = "fail"
    test_info.filepath = file
    test_info.fail_at_line = tonumber(line_num) or 0
    self.pin_test_func(test_info)
    self.add_test_info_func(test_info)
    get_util_quickfix().add_fail_test(test_info)
end

function job_runner:_new_test_info(name, command, opts)
    opts = opts or {}
    local existing = self.get_test_info_func and self.get_test_info_func(name)
        or nil
    local test_info = existing or {}
    test_info.name = name
    test_info.status = opts.status or test_info.status or "running"
    test_info.filepath = opts.filepath or test_info.filepath or ""
    test_info.test_line = opts.test_line or test_info.test_line
    test_info.test_bufnr = opts.test_bufnr or test_info.test_bufnr
    test_info.test_command = command
    test_info.set_ext_mark = false
    test_info.fail_at_line = opts.fail_at_line or 0
    test_info.output = opts.keep_output and test_info.output or {}
    self:_ensure_output_buffer(test_info)
    self:_replace_output_buffer(test_info, test_info.output)
    return test_info
end

function job_runner:_register_initial_test(name, command, opts)
    local test_info = self:_new_test_info(name, command, opts)
    self.add_test_info_func(test_info)
    if test_info.test_bufnr then
        self:_auto_update_test_line(test_info)
    end
    return test_info
end

function job_runner:_handle_run(entry, command)
    if not entry.Test then
        return
    end

    local test_info = self.get_test_info_func(entry.Test)
    if not test_info then
        test_info =
            self:_new_test_info(entry.Test, command, { status = "running" })
    end

    test_info.status = "running"
    test_info.test_command = command
    self.add_test_info_func(test_info)
    self.last_test_name = entry.Test
    self.update_display_buffer_func()
end

function job_runner:_handle_output(entry)
    if not entry.Test then
        return
    end

    local test_info = self.get_test_info_func(entry.Test)
    if not test_info then
        return
    end

    local line = format_output_line(entry.Output)
    if not line then
        return
    end

    self:_append_output(test_info, line)
    self:_handle_error_trace(line, test_info)
    self.add_test_info_func(test_info)
    self.update_display_buffer_func()
end

function job_runner:_handle_outcome(entry)
    if not entry.Test then
        return
    end

    local test_info = self.get_test_info_func(entry.Test)
    if not test_info then
        return
    end

    test_info.status = entry.Action
    self:_append_output(
        test_info,
        string.format("--- %s: %s", entry.Action:upper(), entry.Test)
    )

    if entry.Action == "fail" then
        self.pin_test_func(test_info)
        get_util_quickfix().add_fail_test(test_info)
        self:_mark_source(test_info, "fail")
    elseif entry.Action == "pass" or entry.Action == "skip" then
        self:_mark_source(test_info, entry.Action)
    end

    self.add_test_info_func(test_info)
    self.update_display_buffer_func()
end

function job_runner:_handle_json_line(line, command)
    if not line or line == "" then
        return
    end

    local ok, decoded = pcall(vim.json.decode, line)
    if not ok or type(decoded) ~= "table" then
        return
    end

    if decoded.Action == "run" then
        self:_handle_run(decoded, command)
    elseif decoded.Action == "output" then
        self:_handle_output(decoded)
    elseif
        decoded.Action == "pass"
        or decoded.Action == "fail"
        or decoded.Action == "skip"
    then
        self:_handle_outcome(decoded)
    elseif decoded.Action == "pause" or decoded.Action == "cont" then
        self:_handle_outcome(decoded)
    end
end

function job_runner:_consume_job_data(job_state, data)
    if not data or #data == 0 then
        return
    end

    data[1] = (job_state.pending or "") .. data[1]
    job_state.pending = data[#data]

    for i = 1, #data - 1 do
        self:_handle_json_line(data[i], job_state.command)
    end
end

function job_runner:_stop_test_job(test_name)
    local job_id = self.test_jobs[test_name]
    if job_id and self.running_jobs[job_id] then
        vim.fn.jobstop(job_id)
    end
end

function job_runner:_start_job(args, test_names, env)
    local command = command_to_string(args)
    local job_state = {
        command = command,
        pending = "",
        test_names = test_names or {},
    }

    local job_id
    job_id = vim.fn.jobstart(args, {
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = function(_, data)
            self:_consume_job_data(job_state, data)
        end,
        on_stderr = function(_, data)
            for _, line in ipairs(data or {}) do
                if line ~= "" then
                    vim.notify("go test stderr: " .. line, vim.log.levels.WARN)
                end
            end
        end,
        env = env,
        on_exit = function(_, exit_code)
            if job_state.pending and job_state.pending ~= "" then
                self:_handle_json_line(job_state.pending, job_state.command)
            end
            self.running_jobs[job_id] = nil
            for _, name in ipairs(job_state.test_names) do
                if self.test_jobs[name] == job_id then
                    self.test_jobs[name] = nil
                end
            end
            if exit_code ~= 0 then
                self.update_display_buffer_func()
            end
        end,
    })

    if job_id <= 0 then
        vim.notify(
            "Failed to start go test job: " .. command,
            vim.log.levels.ERROR
        )
        return nil
    end

    self.running_jobs[job_id] = job_state
    for _, name in ipairs(test_names or {}) do
        self.test_jobs[name] = job_id
    end
    return job_id
end

function job_runner:_run_tests(pkg, test_names, metadata_by_name)
    metadata_by_name = metadata_by_name or {}
    local run_pattern
    if #test_names == 1 then
        run_pattern = "^" .. regex_escape(test_names[1]) .. "$"
    elseif #test_names > 1 then
        local escaped = {}
        for _, name in ipairs(test_names) do
            table.insert(escaped, regex_escape(name))
        end
        run_pattern = "^(" .. table.concat(escaped, "|") .. ")$"
    end

    local args, env = self:_build_go_test_args(pkg, run_pattern)
    local command = command_to_string(args)

    for _, name in ipairs(test_names) do
        self:_stop_test_job(name)
        local opts = metadata_by_name[name] or {}
        opts.status = "fired"
        self:_register_initial_test(name, command, opts)
    end

    self.last_test_name = test_names[#test_names] or self.last_test_name
    self.update_display_buffer_func()
    return self:_start_job(args, test_names, env)
end

function job_runner:test_pkg(test_pkg)
    test_pkg = test_pkg or "./..."
    local args, env = self:_build_go_test_args(test_pkg)
    return self:_start_job(args, {}, env)
end

function job_runner:test_nearest_in_terminal()
    local util_find_test = require("go-test-t.util_find_test")
    local test_name, test_line = util_find_test.get_enclosing_test()
    assert(test_line, "No test line found")
    assert(test_name, "No test name found")

    if vim.bo.filetype == "lua" then
        vim.notify(
            "Lua test runner still requires the old terminal path",
            vim.log.levels.WARN
        )
        return self.get_test_info_func(test_name)
    end

    local util_path = require("go-test-t.util_path")
    local pkg = util_path.get_intermediate_path()
    assert(pkg, "No intermediate path found")

    local metadata = {}
    metadata[test_name] = {
        test_line = test_line,
        test_bufnr = vim.api.nvim_get_current_buf(),
        filepath = vim.fn.expand("%:p"),
    }
    self:_run_tests(pkg, { test_name }, metadata)
    return self.get_test_info_func(test_name)
end

function job_runner:retest_in_terminal_by_name(test_name)
    assert(test_name, "No test name found")

    require("go-test-t.util_lsp").action_from_test_name(
        test_name,
        function(lsp_param)
            local util_path = require("go-test-t.util_path")
            local pkg = util_path.get_intermediate_path(lsp_param.filepath)
            assert(pkg, "No intermediate path found")

            local metadata = {}
            metadata[test_name] = {
                test_line = lsp_param.test_line,
                filepath = lsp_param.filepath,
                test_bufnr = lsp_param.test_bufnr,
            }
            self:_run_tests(pkg, { test_name }, metadata)
        end
    )
end

function job_runner:test_buf_in_terminals()
    local source_bufnr = vim.api.nvim_get_current_buf()
    local util_find_test = require("go-test-t.util_find_test")
    local tests_by_name = util_find_test.find_all_tests_in_buf(source_bufnr)
    local test_names = {}
    local metadata = {}

    for test_name, test_line in pairs(tests_by_name) do
        table.insert(test_names, test_name)
        metadata[test_name] = {
            test_line = test_line,
            test_bufnr = source_bufnr,
            filepath = vim.fn.expand("%:p"),
        }
    end
    table.sort(test_names)

    if #test_names == 0 then
        vim.notify("No tests found in buffer", vim.log.levels.WARN)
        return
    end

    local util_path = require("go-test-t.util_path")
    local pkg = util_path.get_intermediate_path()
    assert(pkg, "No intermediate path found")

    self.toggle_display_func(true)
    self:_run_tests(pkg, test_names, metadata)
end

function job_runner:preview_terminal(test_name)
    local test_info = self.get_test_info_func(test_name)
    if not test_info then
        vim.notify("No test output found", vim.log.levels.WARN)
        return nil
    end

    local bufnr = self:_ensure_output_buffer(test_info)
    vim.bo[bufnr].filetype = "test"

    local total_width = math.floor(vim.o.columns)
    local width = math.floor(total_width * 3 / 4) - 2
    local height = math.floor(vim.o.lines)
    local win = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        width = width,
        height = height - 3,
        row = 0,
        col = 0,
        style = "minimal",
        border = "rounded",
    })

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    pcall(vim.api.nvim_win_set_cursor, win, { line_count, 0 })
    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = bufnr, noremap = true, silent = true })

    return win
end

function job_runner:toggle_last_test_terminal()
    if not self.last_test_name then
        vim.notify("No last test output found", vim.log.levels.WARN)
        return
    end
    self:preview_terminal(self.last_test_name)
end

function job_runner:toggle_term_func(test_name)
    self:preview_terminal(test_name)
end

function job_runner:reset()
    for job_id, _ in pairs(self.running_jobs) do
        vim.fn.jobstop(job_id)
    end
    self.running_jobs = {}
    self.test_jobs = {}
    self.last_test_name = nil

    for name, bufnr in pairs(self.output_buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
        self.output_buffers[name] = nil
    end
end

return job_runner
