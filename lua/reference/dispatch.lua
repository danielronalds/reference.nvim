local M = {}

local context = require('reference.context')
local bridge = require('reference.bridge')
local errors = require('reference.errors')
local ui = require('reference.ui')

local REASON_TOASTS = {
  [errors.NOT_IN_TMUX]     = 'Not in a tmux session',
  [errors.NO_AGENTS_FOUND] = 'No agent was found',
}

local function send_and_focus(config, agent, reference)
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

function M.send(config, inputs)
  inputs = inputs or {}
  local reference = context.build_file_reference(inputs.path, inputs.range)
  if reference == '' then
    vim.notify('No file reference to send', vim.log.levels.WARN)
    return
  end

  local agents, reason = bridge.discover_agents({ process_names = config.tmux.process_names })

  local toast = REASON_TOASTS[reason]
  if toast then
    vim.notify(toast, vim.log.levels.ERROR)
    return
  end

  if #agents == 1 then
    send_and_focus(config, agents[1], reference)
    return
  end

  if inputs.pick == 'first' then
    send_and_focus(config, agents[1], reference)
    return
  end

  ui.pick_agent(agents, function(agent)
    if not agent then
      return
    end
    send_and_focus(config, agent, reference)
  end)
end

return M
