local M = {}

local DEFAULT_TIMEOUT_SECONDS = 5
local DEFAULT_RUN_ADDR = 'editor.localhost:8765'
local DEFAULT_DEV_ADDR = 'editor-dev.localhost:8765'

local is_enabled, trim, normalise_base_url, error_message, parse_error_message, parse_response

function M.send(config, text)
  config = config or {}

  if text == nil or text == '' then
    return 'no text'
  end

  local project_name = vim.env.WADE_SESSION
  if project_name == nil or project_name == '' then
    return 'WADE_SESSION is not set'
  end

  local timeout_seconds = config.timeout_seconds or DEFAULT_TIMEOUT_SECONDS
  local body = vim.json.encode({ text = text })
  local url = M.resolve_base_url() .. '/api/sessions/' .. M.url_encode(project_name) .. '/agent'
  local result = vim.system({
    'curl',
    '--silent',
    '--show-error',
    '--max-time',
    tostring(timeout_seconds),
    '--request',
    'POST',
    '--header',
    'Content-Type: application/json',
    '--data',
    body,
    '--write-out',
    '\n%{http_code}',
    url,
  }):wait()

  if result.code ~= 0 then
    local details = trim(result.stderr)
    if details == '' then
      return 'curl failed'
    end

    return 'curl failed: ' .. details
  end

  local response_body, status = parse_response(tostring(result.stdout or ''))
  if status == '204' then
    return nil
  end
  if status == nil then
    return 'WADE request failed: missing HTTP status'
  end

  return error_message(status, response_body)
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
  if ok and type(decoded) == 'table' and type(decoded.message) == 'string' and decoded.message ~= '' then
    return decoded.message
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
