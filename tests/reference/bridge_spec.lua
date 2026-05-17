local stub = require('luassert.stub')

describe('reference.bridge.copy', function()
  local setreg_stub
  local notify_stub

  before_each(function()
    setreg_stub = stub(vim.fn, 'setreg')
    notify_stub = stub(vim, 'notify')
  end)

  after_each(function()
    setreg_stub:revert()
    notify_stub:revert()
  end)

  describe('with valid input', function()
    it('writes the given text to the + register and emits no notification', function()
      local bridge = require('reference.bridge')
      local text = '@lua/foo.lua#L5-12'

      bridge.copy(text)

      assert.stub(setreg_stub).was.called(1)
      assert.stub(setreg_stub).was.called_with('+', text)
      assert.stub(notify_stub).was_not.called()
    end)
  end)

  describe('with empty input', function()
    local cases = {
      { name = 'skips the register write and warns when text is nil', text = nil },
      { name = 'skips the register write and warns when text is empty', text = '' },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local bridge = require('reference.bridge')

        bridge.copy(case.text)

        assert.stub(setreg_stub).was_not.called()
        assert.stub(notify_stub).was.called(1)
        assert.stub(notify_stub).was.called_with('Nothing to copy', vim.log.levels.WARN)
      end)
    end
  end)
end)

local function fake_handle(result)
  return { wait = function() return result end }
end

local function make_system_stub(routes)
  return function(argv)
    local key
    if argv[1] == 'tmux' and argv[2] == 'display-message' then
      key = 'display_message'
    elseif argv[1] == 'tmux' and argv[2] == 'list-panes' then
      key = 'list_panes'
    elseif argv[1] == 'pgrep' then
      key = 'pgrep:' .. tostring(argv[3])
    elseif argv[1] == 'ps' then
      key = 'ps:' .. tostring(argv[3])
    end

    local route = routes[key]
    if route == nil then
      error('unexpected vim.system call: ' .. vim.inspect(argv))
    end

    return fake_handle(route)
  end
end

local function rows_from(records)
  local lines = {}
  for _, r in ipairs(records) do
    table.insert(lines, table.concat({
      r.pane_id,
      tostring(r.pane_pid),
      r.session,
      tostring(r.window_index or 0),
      tostring(r.pane_index or 0),
      r.window,
      r.command,
    }, '\t'))
  end
  return table.concat(lines, '\n') .. '\n'
end

