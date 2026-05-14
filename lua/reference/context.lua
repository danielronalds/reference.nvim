local M = {}

local function is_valid_range(range)
  return type(range) == 'table'
    and type(range.line1) == 'number'
    and type(range.line2) == 'number'
    and range.line1 <= range.line2
end

function M.build_file_reference(path, range)
  if path == nil or path == '' then
    return ''
  end

  if not is_valid_range(range) then
    return '@' .. path
  end

  return '@' .. path .. '#L' .. range.line1 .. '-' .. range.line2
end

return M
