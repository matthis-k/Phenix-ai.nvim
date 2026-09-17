local compose = require("phenix_nvim.compose.buffer")
local compose_model = require("phenix_nvim.compose.model")
local context = require("phenix_nvim.context")
local image = require("phenix_nvim.image")
local runtime = require("phenix_nvim.runtime")
local sessions = require("phenix_nvim.sessions")
local sidebar = require("phenix_nvim.sidebar")
local state = require("phenix_nvim.state")
local util = require("phenix_nvim.util")

local M = {}

local function insert(item)
  local stored = compose_model.add(state.compose, item)
  local win = sidebar.focus_compose()
  compose.insert(state.compose, stored, win)
end

function M.reference()
  local mode = vim.fn.mode(1)
  local item, error
  if mode == "v" or mode == "V" or mode == "\22" then
    item, error = context.visual_selection()
  else
    item = context.current_location()
  end
  if item == nil then
    util.notify(error, vim.log.levels.ERROR)
    return
  end
  insert(item)
end

function M.reference_at(value)
  local item, error = context.typed_reference(value)
  if item == nil then
    util.notify(error, vim.log.levels.ERROR)
    return
  end
  insert(item)
end

function M.reference_picker()
  context.pick_reference(function(item, error)
    if error ~= nil then
      util.notify(vim.inspect(error), vim.log.levels.ERROR)
      return
    end
    if item ~= nil then
      insert(item)
    end
  end)
end

function M.attach_image(path)
  local function attach(value)
    if value == nil or value == "" then
      return
    end
    local item, error = image.from_file(value)
    if item == nil then
      util.notify(error, vim.log.levels.ERROR)
      return
    end
    insert(item)
  end
  if path ~= nil then
    attach(path)
  else
    vim.ui.input({ prompt = "Image file: ", completion = "file" }, attach)
  end
end

local function submit(session_id, content, revision)
  runtime.prompt(session_id, content, function(_, error)
    if error ~= nil then
      util.notify(vim.inspect(error), vim.log.levels.ERROR)
      return
    end
    if state.compose.revision == revision then
      compose.clear(state.compose)
    end
  end)
end

function M.send()
  local content, error = compose.serialize(state.compose)
  if content == nil then
    util.notify(error, vim.log.levels.ERROR)
    return
  end
  if #content == 0 or (#content == 1 and content[1].kind == "text" and content[1].text == "") then
    util.notify("compose buffer is empty", vim.log.levels.WARN)
    return
  end
  local revision = state.compose.revision
  local session_id = runtime.active_session()
  if session_id ~= nil then
    submit(session_id, content, revision)
    return
  end
  runtime.new_session(function(created, create_error)
    if create_error ~= nil then
      util.notify(vim.inspect(create_error), vim.log.levels.ERROR)
      return
    end
    submit(created.session_id, content, revision)
  end)
end

function M.toggle()
  sidebar.toggle()
end

function M.cancel()
  runtime.cancel_active()
end

function M.new_session()
  sessions.new(function(_, error)
    if error ~= nil then
      util.notify(vim.inspect(error), vim.log.levels.ERROR)
    end
  end)
end

function M.close_session()
  sessions.close(nil, function(_, error)
    if error ~= nil then
      util.notify(vim.inspect(error), vim.log.levels.ERROR)
    end
  end)
end

function M.choose_session()
  sessions.choose()
end

local function choice_label(item, selected)
  local name = item.name or item.id or "unknown"
  local id = item.id
  local marker = id ~= nil and id == selected and "✓ " or "  "
  if id ~= nil and id ~= name then
    return marker .. name .. "  ·  " .. id
  end
  return marker .. name
end

local function open_external_auth(result)
  local uri = result and result.uri
  if type(uri) ~= "string" or uri == "" then
    return false
  end
  if result.instructions ~= nil and result.instructions ~= "" then
    util.notify(result.instructions, vim.log.levels.INFO)
  end
  if type(vim.ui.open) == "function" then
    local ok, open_error = pcall(vim.ui.open, uri)
    if ok then
      return true
    end
    util.notify(tostring(open_error), vim.log.levels.WARN)
  end
  util.notify("Open this URL to finish Phenix authentication: " .. uri, vim.log.levels.INFO)
  return true
end

function M.authenticate()
  if type(runtime.list_authentication_methods) ~= "function" or type(runtime.authenticate) ~= "function" then
    util.notify("The installed Phenix runtime does not expose application authentication yet", vim.log.levels.WARN)
    return
  end
  runtime.list_authentication_methods(function(result, error)
    if error ~= nil then
      util.notify(vim.inspect(error), vim.log.levels.ERROR)
      return
    end
    local methods = result and result.methods or {}
    if #methods == 0 then
      util.notify("No Phenix authentication methods are available", vim.log.levels.WARN)
      return
    end
    vim.ui.select(methods, {
      prompt = "Phenix authentication",
      format_item = function(method)
        local label = method.name or method.id or "unknown"
        if method.description ~= nil and method.description ~= "" then
          return label .. "  ·  " .. method.description
        end
        return label
      end,
    }, function(method)
      if method == nil then
        return
      end
      runtime.authenticate(method.id, function(auth_result, auth_error)
        if auth_error ~= nil then
          util.notify(vim.inspect(auth_error), vim.log.levels.ERROR)
          return
        end
        local kind = auth_result and string.lower(tostring(auth_result.kind or "")) or ""
        if kind == "external" then
          open_external_auth(auth_result)
          return
        end
        util.notify("Phenix authentication completed", vim.log.levels.INFO)
      end)
    end)
  end)
end

function M.choose_model()
  runtime.list_models(function(result, error)
    if error ~= nil then
      util.notify(vim.inspect(error), vim.log.levels.ERROR)
      return
    end
    local available = result and result.available or {}
    if #available == 0 then
      util.notify("No models are available for this session", vim.log.levels.WARN)
      return
    end
    vim.ui.select(available, {
      prompt = "Phenix model",
      format_item = function(item)
        return choice_label(item, result.selected)
      end,
    }, function(item)
      if item == nil then
        return
      end
      runtime.select_model(item.id, function(_, select_error)
        if select_error ~= nil then
          util.notify(vim.inspect(select_error), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

function M.choose_routing_profile()
  runtime.list_routing_profiles(function(result, error)
    if error ~= nil then
      util.notify(vim.inspect(error), vim.log.levels.ERROR)
      return
    end
    local available = result and result.available or {}
    if #available == 0 then
      util.notify("No routing profiles are available for this session", vim.log.levels.WARN)
      return
    end
    vim.ui.select(available, {
      prompt = "Phenix routing profile",
      format_item = function(item)
        return choice_label(item, result.selected)
      end,
    }, function(item)
      if item == nil then
        return
      end
      runtime.select_routing_profile(item.id, function(_, select_error)
        if select_error ~= nil then
          util.notify(vim.inspect(select_error), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

return M