describe('reference.bridge.discover_agents', function()
  local system_stub

  before_each(function()
    system_stub = stub(vim, 'system')
  end)

  after_each(function()
    system_stub:revert()
  end)

  describe('when not in a tmux session', function()
    it("returns an empty list and reason 'not in tmux' when the session probe fails", function()
      local bridge = require('reference.bridge')
      system_stub.invokes(make_system_stub({
        display_message = { stdout = '', stderr = 'no server running\n', code = 1 },
      }))

      local agents, reason = bridge.discover_agents()

      assert.are.same({}, agents)
      assert.are.equal('not in tmux', reason)
    end)
  end)

  describe('when inside tmux with no matching panes', function()
    it("returns an empty list and reason 'no agents found' when list-panes rows do not match", function()
      local bridge = require('reference.bridge')
      local rows = rows_from({
        { pane_id = '%0', pane_pid = 100, session = 'work', window = 'editor', command = 'zsh' },
        { pane_id = '%1', pane_pid = 101, session = 'work', window = 'logs',   command = 'vim' },
      })
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = { stdout = rows, code = 0 },
      }))

      local agents, reason = bridge.discover_agents()

      assert.are.same({}, agents)
      assert.are.equal('no agents found', reason)
    end)
  end)

  describe('tmux invocation', function()
    it("uses 'tmux list-panes -s' for current-session scope, never '-a'", function()
      local bridge = require('reference.bridge')
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = {
          stdout = rows_from({
            { pane_id = '%0', pane_pid = 100, session = 'work', window = 'editor', command = 'claude' },
          }),
          code = 0,
        },
      }))

      bridge.discover_agents()

      local list_panes_argv = nil
      for _, call in ipairs(system_stub.calls) do
        local argv = call.vals[1]
        if argv[1] == 'tmux' and argv[2] == 'list-panes' then
          list_panes_argv = argv
          break
        end
      end

      assert.is_not_nil(list_panes_argv)
      local saw_s, saw_a = false, false
      for _, arg in ipairs(list_panes_argv) do
        if arg == '-s' then saw_s = true end
        if arg == '-a' then saw_a = true end
      end
      assert.is_true(saw_s)
      assert.is_false(saw_a)
    end)
  end)

  describe('direct command matches', function()
    it('returns a single entry when one pane command matches a configured name directly', function()
      local bridge = require('reference.bridge')
      local rows = rows_from({
        { pane_id = '%0', pane_pid = 100, session = 'work', window = 'editor', command = 'zsh' },
        { pane_id = '%1', pane_pid = 101, session = 'work', window = 'agent',  command = 'claude' },
        { pane_id = '%2', pane_pid = 102, session = 'work', window = 'logs',   command = 'vim' },
      })
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = { stdout = rows, code = 0 },
      }))

      local agents, reason = bridge.discover_agents()

      assert.is_nil(reason)
      assert.are.equal(1, #agents)
      assert.are.equal('%1', agents[1].pane_id)
    end)

    it('populates pane_id, pane_pid, session, window_index, pane_index, window, command, and matched_name on each entry', function()
      local bridge = require('reference.bridge')
      local rows = rows_from({
        { pane_id = '%42', pane_pid = 12345, session = 'work', window_index = 2, pane_index = 1, window = 'editor', command = 'claude' },
      })
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = { stdout = rows, code = 0 },
      }))

      local agents = bridge.discover_agents()

      assert.are.equal(1, #agents)
      assert.are.equal('%42', agents[1].pane_id)
      assert.are.equal(12345, agents[1].pane_pid)
      assert.are.equal('work', agents[1].session)
      assert.are.equal(2, agents[1].window_index)
      assert.are.equal(1, agents[1].pane_index)
      assert.are.equal('editor', agents[1].window)
      assert.are.equal('claude', agents[1].command)
      assert.are.equal('claude', agents[1].matched_name)
    end)

    it('returns multiple entries when multiple panes match, preserving the tmux row order', function()
      local bridge = require('reference.bridge')
      local rows = rows_from({
        { pane_id = '%0', pane_pid = 100, session = 'work', window = 'editor', command = 'opencode' },
        { pane_id = '%1', pane_pid = 101, session = 'work', window = 'shell',  command = 'zsh' },
        { pane_id = '%2', pane_pid = 102, session = 'work', window = 'agent',  command = 'claude' },
        { pane_id = '%3', pane_pid = 103, session = 'work', window = 'chat',   command = 'pi' },
      })
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = { stdout = rows, code = 0 },
      }))

      local agents, reason = bridge.discover_agents()

      assert.is_nil(reason)
      assert.are.equal(3, #agents)
      assert.are.equal('%0', agents[1].pane_id)
      assert.are.equal('opencode', agents[1].matched_name)
      assert.are.equal('%2', agents[2].pane_id)
      assert.are.equal('claude', agents[2].matched_name)
      assert.are.equal('%3', agents[3].pane_id)
      assert.are.equal('pi', agents[3].matched_name)
    end)

    it('does not walk children when the surface command already matched directly', function()
      local bridge = require('reference.bridge')
      local rows = rows_from({
        { pane_id = '%0', pane_pid = 100, session = 'work', window = 'agent', command = 'claude' },
      })
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = { stdout = rows, code = 0 },
      }))

      bridge.discover_agents()

      for _, call in ipairs(system_stub.calls) do
        local argv = call.vals[1]
        assert.are_not.equal('pgrep', argv[1])
        assert.are_not.equal('ps', argv[1])
      end
    end)
  end)

  describe('node-wrapped agents', function()
    it("sets matched_name to the configured name even when command is 'node'", function()
      local bridge = require('reference.bridge')
      local rows = rows_from({
        { pane_id = '%5', pane_pid = 555, session = 'work', window = 'editor', command = 'node' },
      })
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = { stdout = rows, code = 0 },
        ['pgrep:555'] = { stdout = '600\n', code = 0 },
        ['ps:600'] = { stdout = 'node /usr/local/bin/claude --help\n', code = 0 },
      }))

      local agents = bridge.discover_agents()

      assert.are.equal(1, #agents)
      assert.are.equal('node', agents[1].command)
      assert.are.equal('claude', agents[1].matched_name)
    end)

    it('detects an agent wrapped in node by walking children via pgrep -P and ps -p <child> -o args=', function()
      local bridge = require('reference.bridge')
      local rows = rows_from({
        { pane_id = '%9', pane_pid = 900, session = 'work', window = 'agent', command = 'node' },
      })
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = { stdout = rows, code = 0 },
        ['pgrep:900'] = { stdout = '901\n902\n', code = 0 },
        ['ps:901'] = { stdout = '/usr/bin/some-unrelated-thing\n', code = 0 },
        ['ps:902'] = { stdout = 'node /usr/local/bin/opencode\n', code = 0 },
      }))

      local agents, reason = bridge.discover_agents()

      assert.is_nil(reason)
      assert.are.equal(1, #agents)
      assert.are.equal('%9', agents[1].pane_id)
      assert.are.equal('node', agents[1].command)
      assert.are.equal('opencode', agents[1].matched_name)
    end)

    local non_node_cases = {
      { name = "does not walk children for command 'zsh'",    command = 'zsh' },
      { name = "does not walk children for command 'vim'",    command = 'vim' },
      { name = "does not walk children for command 'python'", command = 'python' },
    }

    for _, case in ipairs(non_node_cases) do
      it(case.name, function()
        local bridge = require('reference.bridge')
        local rows = rows_from({
          { pane_id = '%0', pane_pid = 100, session = 'work', window = 'misc', command = case.command },
        })
        system_stub.invokes(make_system_stub({
          display_message = { stdout = 'work\n', code = 0 },
          list_panes = { stdout = rows, code = 0 },
        }))

        local agents, reason = bridge.discover_agents()

        assert.are.same({}, agents)
        assert.are.equal('no agents found', reason)

        for _, call in ipairs(system_stub.calls) do
          local argv = call.vals[1]
          assert.are_not.equal('pgrep', argv[1])
          assert.are_not.equal('ps', argv[1])
        end
      end)
    end
  end)

  describe('process_names option', function()
    local default_cases = {
      { name = 'default list includes claude',   process = 'claude' },
      { name = 'default list includes opencode', process = 'opencode' },
      { name = 'default list includes pi',       process = 'pi' },
    }

    for _, case in ipairs(default_cases) do
      it(case.name, function()
        local bridge = require('reference.bridge')
        local rows = rows_from({
          { pane_id = '%0', pane_pid = 100, session = 'work', window = 'agent', command = case.process },
        })
        system_stub.invokes(make_system_stub({
          display_message = { stdout = 'work\n', code = 0 },
          list_panes = { stdout = rows, code = 0 },
        }))

        local agents = bridge.discover_agents()

        assert.are.equal(1, #agents)
        assert.are.equal(case.process, agents[1].matched_name)
      end)
    end

    it('honours a custom process_names list, ignoring defaults that are not in the override', function()
      local bridge = require('reference.bridge')
      local rows = rows_from({
        { pane_id = '%0', pane_pid = 100, session = 'work', window = 'editor', command = 'claude' },
        { pane_id = '%1', pane_pid = 101, session = 'work', window = 'custom', command = 'custom_agent' },
      })
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = { stdout = rows, code = 0 },
      }))

      local agents, reason = bridge.discover_agents({ process_names = { 'custom_agent' } })

      assert.is_nil(reason)
      assert.are.equal(1, #agents)
      assert.are.equal('%1', agents[1].pane_id)
      assert.are.equal('custom_agent', agents[1].matched_name)
    end)
  end)

  describe('return contract', function()
    it('returns reason as nil whenever the list is non-empty', function()
      local bridge = require('reference.bridge')
      local rows = rows_from({
        { pane_id = '%0', pane_pid = 100, session = 'work', window = 'agent', command = 'claude' },
      })
      system_stub.invokes(make_system_stub({
        display_message = { stdout = 'work\n', code = 0 },
        list_panes = { stdout = rows, code = 0 },
      }))

      local agents, reason = bridge.discover_agents()

      assert.is_true(#agents > 0)
      assert.is_nil(reason)
    end)
  end)
end)

