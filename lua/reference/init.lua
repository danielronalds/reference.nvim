local M = {}

local context = require('reference.context')
local bridge = require('reference.bridge')

local DEFAULT_CONFIG = {
  tmux = {
    process_names = { 'claude', 'opencode', 'pi' },
    switch_to_target = true,
  },
}

local config = vim.deepcopy(DEFAULT_CONFIG)

local function format_agent(agent)
  local name = agent.matched_name or agent.command or '?'
  return string.format('%s (%s:%s)', name, agent.session or '?', agent.window or '?')
end

local function send_and_focus(agent, reference)
  local send_reason = bridge.send(agent.pane_id, reference)
  if send_reason then
    vim.notify('Failed to send reference: ' .. send_reason, vim.log.levels.WARN)
    return
  end

  if config.tmux.switch_to_target then
    local focus_reason = bridge.focus(agent.pane_id)
    if focus_reason then
      vim.notify('Failed to focus tmux pane: ' .. focus_reason, vim.log.levels.WARN)
    end
  end
end

function M._send(inputs)
  inputs = inputs or {}
  local reference = context.build_file_reference(inputs.path, inputs.range)
  if reference == '' then
    vim.notify('No file reference to send', vim.log.levels.WARN)
    return
  end

  local agents, reason = bridge.discover_agents({ process_names = config.tmux.process_names })

  if reason then
    bridge.copy(reference)
    vim.notify('Copied reference to clipboard (' .. reason .. ')', vim.log.levels.INFO)
    return
  end

  if #agents == 1 then
    send_and_focus(agents[1], reference)
    return
  end

  vim.ui.select(agents, {
    prompt = 'Send reference to:',
    format_item = format_agent,
  }, function(agent)
    if not agent then
      return
    end
    send_and_focus(agent, reference)
  end)
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
end

return M
