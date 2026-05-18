describe('reference.constants', function()
  local cases = {
    { name = 'NOT_IN_TMUX equals not_in_tmux',         key = 'NOT_IN_TMUX',     value = 'not_in_tmux' },
    { name = 'NO_AGENTS_FOUND equals no_agents_found', key = 'NO_AGENTS_FOUND', value = 'no_agents_found' },
  }

  for _, case in ipairs(cases) do
    it(case.name, function()
      local constants = require('reference.constants')

      local actual = constants[case.key]

      assert.are.equal(case.value, actual)
    end)
  end
end)