describe('reference.bridge.send', function()
  local system_stub
  local notify_stub

  before_each(function()
    system_stub = stub(vim, 'system')
    notify_stub = stub(vim, 'notify')
  end)

  after_each(function()
    system_stub:revert()
    notify_stub:revert()
  end)

  local function send_keys_result(result)
    system_stub.invokes(function(argv)
      if argv[1] == 'tmux' and argv[2] == 'send-keys' then
        return fake_handle(result)
      end
      error('unexpected vim.system call: ' .. vim.inspect(argv))
    end)
  end

  describe('with valid input', function()
    it('writes the given text to the target pane via tmux send-keys -t <pane_id> -l <text>', function()
      local bridge = require('reference.bridge')
      send_keys_result({ stdout = '', code = 0 })

      bridge.send('%1', '@lua/foo.lua#L5-12')

      assert.stub(system_stub).was.called(1)
      local argv = system_stub.calls[1].vals[1]
      assert.are.same({ 'tmux', 'send-keys', '-t', '%1', '-l', '@lua/foo.lua#L5-12' }, argv)
    end)

    it('returns ok (nil reason) when tmux exits 0', function()
      local bridge = require('reference.bridge')
      send_keys_result({ stdout = '', code = 0 })

      local reason = bridge.send('%1', '@lua/foo.lua')

      assert.is_nil(reason)
    end)

    it('returns a reason string when tmux exits non-zero', function()
      local bridge = require('reference.bridge')
      send_keys_result({ stdout = '', stderr = "can't find pane\n", code = 1 })

      local reason = bridge.send('%bogus', '@lua/foo.lua')

      assert.is_string(reason)
    end)

    it('passes the literal flag -l so special characters in the reference are not interpreted as tmux key names', function()
      local bridge = require('reference.bridge')
      send_keys_result({ stdout = '', code = 0 })

      bridge.send('%1', '@lua/foo.lua')

      local argv = system_stub.calls[1].vals[1]
      local saw_literal = false
      for _, arg in ipairs(argv) do
        if arg == '-l' then saw_literal = true end
      end
      assert.is_true(saw_literal)
    end)
  end)

  describe('with empty input', function()
    local cases = {
      { name = 'skips the tmux call and warns when text is nil',     pane_id = '%1', text = nil },
      { name = 'skips the tmux call and warns when text is empty',   pane_id = '%1', text = '' },
      { name = 'skips the tmux call and warns when pane_id is nil',  pane_id = nil,  text = '@x' },
      { name = 'skips the tmux call and warns when pane_id is empty', pane_id = '',  text = '@x' },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local bridge = require('reference.bridge')

        bridge.send(case.pane_id, case.text)

        assert.stub(system_stub).was_not.called()
        assert.stub(notify_stub).was.called(1)
      end)
    end
  end)
end)

