local M = {}

local DEFAULT_TIMEOUT_SECONDS = 5
local DEFAULT_RUN_ADDR = 'editor.localhost:8765'
local DEFAULT_DEV_ADDR = 'editor-dev.localhost:8090'

local request, is_success_status, trim, normalise_base_url, error_message, parse_error_message, parse_response
local parse_terminal_id, is_enabled

function M.send(config, text)
  config = config or {}

  if text == nil or text == '' then
    return 'no text'
  end

  local workspace_id = trim(vim.env.WADE_WORKSPACE_ID)
  if workspace_id == '' then
    return 'WADE_WORKSPACE_ID is not set'
  end

  local timeout_seconds = config.timeout_seconds or DEFAULT_TIMEOUT_SECONDS
  local base_url = M.resolve_base_url()
  local workspace_url = base_url .. '/api/v1/workspaces/' .. M.url_encode(workspace_id)
  local start_response, start_reason = request(timeout_seconds, workspace_url .. '/start')
  if start_reason then
    return start_reason
  end

  local terminal_id, terminal_reason = parse_terminal_id(start_response)
  if terminal_reason then
    return terminal_reason
  end

  local input_url = workspace_url .. '/terminals/' .. M.url_encode(terminal_id) .. '/input'
  local input_body = vim.json.encode({ text = text, mode = 'bracketed-paste' })
  local _, input_reason = request(timeout_seconds, input_url, input_body)
  return input_reason
end

function M.resolve_base_url()
  local addr = trim(vim.env.WADE_ADDR)
  if addr ~= '' then
    return normalise_base_url(addr)
  end

  if is_enabled(vim.env.WADE_DEV) then
    return normalise_base_url(DEFAULT_DEV_ADDR)
  end

  return normalise_base_url(DEFAULT_RUN_ADDR)
end

function M.url_encode(value)
  return tostring(value):gsub('([^%w%-_%.~])', function(character)
    return string.format('%%%02X', string.byte(character))
  end)
end

function request(timeout_seconds, url, body)
  local command = {
    'curl',
    '--silent',
    '--show-error',
    '--max-time',
    tostring(timeout_seconds),
    '--request',
    'POST',
  }
  if body ~= nil then
    vim.list_extend(command, {
      '--header',
      'Content-Type: application/json',
      '--data',
      body,
    })
  end
  vim.list_extend(command, {
    '--write-out',
    '\n%{http_code}',
    url,
  })

  local result = vim.system(command):wait()
  if result.code ~= 0 then
    local details = trim(result.stderr)
    if details == '' then
      return nil, 'curl failed'
    end

    return nil, 'curl failed: ' .. details
  end

  local response_body, status = parse_response(tostring(result.stdout or ''))
  if status == nil then
    return nil, 'WADE request failed: missing HTTP status'
  end
  if not is_success_status(status) then
    return nil, error_message(status, response_body)
  end

  return response_body, nil
end

function is_success_status(status)
  local status_number = tonumber(status)
  return status_number ~= nil and status_number >= 200 and status_number < 300
end

function parse_terminal_id(body)
  local ok, decoded = pcall(vim.json.decode, body)
  if not ok or type(decoded) ~= 'table' or type(decoded.id) ~= 'string' or decoded.id == '' then
    return nil, 'WADE start response did not include an agent terminal ID'
  end

  return decoded.id, nil
end

function parse_response(output)
  local body, status = output:match('^(.*)\n(%d%d%d)$')
  return body, status
end

function error_message(status, body)
  local message = parse_error_message(body)
  if message ~= '' then
    return 'WADE request failed with HTTP ' .. status .. ': ' .. message
  end

  return 'WADE request failed with HTTP ' .. status
end

function parse_error_message(body)
  body = trim(body)
  if body == '' then
    return ''
  end

  local ok, decoded = pcall(vim.json.decode, body)
  if ok and type(decoded) == 'table' then
    if type(decoded.detail) == 'string' and decoded.detail ~= '' then
      return decoded.detail
    end
    if type(decoded.message) == 'string' and decoded.message ~= '' then
      return decoded.message
    end
  end

  return body
end

function normalise_base_url(addr)
  addr = trim(addr):gsub('/+$', '')
  if addr:match('^https?://') then
    return addr
  end

  return 'http://' .. addr
end

function is_enabled(value)
  value = trim(value):lower()
  return value ~= '' and value ~= '0' and value ~= 'false' and value ~= 'no'
end

function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

return M
