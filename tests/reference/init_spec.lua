local stub = require('luassert.stub')

local function load_reference()
  package.loaded['reference'] = nil
  return require('reference')
end

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