describe('reference.bridge.focus', function()
  local system_stub
  local notify_stub

  before_each(function()
    system_stub = stub(vim, 'system')
    notify_stub = stub(vim, 'notify')
  end)

  after_each(function()
    system_stub:revert()
    notify_stub:revert()
  end)

  local function focus_routes(routes)
    system_stub.invokes(function(argv)
      local key
      if argv[1] == 'tmux' and argv[2] == 'select-window' then
        key = 'select_window'
      elseif argv[1] == 'tmux' and argv[2] == 'select-pane' then
        key = 'select_pane'
      end

      local route = routes[key]
      if route == nil then
        error('unexpected vim.system call: ' .. vim.inspect(argv))
      end

      return fake_handle(route)
    end)
  end

  describe('with valid input', function()
    it('runs tmux select-window -t <pane_id> then tmux select-pane -t <pane_id>', function()
      local bridge = require('reference.bridge')
      focus_routes({
        select_window = { stdout = '', code = 0 },
        select_pane = { stdout = '', code = 0 },
      })

      bridge.focus('%1')

      assert.stub(system_stub).was.called(2)
      assert.are.same({ 'tmux', 'select-window', '-t', '%1' }, system_stub.calls[1].vals[1])
      assert.are.same({ 'tmux', 'select-pane', '-t', '%1' }, system_stub.calls[2].vals[1])
    end)

    it('returns ok (nil reason) when both tmux calls exit 0', function()
      local bridge = require('reference.bridge')
      focus_routes({
        select_window = { stdout = '', code = 0 },
        select_pane = { stdout = '', code = 0 },
      })

      local reason = bridge.focus('%1')

      assert.is_nil(reason)
    end)

    it('returns a reason string when select-window fails', function()
      local bridge = require('reference.bridge')
      focus_routes({
        select_window = { stdout = '', stderr = "can't find window\n", code = 1 },
        select_pane = { stdout = '', code = 0 },
      })

      local reason = bridge.focus('%bogus')

      assert.is_string(reason)
    end)

    it('returns a reason string when select-pane fails', function()
      local bridge = require('reference.bridge')
      focus_routes({
        select_window = { stdout = '', code = 0 },
        select_pane = { stdout = '', stderr = "can't find pane\n", code = 1 },
      })

      local reason = bridge.focus('%bogus')

      assert.is_string(reason)
    end)
  end)

  describe('with empty input', function()
    local cases = {
      { name = 'skips the tmux calls and warns when pane_id is nil',   pane_id = nil },
      { name = 'skips the tmux calls and warns when pane_id is empty', pane_id = '' },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local bridge = require('reference.bridge')

        bridge.focus(case.pane_id)

        assert.stub(system_stub).was_not.called()
        assert.stub(notify_stub).was.called(1)
      end)
    end
  end)
end)
