local M = {}

local DEFAULT_PROCESS_NAMES = { 'claude', 'opencode', 'pi' }

local in_tmux_session, list_panes, direct_match, node_wrapped_match

function M.copy(text)
  if text == nil or text == '' then
    vim.notify('Nothing to copy', vim.log.levels.WARN)
    return
  end

  vim.fn.setreg('+', text)
end

function M.send(pane_id, text)
  if pane_id == nil or pane_id == '' then
    vim.notify('No tmux pane to send to', vim.log.levels.WARN)
    return 'no pane'
  end

  if text == nil or text == '' then
    vim.notify('Nothing to send', vim.log.levels.WARN)
    return 'no text'
  end

  local result = vim.system({ 'tmux', 'send-keys', '-t', pane_id, '-l', text }):wait()
  if result.code ~= 0 then
    return 'tmux send-keys failed: ' .. tostring(result.stderr or '')
  end

  return nil
end

function M.focus(pane_id)
  if pane_id == nil or pane_id == '' then
    vim.notify('No tmux pane to focus', vim.log.levels.WARN)
    return 'no pane'
  end

  local select_window = vim.system({ 'tmux', 'select-window', '-t', pane_id }):wait()
  if select_window.code ~= 0 then
    return 'tmux select-window failed: ' .. tostring(select_window.stderr or '')
  end

  local select_pane = vim.system({ 'tmux', 'select-pane', '-t', pane_id }):wait()
  if select_pane.code ~= 0 then
    return 'tmux select-pane failed: ' .. tostring(select_pane.stderr or '')
  end

  return nil
end

function M.discover_agents(opts)
  opts = opts or {}
  local process_names = opts.process_names or DEFAULT_PROCESS_NAMES

  if not in_tmux_session() then
    return {}, 'not in tmux'
  end

  local agents = {}
  for _, pane in ipairs(list_panes()) do
    local matched_name = direct_match(pane.command, process_names)
    if not matched_name and pane.command == 'node' then
      matched_name = node_wrapped_match(pane.pane_pid, process_names)
    end

    if matched_name then
      table.insert(agents, {
        pane_id = pane.pane_id,
        pane_pid = pane.pane_pid,
        session = pane.session,
        window = pane.window,
        command = pane.command,
        matched_name = matched_name,
      })
    end
  end

  if #agents == 0 then
    return {}, 'no agents found'
  end

  return agents, nil
end

local function run(argv)
  return vim.system(argv):wait()
end

function in_tmux_session()
  local result = run({ 'tmux', 'display-message', '-p', '#{session_name}' })
  return result.code == 0
end

function list_panes()
  local result = run({
    'tmux',
    'list-panes',
    '-s',
    '-F',
    '#{pane_id}\t#{pane_pid}\t#{session_name}\t#{window_name}\t#{pane_current_command}',
  })
  if result.code ~= 0 then
    return {}
  end

  local rows = {}
  for line in tostring(result.stdout or ''):gmatch('[^\n]+') do
    local pane_id, pane_pid, session, window, command =
      line:match('^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$')
    if pane_id then
      table.insert(rows, {
        pane_id = pane_id,
        pane_pid = tonumber(pane_pid),
        session = session,
        window = window,
        command = command,
      })
    end
  end
  return rows
end

function direct_match(command, process_names)
  for _, name in ipairs(process_names) do
    if command == name then
      return name
    end
  end
  return nil
end

local function child_pids(parent_pid)
  local result = run({ 'pgrep', '-P', tostring(parent_pid) })
  if result.code ~= 0 then
    return {}
  end

  local pids = {}
  for pid in tostring(result.stdout or ''):gmatch('%d+') do
    table.insert(pids, pid)
  end
  return pids
end

local function args_match(child_pid, process_names)
  local result = run({ 'ps', '-p', tostring(child_pid), '-o', 'args=' })
  if result.code ~= 0 then
    return nil
  end

  local args = tostring(result.stdout or '')
  for _, name in ipairs(process_names) do
    if args:find(name, 1, true) then
      return name
    end
  end
  return nil
end

function node_wrapped_match(pane_pid, process_names)
  for _, child_pid in ipairs(child_pids(pane_pid)) do
    local matched = args_match(child_pid, process_names)
    if matched then
      return matched
    end
  end
  return nil
end

return M
