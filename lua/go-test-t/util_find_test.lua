local M = {}

---@return  string? , number?
function M.get_enclosing_test()
    if vim.bo.filetype == "lua" then
        return require("go-test-t.util_lua").get_enclosing_test()
    end

    local beaver = require("beaver")
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row0 = cursor[1] - 1

    local ctx = beaver.enclosing_function(bufnr, row0)
    if not ctx then
        return nil, nil
    end

    if not string.match(ctx.name, "Test") then
        return nil
    end

    return ctx.name, ctx.start_row + 1
end

M.find_all_tests_in_buf = function(go_bufnr)
    local beaver = require("beaver")
    local funcs = beaver.list_functions(go_bufnr)

    local res = {}
    for _, ctx in ipairs(funcs) do
        if string.match(ctx.name, "Test") then
            res[ctx.name] = ctx.start_row + 1
        end
    end
    return res
end

return M
