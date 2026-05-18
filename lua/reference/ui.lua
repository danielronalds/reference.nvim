local M = {}

function M.format_agent(agent)
  local name = agent.matched_name or agent.command or '?'
  local address = string.format(
    '%s:%s.%s',
    agent.session or '?',
    tostring(agent.window_index or '?'),
    tostring(agent.pane_index or '?')
  )
  return string.format('%s  %s (%s)', name, address, agent.window or '?')
end

function M.pick_agent(agents, on_choice)
  vim.ui.select(agents, {
    prompt = 'Send reference to:',
    format_item = M.format_agent,
  }, function(agent)
    on_choice(agent)
  end)
end

return M
