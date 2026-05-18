local stub = require('luassert.stub')

local function load_reference()
  package.loaded['reference'] = nil
  return require('reference')
end

describe('reference._send dispatch', function()
  local bridge = require('reference.bridge')
  local reference
  local discover_stub, send_stub, focus_stub
  local notify_stub, ui_select_stub, create_command_stub

  before_each(function()
    discover_stub = stub(bridge, 'discover_agents')
    send_stub = stub(bridge, 'send')
    focus_stub = stub(bridge, 'focus')
    notify_stub = stub(vim, 'notify')
    ui_select_stub = stub(vim.ui, 'select')
    create_command_stub = stub(vim.api, 'nvim_create_user_command')

    reference = load_reference()
    reference.setup({})
  end)

  after_each(function()
    discover_stub:revert()
    send_stub:revert()
    focus_stub:revert()
    notify_stub:revert()
    ui_select_stub:revert()
    create_command_stub:revert()
  end)

  describe('reference building', function()
    it('builds the reference using the resolved path and range and feeds it through the dispatch flow', function()
      discover_stub.returns({
        { pane_id = '%1', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)

      reference._send({ path = 'lua/foo.lua', range = { line1 = 5, line2 = 12 } })

      assert.stub(send_stub).was.called_with('%1', '@lua/foo.lua#L5-12')
    end)
  end)

  describe('no-agent toasts', function()
    local errors = require('reference.errors')
    local cases = {
      { name = "when not in tmux, notifies with the tmux-specific error",     reason = errors.NOT_IN_TMUX,     message = 'Not in a tmux session' },
      { name = "when no agents are discovered, notifies with the no-agent error", reason = errors.NO_AGENTS_FOUND, message = 'No agent was found' },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        discover_stub.returns({}, case.reason)

        reference._send({ path = 'lua/foo.lua' })

        assert.stub(notify_stub).was.called(1)
        assert.stub(notify_stub).was.called_with(case.message, vim.log.levels.ERROR)
        assert.stub(send_stub).was_not.called()
      end)
    end
  end)

  describe('single agent', function()
    it("calls bridge.send with that agent's pane_id and the reference", function()
      discover_stub.returns({
        { pane_id = '%7', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)

      reference._send({ path = 'lua/foo.lua' })

      assert.stub(send_stub).was.called(1)
      assert.stub(send_stub).was.called_with('%7', '@lua/foo.lua')
    end)

    it('calls bridge.focus after sending when tmux.switch_to_target is true', function()
      reference.setup({ tmux = { switch_to_target = true } })
      discover_stub.returns({
        { pane_id = '%7', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)
      send_stub.returns(nil)

      reference._send({ path = 'lua/foo.lua' })

      assert.stub(focus_stub).was.called(1)
      assert.stub(focus_stub).was.called_with('%7')
    end)

    it('does not call bridge.focus when tmux.switch_to_target is false', function()
      reference.setup({ tmux = { switch_to_target = false } })
      discover_stub.returns({
        { pane_id = '%7', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)
      send_stub.returns(nil)

      reference._send({ path = 'lua/foo.lua' })

      assert.stub(focus_stub).was_not.called()
    end)
  end)

  describe('multiple agents', function()
    local agents = {
      { pane_id = '%1', session = 'work', window = 'one', command = 'claude',   matched_name = 'claude' },
      { pane_id = '%2', session = 'work', window = 'two', command = 'opencode', matched_name = 'opencode' },
    }

    it('calls vim.ui.select with the agent list', function()
      discover_stub.returns(agents, nil)

      reference._send({ path = 'lua/foo.lua' })

      assert.stub(ui_select_stub).was.called(1)
      local first_arg = ui_select_stub.calls[1].vals[1]
      assert.are.same(agents, first_arg)
    end)

    it("when the user picks an agent, calls bridge.send with the picked agent's pane_id", function()
      discover_stub.returns(agents, nil)
      ui_select_stub.invokes(function(items, _opts, on_choice)
        on_choice(items[2])
      end)

      reference._send({ path = 'lua/foo.lua' })

      assert.stub(send_stub).was.called(1)
      assert.stub(send_stub).was.called_with('%2', '@lua/foo.lua')
    end)

    it('when the user cancels vim.ui.select, does not call bridge.send', function()
      discover_stub.returns(agents, nil)
      ui_select_stub.invokes(function(_items, _opts, on_choice)
        on_choice(nil)
      end)

      reference._send({ path = 'lua/foo.lua' })

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
        reference._send({ path = case.path })

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

      reference._send({ path = 'lua/foo.lua', pick = 'first' })

      assert.stub(send_stub).was.called(1)
      assert.stub(send_stub).was.called_with('%1', '@lua/foo.lua')
    end)

    it('with multiple agents, does not call vim.ui.select', function()
      discover_stub.returns(agents, nil)

      reference._send({ path = 'lua/foo.lua', pick = 'first' })

      assert.stub(ui_select_stub).was_not.called()
    end)

    it("with multiple agents and switch_to_target = true, calls bridge.focus with the first agent's pane_id", function()
      reference.setup({ tmux = { switch_to_target = true } })
      discover_stub.returns(agents, nil)
      send_stub.returns(nil)

      reference._send({ path = 'lua/foo.lua', pick = 'first' })

      assert.stub(focus_stub).was.called(1)
      assert.stub(focus_stub).was.called_with('%1')
    end)

    it('with multiple agents and switch_to_target = false, does not call bridge.focus', function()
      reference.setup({ tmux = { switch_to_target = false } })
      discover_stub.returns(agents, nil)
      send_stub.returns(nil)

      reference._send({ path = 'lua/foo.lua', pick = 'first' })

      assert.stub(focus_stub).was_not.called()
    end)

    it("with exactly one agent, calls bridge.send with that agent's pane_id", function()
      discover_stub.returns({
        { pane_id = '%7', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
      }, nil)

      reference._send({ path = 'lua/foo.lua', pick = 'first' })

      assert.stub(send_stub).was.called(1)
      assert.stub(send_stub).was.called_with('%7', '@lua/foo.lua')
    end)

    local errors = require('reference.errors')
    local no_agent_cases = {
      { name = "with reason NO_AGENTS_FOUND, notifies with the no-agent error and does not send", reason = errors.NO_AGENTS_FOUND, message = 'No agent was found' },
      { name = "with reason NOT_IN_TMUX, notifies with the tmux-specific error and does not send", reason = errors.NOT_IN_TMUX,     message = 'Not in a tmux session' },
    }

    for _, case in ipairs(no_agent_cases) do
      it(case.name, function()
        discover_stub.returns({}, case.reason)

        reference._send({ path = 'lua/foo.lua', pick = 'first' })

        assert.stub(notify_stub).was.called(1)
        assert.stub(notify_stub).was.called_with(case.message, vim.log.levels.ERROR)
        assert.stub(send_stub).was_not.called()
      end)
    end

    it('with an empty resolved path, notifies the user and does not call bridge.send', function()
      reference._send({ path = '', pick = 'first' })

      assert.stub(send_stub).was_not.called()
      assert.stub(notify_stub).was.called()
      assert.stub(discover_stub).was_not.called()
    end)

    it("when pick is omitted, multi-agent dispatch still routes through vim.ui.select", function()
      discover_stub.returns(agents, nil)

      reference._send({ path = 'lua/foo.lua' })

      assert.stub(ui_select_stub).was.called(1)
      assert.stub(send_stub).was_not.called()
    end)
  end)
end)

describe('reference.setup config merging', function()
  local bridge = require('reference.bridge')
  local reference
  local discover_stub, send_stub, focus_stub
  local notify_stub, ui_select_stub, create_command_stub

  before_each(function()
    discover_stub = stub(bridge, 'discover_agents')
    send_stub = stub(bridge, 'send')
    focus_stub = stub(bridge, 'focus')
    notify_stub = stub(vim, 'notify')
    ui_select_stub = stub(vim.ui, 'select')
    create_command_stub = stub(vim.api, 'nvim_create_user_command')

    reference = load_reference()
  end)

  after_each(function()
    discover_stub:revert()
    send_stub:revert()
    focus_stub:revert()
    notify_stub:revert()
    ui_select_stub:revert()
    create_command_stub:revert()
  end)

  it('merges user-supplied tmux.process_names over the defaults', function()
    local errors = require('reference.errors')
    discover_stub.returns({}, errors.NO_AGENTS_FOUND)

    reference.setup({ tmux = { process_names = { 'custom_agent' } } })
    reference._send({ path = 'lua/foo.lua' })

    local opts = discover_stub.calls[1].vals[1]
    assert.are.same({ 'custom_agent' }, opts.process_names)
  end)

  it('merges user-supplied tmux.switch_to_target over the default', function()
    discover_stub.returns({
      { pane_id = '%1', session = 'work', window = 'agent', command = 'claude', matched_name = 'claude' },
    }, nil)
    send_stub.returns(nil)

    reference.setup({ tmux = { switch_to_target = false } })
    reference._send({ path = 'lua/foo.lua' })

    assert.stub(focus_stub).was_not.called()
  end)

  it('forwards the configured process_names to bridge.discover_agents', function()
    local errors = require('reference.errors')
    discover_stub.returns({}, errors.NO_AGENTS_FOUND)

    reference.setup({})
    reference._send({ path = 'lua/foo.lua' })

    local opts = discover_stub.calls[1].vals[1]
    assert.are.same({ 'claude', 'opencode', 'pi' }, opts.process_names)
  end)
end)
