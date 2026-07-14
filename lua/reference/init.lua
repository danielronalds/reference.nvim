local M = {}

local commands = require('reference.commands')

local DEFAULT_CONFIG = {
  driver = 'tmux',
  wade = {
    timeout_seconds = 5,
  },
  tmux = {
    process_names = { 'claude', 'opencode', 'pi' },
    switch_to_target = true,
  },
}

function M.setup(opts)
  local config = vim.tbl_deep_extend('force', vim.deepcopy(DEFAULT_CONFIG), opts or {})
  commands.register(config)
end

return M
