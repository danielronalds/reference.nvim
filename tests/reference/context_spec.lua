describe('reference.context.build_file_reference', function()
  describe('with a valid path', function()
    local cases = {
      {
        name = 'returns @path when no range is given',
        range = nil,
        expected = '@lua/foo.lua',
      },
      {
        name = 'returns @path#Lstart-end for a multi-line range',
        range = { line1 = 5, line2 = 12 },
        expected = '@lua/foo.lua#L5-12',
      },
      {
        name = 'still emits both bounds when line1 equals line2',
        range = { line1 = 5, line2 = 5 },
        expected = '@lua/foo.lua#L5-5',
      },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local context = require('reference.context')
        local path = 'lua/foo.lua'

        local result = context.build_file_reference(path, case.range)

        assert.are.equal(case.expected, result)
      end)
    end
  end)

  describe('with an absent path', function()
    local cases = {
      { name = 'returns empty string when path is nil', path = nil },
      { name = 'returns empty string when path is empty', path = '' },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local context = require('reference.context')
        local range = { line1 = 5, line2 = 12 }

        local result = context.build_file_reference(case.path, range)

        assert.are.equal('', result)
      end)
    end
  end)

  describe('with an invalid range', function()
    local cases = {
      {
        name = 'falls back to path-only when line1 is missing',
        range = { line2 = 12 },
      },
      {
        name = 'falls back to path-only when line2 is missing',
        range = { line1 = 5 },
      },
      {
        name = 'falls back to path-only when line1 is greater than line2',
        range = { line1 = 12, line2 = 5 },
      },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local context = require('reference.context')
        local path = 'lua/foo.lua'

        local result = context.build_file_reference(path, case.range)

        assert.are.equal('@lua/foo.lua', result)
      end)
    end
  end)

  it('does not mutate the input range table', function()
    local context = require('reference.context')
    local path = 'lua/foo.lua'
    local range = { line1 = 5, line2 = 12 }
    local original_line1 = range.line1
    local original_line2 = range.line2

    context.build_file_reference(path, range)

    assert.are.equal(original_line1, range.line1)
    assert.are.equal(original_line2, range.line2)
  end)
end)
