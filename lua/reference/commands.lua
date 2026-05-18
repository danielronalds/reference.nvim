local M = {}

local dispatch = require('reference.dispatch')

local make_callback

function M.register(config)
  vim.api.nvim_create_user_command(
    'ReferenceSend',
    make_callback(config, nil),
    { range = true, force = true }
  )

  vim.api.nvim_create_user_command(
    'ReferenceSendFirst',
    make_callback(config, 'first'),
    { range = true, force = true }
  )
end

function make_callback(config, pick)
  return function(cmd_opts)
    local path = vim.fn.fnamemodify(vim.fn.expand('%:p'), ':~:.')
    local range = nil
    if cmd_opts.range == 2 then
      range = { line1 = cmd_opts.line1, line2 = cmd_opts.line2 }
    end
    dispatch.send(config, { path = path, range = range, pick = pick })
  end
end

return M
