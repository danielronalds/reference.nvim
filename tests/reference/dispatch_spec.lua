local stub = require('luassert.stub')

describe('reference.dispatch.send', function()
  local bridge = require('reference.bridge')
  local errors = require('reference.errors')
  local ui = require('reference.ui')
  local dispatch = require('reference.dispatch')
  local default_config
  local discover_stub, send_stub, focus_stub
  local notify_stub, pick_agent_stub

  before_each(function()
    discover_stub = stub(bridge, 'discover_agents')
    send_stub = stub(bridge, 'send')
    focus_stub = stub(bridge, 'focus')
    notify_stub = stub(vim, 'notify')
    pick_agent_stub = stub(ui, 'pick_agent')

    default_config = {
      tmux = {
        process_names = { 'claude', 'opencode', 'pi' },
        switch_to_target = true,
      },
    }
  end)

  after_each(function()
    discover_stub:revert()
    send_stub:revert()
    focus_stub:revert()
    notify_stub:revert()
    pick_agent_stub:revert()
  end)

  describe('reference building', function()
    it('builds the reference using the resolved path and range and feeds it through to bridge.send', function()
      discover_stub.returns({
        { pane_id = '%1', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)

      dispatch.send(default_config, { path = 'lua/foo.lua', range = { line1 = 5, line2 = 12 } })

      assert.stub(send_stub).was.called_with('%1', '@lua/foo.lua#L5-12')
    end)
  end)

  describe('no-agent toasts', function()
    local cases = {
      { name = 'notifies "Not in a tmux session" at ERROR level when reason is NOT_IN_TMUX',  reason = errors.NOT_IN_TMUX,     message = 'Not in a tmux session' },
      { name = 'notifies "No agent was found" at ERROR level when reason is NO_AGENTS_FOUND', reason = errors.NO_AGENTS_FOUND, message = 'No agent was found' },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        discover_stub.returns({}, case.reason)

        dispatch.send(default_config, { path = 'lua/foo.lua' })

        assert.stub(notify_stub).was.called(1)
        assert.stub(notify_stub).was.called_with(case.message, vim.log.levels.ERROR)
      end)
    end

    it('does not call bridge.send when reason is non-nil', function()
      discover_stub.returns({}, errors.NO_AGENTS_FOUND)

      dispatch.send(default_config, { path = 'lua/foo.lua' })

      assert.stub(send_stub).was_not.called()
    end)
  end)

  describe('single agent', function()
    it("calls bridge.send with that agent's pane_id and the reference", function()
      discover_stub.returns({
        { pane_id = '%7', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)

      dispatch.send(default_config, { path = 'lua/foo.lua' })

      assert.stub(send_stub).was.called(1)
      assert.stub(send_stub).was.called_with('%7', '@lua/foo.lua')
    end)

    it('calls bridge.focus after sending when tmux.switch_to_target is true', function()
      local config = vim.deepcopy(default_config)
      config.tmux.switch_to_target = true
      discover_stub.returns({
        { pane_id = '%7', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)
      send_stub.returns(nil)

      dispatch.send(config, { path = 'lua/foo.lua' })

      assert.stub(focus_stub).was.called(1)
      assert.stub(focus_stub).was.called_with('%7')
    end)

    it('does not call bridge.focus when tmux.switch_to_target is false', function()
      local config = vim.deepcopy(default_config)
      config.tmux.switch_to_target = false
      discover_stub.returns({
        { pane_id = '%7', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)
      send_stub.returns(nil)

      dispatch.send(config, { path = 'lua/foo.lua' })

      assert.stub(focus_stub).was_not.called()
    end)
  end)

  describe('multiple agents', function()
    local agents = {
      { pane_id = '%1', session = 'work', window = 'one', command = 'claude',   matched_name = 'claude' },
      { pane_id = '%2', session = 'work', window = 'two', command = 'opencode', matched_name = 'opencode' },
    }

    it('calls ui.pick_agent with the agent list', function()
      discover_stub.returns(agents, nil)

      dispatch.send(default_config, { path = 'lua/foo.lua' })

      assert.stub(pick_agent_stub).was.called(1)
      local first_arg = pick_agent_stub.calls[1].vals[1]
      assert.are.same(agents, first_arg)
    end)

    it("when the user picks an agent, calls bridge.send with the picked agent's pane_id", function()
      discover_stub.returns(agents, nil)
      pick_agent_stub.invokes(function(items, on_choice)
        on_choice(items[2])
      end)

      dispatch.send(default_config, { path = 'lua/foo.lua' })

      assert.stub(send_stub).was.called(1)
      assert.stub(send_stub).was.called_with('%2', '@lua/foo.lua')
    end)

    it('when the user cancels the picker, does not call bridge.send', function()
      discover_stub.returns(agents, nil)
      pick_agent_stub.invokes(function(_items, on_choice)
        on_choice(nil)
      end)

      dispatch.send(default_config, { path = 'lua/foo.lua' })

      assert.stub(send_stub).was_not.called()
    end)
  end)

  describe('with no resolved path', function()
    local cases = {
      { name = 'notifies and does not send when path is nil',   path = nil },
      { name = 'notifies and does not send when path is empty', path = '' },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        dispatch.send(default_config, { path = case.path })

        assert.stub(send_stub).was_not.called()
        assert.stub(notify_stub).was.called()
        assert.stub(discover_stub).was_not.called()
      end)
    end
  end)

  describe("pick = 'first'", function()
    local agents = {
      { pane_id = '%1', session = 'work', window = 'one', command = 'claude',   matched_name = 'claude' },
      { pane_id = '%2', session = 'work', window = 'two', command = 'opencode', matched_name = 'opencode' },
    }

    it("with multiple agents, calls bridge.send with the first agent's pane_id and the reference", function()
      discover_stub.returns(agents, nil)

      dispatch.send(default_config, { path = 'lua/foo.lua', pick = 'first' })

      assert.stub(send_stub).was.called(1)
      assert.stub(send_stub).was.called_with('%1', '@lua/foo.lua')
    end)

    it('with multiple agents, does not call ui.pick_agent', function()
      discover_stub.returns(agents, nil)

      dispatch.send(default_config, { path = 'lua/foo.lua', pick = 'first' })

      assert.stub(pick_agent_stub).was_not.called()
    end)

    it("with exactly one agent, calls bridge.send with that agent's pane_id", function()
      discover_stub.returns({
        { pane_id = '%7', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)

      dispatch.send(default_config, { path = 'lua/foo.lua', pick = 'first' })

      assert.stub(send_stub).was.called(1)
      assert.stub(send_stub).was.called_with('%7', '@lua/foo.lua')
    end)

    local no_agent_cases = {
      { name = 'with reason NO_AGENTS_FOUND, notifies with the matching toast and does not send', reason = errors.NO_AGENTS_FOUND, message = 'No agent was found' },
      { name = 'with reason NOT_IN_TMUX, notifies with the matching toast and does not send',     reason = errors.NOT_IN_TMUX,     message = 'Not in a tmux session' },
    }

    for _, case in ipairs(no_agent_cases) do
      it(case.name, function()
        discover_stub.returns({}, case.reason)

        dispatch.send(default_config, { path = 'lua/foo.lua', pick = 'first' })

        assert.stub(notify_stub).was.called(1)
        assert.stub(notify_stub).was.called_with(case.message, vim.log.levels.ERROR)
        assert.stub(send_stub).was_not.called()
      end)
    end

    it('when pick is omitted, multi-agent dispatch routes through ui.pick_agent', function()
      discover_stub.returns(agents, nil)

      dispatch.send(default_config, { path = 'lua/foo.lua' })

      assert.stub(pick_agent_stub).was.called(1)
      assert.stub(send_stub).was_not.called()
    end)
  end)
end)
