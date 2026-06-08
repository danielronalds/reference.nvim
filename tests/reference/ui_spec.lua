local stub = require('luassert.stub')

describe('reference.ui.format_agent', function()
  it('renders matched_name, address, and window for a fully populated agent', function()
    local ui = require('reference.ui')
    local agent = {
      matched_name = 'claude',
      session = 'work',
      window_index = 2,
      pane_index = 1,
      window = 'editor',
      command = 'claude',
    }

    local result = ui.format_agent(agent)

    assert.are.equal('(editor:2.1 - claude) work', result)
  end)

  describe('with missing fields', function()
    local cases = {
      {
        name = "substitutes '?' for a missing session",
        agent = { matched_name = 'claude', window_index = 2, pane_index = 1, window = 'editor' },
        expected = '(editor:2.1 - claude) ?',
      },
      {
        name = "substitutes '?' for a missing window_index",
        agent = { matched_name = 'claude', session = 'work', pane_index = 1, window = 'editor' },
        expected = '(editor:?.1 - claude) work',
      },
      {
        name = "substitutes '?' for a missing pane_index",
        agent = { matched_name = 'claude', session = 'work', window_index = 2, window = 'editor' },
        expected = '(editor:2.? - claude) work',
      },
      {
        name = "substitutes '?' for a missing window",
        agent = { matched_name = 'claude', session = 'work', window_index = 2, pane_index = 1 },
        expected = '(?:2.1 - claude) work',
      },
      {
        name = "falls back to command when matched_name is missing",
        agent = { command = 'claude', session = 'work', window_index = 2, pane_index = 1, window = 'editor' },
        expected = '(editor:2.1 - claude) work',
      },
      {
        name = "falls back to '?' when both matched_name and command are missing",
        agent = { session = 'work', window_index = 2, pane_index = 1, window = 'editor' },
        expected = '(editor:2.1 - ?) work',
      },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local ui = require('reference.ui')

        local result = ui.format_agent(case.agent)

        assert.are.equal(case.expected, result)
      end)
    end
  end)
end)

describe('reference.ui.pick_agent', function()
  local ui_select_stub

  before_each(function()
    ui_select_stub = stub(vim.ui, 'select')
  end)

  after_each(function()
    ui_select_stub:revert()
  end)

  it('calls vim.ui.select with the agent list and a format_item option that delegates to format_agent', function()
    local ui = require('reference.ui')
    local agents = {
      { pane_id = '%1', matched_name = 'claude',   session = 'work', window_index = 0, pane_index = 0, window = 'one' },
      { pane_id = '%2', matched_name = 'opencode', session = 'work', window_index = 1, pane_index = 0, window = 'two' },
    }

    ui.pick_agent(agents, function() end)

    assert.stub(ui_select_stub).was.called(1)
    local items = ui_select_stub.calls[1].vals[1]
    local opts = ui_select_stub.calls[1].vals[2]
    assert.are.same(agents, items)
    assert.are.equal(ui.format_agent(agents[1]), opts.format_item(agents[1]))
  end)

  it('invokes on_choice with the selected agent when the user picks one', function()
    local ui = require('reference.ui')
    local agents = {
      { pane_id = '%1', matched_name = 'claude',   session = 'work', window_index = 0, pane_index = 0, window = 'one' },
      { pane_id = '%2', matched_name = 'opencode', session = 'work', window_index = 1, pane_index = 0, window = 'two' },
    }
    ui_select_stub.invokes(function(items, _opts, on_select)
      on_select(items[2])
    end)
    local received
    local function on_choice(agent) received = agent end

    ui.pick_agent(agents, on_choice)

    assert.are.same(agents[2], received)
  end)

  it('invokes on_choice with nil when the user cancels', function()
    local ui = require('reference.ui')
    local agents = {
      { pane_id = '%1', matched_name = 'claude', session = 'work', window_index = 0, pane_index = 0, window = 'one' },
    }
    ui_select_stub.invokes(function(_items, _opts, on_select)
      on_select(nil)
    end)
    local called_with_nil = false
    local function on_choice(agent)
      if agent == nil then called_with_nil = true end
    end

    ui.pick_agent(agents, on_choice)

    assert.is_true(called_with_nil)
  end)
end)
