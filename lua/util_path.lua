local M = {}

---@param steps number? Number of path segments to include (nil for all)
---@return string?
function M.get_intermediate_path(filepath, steps)
  local cwd = vim.fn.getcwd()
  filepath = filepath or vim.fn.expand '%:p'
  local path_sep = package.config:sub(1, 1)

  cwd = cwd:gsub('/', path_sep):gsub('\\', path_sep)
  filepath = filepath:gsub('/', path_sep):gsub('\\', path_sep)

  if cwd:sub(-1) ~= path_sep then
    cwd = cwd .. path_sep
  end

  if filepath:sub(1, #cwd) ~= cwd then
    return nil
  end

  local relative_path = filepath:sub(#cwd + 1)
  local segments = {}

  for segment in relative_path:gmatch('[^' .. path_sep .. ']+') do
    table.insert(segments, segment)
    if steps and #segments == steps then
      break
    end
  end

  if #segments == 0 then
    return ''
  else
    local result = '.' .. path_sep
    for i, segment in ipairs(segments) do
      result = result .. segment
      if i < #segments then
        result = result .. path_sep
      end
    end
    return result
  end
end

return M
