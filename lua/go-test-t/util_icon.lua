local M = {}

---@param status string
function M.get_status_icon(status)
    assert(status, "Empty status provided")
    if status == "pass" or status == "skip" then
        return "✅"
    elseif status == "fail" then
        return "❌"
    elseif status == "cont" then
        return "🔄"
    elseif status == "start" then
        return "🚀"
    elseif status == "pause" then
        return "🛑"
    elseif status == "running" then
        return "🔄"
    elseif status == "fired" then
        return "🔥"
    else
        vim.notify("Unknown status: " .. status, vim.log.levels.WARN)
        return "❓"
    end
end

return M
