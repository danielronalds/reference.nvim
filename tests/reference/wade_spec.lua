local stub = require('luassert.stub')

local function fake_handle(result)
  return { wait = function() return result end }
end

local function system_results(results)
  local result_index = 0
  return function()
    result_index = result_index + 1
    return fake_handle(results[result_index])
  end
end

local function option_value(command, option)
  for index, argument in ipairs(command) do
    if argument == option then
      return command[index + 1]
    end
  end
end

describe('reference.wade', function()
  local wade = require('reference.wade')
  local system_stub
  local saved_wade_addr
  local saved_wade_dev
  local saved_wade_workspace_id

  before_each(function()
    system_stub = stub(vim, 'system')
    saved_wade_addr = vim.env.WADE_ADDR
    saved_wade_dev = vim.env.WADE_DEV
    saved_wade_workspace_id = vim.env.WADE_WORKSPACE_ID
    vim.env.WADE_ADDR = nil
    vim.env.WADE_DEV = nil
    vim.env.WADE_WORKSPACE_ID = nil
  end)

  after_each(function()
    system_stub:revert()
    vim.env.WADE_ADDR = saved_wade_addr
    vim.env.WADE_DEV = saved_wade_dev
    vim.env.WADE_WORKSPACE_ID = saved_wade_workspace_id
  end)

  describe('resolve_base_url', function()
    it('uses WADE_ADDR when present and adds an http scheme', function()
      vim.env.WADE_ADDR = '127.0.0.1:8090'

      local result = wade.resolve_base_url()

      assert.are.equal('http://127.0.0.1:8090', result)
    end)

    it('keeps an explicit scheme and trims trailing slashes from WADE_ADDR', function()
      vim.env.WADE_ADDR = 'https://editor.example.test:9443/'

      local result = wade.resolve_base_url()

      assert.are.equal('https://editor.example.test:9443', result)
    end)

    it('uses the dev default when WADE_DEV is enabled and WADE_ADDR is absent', function()
      vim.env.WADE_DEV = '1'

      local result = wade.resolve_base_url()

      assert.are.equal('http://editor-dev.localhost:8090', result)
    end)

    it('uses the run default when WADE_DEV is absent', function()
      local result = wade.resolve_base_url()

      assert.are.equal('http://editor.localhost:8765', result)
    end)

    it('uses the run default when WADE_DEV is disabled', function()
      vim.env.WADE_DEV = 'false'

      local result = wade.resolve_base_url()

      assert.are.equal('http://editor.localhost:8765', result)
    end)
  end)

  describe('url_encode', function()
    it('percent encodes identifiers for use as path segments', function()
      local result = wade.url_encode('agent:Pi feature/one')

      assert.are.equal('agent%3APi%20feature%2Fone', result)
    end)
  end)

  describe('send', function()
    it('returns a reason and skips curl when WADE_WORKSPACE_ID is missing', function()
      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('WADE_WORKSPACE_ID is not set', reason)
      assert.stub(system_stub).was_not.called()
    end)

    it('starts the default agent and sends the reference to its terminal', function()
      vim.env.WADE_WORKSPACE_ID = 'wade feature'
      vim.env.WADE_ADDR = 'editor.localhost:8090'
      system_stub.invokes(system_results({
        { stdout = '{"id":"agent:Pi","role":"agent"}\n\n200', stderr = '', code = 0 },
        { stdout = '\n204', stderr = '', code = 0 },
      }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua#L5-12')

      assert.is_nil(reason)
      assert.stub(system_stub).was.called(2)
      assert.are.same({
        'curl',
        '--silent',
        '--show-error',
        '--max-time',
        '5',
        '--request',
        'POST',
        '--write-out',
        '\n%{http_code}',
        'http://editor.localhost:8090/api/v1/workspaces/wade%20feature/start',
      }, system_stub.calls[1].vals[1])

      local input_command = system_stub.calls[2].vals[1]
      assert.are.equal(
        'http://editor.localhost:8090/api/v1/workspaces/wade%20feature/terminals/agent%3APi/input',
        input_command[#input_command]
      )
      assert.are.same({
        text = '@lua/foo.lua#L5-12',
        mode = 'bracketed-paste',
      }, vim.json.decode(option_value(input_command, '--data')))
    end)

    it('uses the configured timeout for both requests', function()
      vim.env.WADE_WORKSPACE_ID = 'wade'
      system_stub.invokes(system_results({
        { stdout = '{"id":"agent:pi"}\n200', stderr = '', code = 0 },
        { stdout = '\n204', stderr = '', code = 0 },
      }))

      wade.send({ timeout_seconds = 2 }, '@lua/foo.lua')

      assert.are.equal('2', option_value(system_stub.calls[1].vals[1], '--max-time'))
      assert.are.equal('2', option_value(system_stub.calls[2].vals[1], '--max-time'))
    end)

    it('returns WADE problem details when starting the agent fails', function()
      vim.env.WADE_WORKSPACE_ID = 'wade'
      system_stub.invokes(system_results({
        {
          stdout = '{"detail":"workspace not found","code":"workspace_not_found"}\n404',
          stderr = '',
          code = 0,
        },
      }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('WADE request failed with HTTP 404: workspace not found', reason)
      assert.stub(system_stub).was.called(1)
    end)

    it('returns a reason when the start response has no terminal ID', function()
      vim.env.WADE_WORKSPACE_ID = 'wade'
      system_stub.invokes(system_results({
        { stdout = '{"role":"agent"}\n200', stderr = '', code = 0 },
      }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('WADE start response did not include an agent terminal ID', reason)
      assert.stub(system_stub).was.called(1)
    end)

    it('returns WADE problem details when sending terminal input fails', function()
      vim.env.WADE_WORKSPACE_ID = 'wade'
      system_stub.invokes(system_results({
        { stdout = '{"id":"agent:pi"}\n200', stderr = '', code = 0 },
        {
          stdout = '{"detail":"terminal not found","code":"terminal_not_found"}\n404',
          stderr = '',
          code = 0,
        },
      }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('WADE request failed with HTTP 404: terminal not found', reason)
    end)

    it('returns a non-JSON response body from failed requests', function()
      vim.env.WADE_WORKSPACE_ID = 'wade'
      system_stub.invokes(system_results({
        { stdout = 'not found\n404', stderr = '', code = 0 },
      }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('WADE request failed with HTTP 404: not found', reason)
    end)

    it('returns curl stderr when curl fails', function()
      vim.env.WADE_WORKSPACE_ID = 'wade'
      system_stub.invokes(system_results({
        { stdout = '', stderr = 'connection refused\n', code = 7 },
      }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('curl failed: connection refused', reason)
    end)
  end)
end)
