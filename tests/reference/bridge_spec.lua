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
