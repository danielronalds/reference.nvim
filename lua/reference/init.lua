local M = {}

local dispatch = require('reference.dispatch')

local DEFAULT_CONFIG = {
  tmux = {
    process_names = { 'claude', 'opencode', 'pi' },
    switch_to_target = true,
  },
}

local config = vim.deepcopy(DEFAULT_CONFIG)

function M._send(inputs)
  dispatch.send(config, inputs)
end

function M.setup(opts)
  config = vim.tbl_deep_extend('force', vim.deepcopy(DEFAULT_CONFIG), opts or {})

  vim.api.nvim_create_user_command('ReferenceSend', function(cmd_opts)
    local path = vim.fn.fnamemodify(vim.fn.expand('%:p'), ':~:.')
    local range = nil
    if cmd_opts.range == 2 then
      range = { line1 = cmd_opts.line1, line2 = cmd_opts.line2 }
    end
    M._send({ path = path, range = range })
  end, { range = true, force = true })

  vim.api.nvim_create_user_command('ReferenceSendFirst', function(cmd_opts)
    local path = vim.fn.fnamemodify(vim.fn.expand('%:p'), ':~:.')
    local range = nil
    if cmd_opts.range == 2 then
      range = { line1 = cmd_opts.line1, line2 = cmd_opts.line2 }
    end
    M._send({ path = path, range = range, pick = 'first' })
  end, { range = true, force = true })
end

return M
