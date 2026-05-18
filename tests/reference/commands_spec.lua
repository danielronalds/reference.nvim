local stub = require('luassert.stub')

local function find_command_registration(create_command_stub, name)
  for _, call in ipairs(create_command_stub.calls) do
    if call.vals[1] == name then
      return { callback = call.vals[2], opts = call.vals[3] }
    end
  end
  return nil
end

describe('reference.commands.register', function()
  local dispatch = require('reference.dispatch')
  local commands = require('reference.commands')
  local config
  local create_command_stub, dispatch_send_stub, expand_stub, fnamemodify_stub

  before_each(function()
    create_command_stub = stub(vim.api, 'nvim_create_user_command')
    dispatch_send_stub = stub(dispatch, 'send')
    expand_stub = stub(vim.fn, 'expand')
    fnamemodify_stub = stub(vim.fn, 'fnamemodify')

    expand_stub.returns('/abs/lua/foo.lua')
    fnamemodify_stub.returns('lua/foo.lua')

    config = {
      tmux = {
        process_names = { 'claude', 'opencode', 'pi' },
        switch_to_target = true,
      },
    }
  end)

  after_each(function()
    create_command_stub:revert()
    dispatch_send_stub:revert()
    expand_stub:revert()
    fnamemodify_stub:revert()
  end)

  describe('command registration', function()
    local cases = {
      { name = 'registers ReferenceSend with { range = true, force = true }',      command = 'ReferenceSend' },
      { name = 'registers ReferenceSendFirst with { range = true, force = true }', command = 'ReferenceSendFirst' },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        commands.register(config)

        local registration = find_command_registration(create_command_stub, case.command)
        assert.is_not_nil(registration)
        assert.are.same({ range = true, force = true }, registration.opts)
      end)
    end
  end)

  describe("'ReferenceSend' callback", function()
    it('with range = 2, calls dispatch.send with the resolved path and range and no pick', function()
      commands.register(config)
      local registration = find_command_registration(create_command_stub, 'ReferenceSend')

      registration.callback({ range = 2, line1 = 5, line2 = 12 })

      assert.stub(dispatch_send_stub).was.called(1)
      local cfg_arg = dispatch_send_stub.calls[1].vals[1]
      local inputs_arg = dispatch_send_stub.calls[1].vals[2]
      assert.are.same(config, cfg_arg)
      assert.are.equal('lua/foo.lua', inputs_arg.path)
      assert.are.same({ line1 = 5, line2 = 12 }, inputs_arg.range)
      assert.is_nil(inputs_arg.pick)
    end)

    it('with range ~= 2, calls dispatch.send with the resolved path, range = nil, and no pick', function()
      commands.register(config)
      local registration = find_command_registration(create_command_stub, 'ReferenceSend')

      registration.callback({ range = 0 })

      assert.stub(dispatch_send_stub).was.called(1)
      local inputs_arg = dispatch_send_stub.calls[1].vals[2]
      assert.are.equal('lua/foo.lua', inputs_arg.path)
      assert.is_nil(inputs_arg.range)
      assert.is_nil(inputs_arg.pick)
    end)
  end)

  describe("'ReferenceSendFirst' callback", function()
    it("with range = 2, calls dispatch.send with pick = 'first' and the resolved path and range", function()
      commands.register(config)
      local registration = find_command_registration(create_command_stub, 'ReferenceSendFirst')

      registration.callback({ range = 2, line1 = 5, line2 = 12 })

      assert.stub(dispatch_send_stub).was.called(1)
      local inputs_arg = dispatch_send_stub.calls[1].vals[2]
      assert.are.equal('lua/foo.lua', inputs_arg.path)
      assert.are.same({ line1 = 5, line2 = 12 }, inputs_arg.range)
      assert.are.equal('first', inputs_arg.pick)
    end)

    it("with range ~= 2, calls dispatch.send with pick = 'first' and range = nil", function()
      commands.register(config)
      local registration = find_command_registration(create_command_stub, 'ReferenceSendFirst')

      registration.callback({ range = 0 })

      assert.stub(dispatch_send_stub).was.called(1)
      local inputs_arg = dispatch_send_stub.calls[1].vals[2]
      assert.are.equal('lua/foo.lua', inputs_arg.path)
      assert.is_nil(inputs_arg.range)
      assert.are.equal('first', inputs_arg.pick)
    end)
  end)
end)
