local M = {}

local dispatch = require('reference.dispatch')
local commands = require('reference.commands')

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
  commands.register(config)
end

return M
