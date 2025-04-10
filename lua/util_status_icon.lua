local M = {}

---@param status string
function M.get_status_icon(status)
  assert(status, 'Empty status provided')
  if status == 'pass' then
    return '✅'
  elseif status == 'fail' then
    return '❌'
  elseif status == 'cont' then
    return '🔥'
  elseif status == 'start' then
    return '🚀'
  elseif status == 'not run' then
    return '⏺️'
  elseif status == 'tracked' then
    return '🏁'
  else
    vim.notify('Unknown status: ' .. status, vim.log.levels.WARN)
    return '❓'
  end
end

return M
