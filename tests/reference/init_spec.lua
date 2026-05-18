local stub = require('luassert.stub')

describe('reference.setup config merging', function()
  local commands = require('reference.commands')
  local reference = require('reference')
  local register_stub

  before_each(function()
    register_stub = stub(commands, 'register')
  end)

  after_each(function()
    register_stub:revert()
  end)

  describe('default merge', function()
    it('calls commands.register once with the default tmux.process_names and switch_to_target = true', function()
      reference.setup({})

      assert.stub(register_stub).was.called(1)
      local cfg = register_stub.calls[1].vals[1]
      assert.are.same({ 'claude', 'opencode', 'pi' }, cfg.tmux.process_names)
      assert.is_true(cfg.tmux.switch_to_target)
    end)
  end)

  describe('user overrides', function()
    it('overrides tmux.process_names while keeping the default switch_to_target', function()
      reference.setup({ tmux = { process_names = { 'custom_agent' } } })

      assert.stub(register_stub).was.called(1)
      local cfg = register_stub.calls[1].vals[1]
      assert.are.same({ 'custom_agent' }, cfg.tmux.process_names)
      assert.is_true(cfg.tmux.switch_to_target)
    end)

    it('overrides tmux.switch_to_target while keeping the default process_names', function()
      reference.setup({ tmux = { switch_to_target = false } })

      assert.stub(register_stub).was.called(1)
      local cfg = register_stub.calls[1].vals[1]
      assert.is_false(cfg.tmux.switch_to_target)
      assert.are.same({ 'claude', 'opencode', 'pi' }, cfg.tmux.process_names)
    end)
  end)

  describe('repeated setup calls', function()
    it('calls commands.register once per setup with the per-call merged config', function()
      reference.setup({ tmux = { process_names = { 'first_agent' } } })
      reference.setup({ tmux = { switch_to_target = false } })

      assert.stub(register_stub).was.called(2)

      local first_cfg = register_stub.calls[1].vals[1]
      assert.are.same({ 'first_agent' }, first_cfg.tmux.process_names)
      assert.is_true(first_cfg.tmux.switch_to_target)

      local second_cfg = register_stub.calls[2].vals[1]
      assert.are.same({ 'claude', 'opencode', 'pi' }, second_cfg.tmux.process_names)
      assert.is_false(second_cfg.tmux.switch_to_target)
    end)
  end)
end)
