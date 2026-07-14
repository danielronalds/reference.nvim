local stub = require('luassert.stub')

local function fake_handle(result)
  return { wait = function() return result end }
end

local function system_result(result)
  return function()
    return fake_handle(result)
  end
end

describe('reference.wade', function()
  local wade = require('reference.wade')
  local system_stub
  local saved_wade_addr
  local saved_wade_dev
  local saved_wade_session

  before_each(function()
    system_stub = stub(vim, 'system')
    saved_wade_addr = vim.env.WADE_ADDR
    saved_wade_dev = vim.env.WADE_DEV
    saved_wade_session = vim.env.WADE_SESSION
    vim.env.WADE_ADDR = nil
    vim.env.WADE_DEV = nil
    vim.env.WADE_SESSION = nil
  end)

  after_each(function()
    system_stub:revert()
    vim.env.WADE_ADDR = saved_wade_addr
    vim.env.WADE_DEV = saved_wade_dev
    vim.env.WADE_SESSION = saved_wade_session
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

      assert.are.equal('http://editor-dev.localhost:8765', result)
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
    it('percent encodes project names for use as a path segment', function()
      local result = wade.url_encode('wade feature/one')

      assert.are.equal('wade%20feature%2Fone', result)
    end)
  end)

  describe('send', function()
    it('returns a reason and skips curl when WADE_SESSION is missing', function()
      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('WADE_SESSION is not set', reason)
      assert.stub(system_stub).was_not.called()
    end)

    it('posts the reference to the current WADE session agent endpoint', function()
      vim.env.WADE_SESSION = 'wade feature'
      vim.env.WADE_ADDR = 'editor.localhost:8090'
      system_stub.invokes(system_result({ stdout = '\n204', stderr = '', code = 0 }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua#L5-12')

      assert.is_nil(reason)
      assert.stub(system_stub).was.called(1)
      assert.are.same({
        'curl',
        '--silent',
        '--show-error',
        '--max-time',
        '5',
        '--request',
        'POST',
        '--header',
        'Content-Type: application/json',
        '--data',
        '{"text":"@lua/foo.lua#L5-12"}',
        '--write-out',
        '\n%{http_code}',
        'http://editor.localhost:8090/api/sessions/wade%20feature/agent',
      }, system_stub.calls[1].vals[1])
    end)

    it('uses the configured timeout', function()
      vim.env.WADE_SESSION = 'wade'
      system_stub.invokes(system_result({ stdout = '\n204', stderr = '', code = 0 }))

      wade.send({ timeout_seconds = 2 }, '@lua/foo.lua')

      assert.are.equal('2', system_stub.calls[1].vals[1][5])
    end)

    it('returns the WADE error message from non-204 JSON responses', function()
      vim.env.WADE_SESSION = 'wade'
      system_stub.invokes(system_result({
        stdout = '{"message":"agent session not found"}\n404',
        stderr = '',
        code = 0,
      }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('WADE request failed with HTTP 404: agent session not found', reason)
    end)

    it('returns the response body from non-204 non-JSON responses', function()
      vim.env.WADE_SESSION = 'wade'
      system_stub.invokes(system_result({ stdout = 'not found\n404', stderr = '', code = 0 }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('WADE request failed with HTTP 404: not found', reason)
    end)

    it('returns curl stderr when curl fails', function()
      vim.env.WADE_SESSION = 'wade'
      system_stub.invokes(system_result({ stdout = '', stderr = 'connection refused\n', code = 7 }))

      local reason = wade.send({ timeout_seconds = 5 }, '@lua/foo.lua')

      assert.are.equal('curl failed: connection refused', reason)
    end)
  end)
end)
