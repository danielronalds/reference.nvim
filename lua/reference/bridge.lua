local M = {}

function M.copy(text)
  if text == nil or text == '' then
    vim.notify('Nothing to copy', vim.log.levels.WARN)
    return
  end

  vim.fn.setreg('+', text)
end

return M
