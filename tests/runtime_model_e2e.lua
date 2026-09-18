local frontend = require("phenix_nvim")
local runtime = require("phenix_nvim.runtime")
local transcript = require("phenix_nvim.transcript.controller")
local transcript_buffer = require("phenix_nvim.transcript.buffer")

local command = assert(vim.env.PHENIX_FIXTURE_ACP, "PHENIX_FIXTURE_ACP is required")
local marker = "PHENIX_NVIM_E2E_MARKER"
local expected = "PHENIX_NVIM_E2E_RESPONSE"

frontend.setup({
  auto_connect = false,
  command = command,
  env = {
    PHENIX_STATE_DB = assert(vim.env.PHENIX_STATE_DB, "PHENIX_STATE_DB is required"),
    PHENIX_FIXTURE_EXPECT_INPUT = marker,
    PHENIX_FIXTURE_RESPONSE = expected,
  },
})

local connected = false
local connection_error = nil
frontend.connect(function(_, err)
  connection_error = err
  connected = true
end)
assert(vim.wait(10000, function()
  return connected
end, 10), "deterministic fixture connection timed out")
assert(connection_error == nil, vim.inspect(connection_error))

frontend.new_session()
assert(vim.wait(10000, function()
  return runtime.active_session() ~= nil
end, 10), "deterministic fixture session creation timed out")
local session_id = assert(runtime.active_session())

local selections = nil
local selection_error = nil
runtime.list_selections(function(result, err)
  selections = result
  selection_error = err
end)
assert(vim.wait(10000, function()
  return selections ~= nil or selection_error ~= nil
end, 10), "deterministic fixture selection discovery timed out")
assert(selection_error == nil, vim.inspect(selection_error))

local fixture = nil
for _, item in ipairs(selections.available or {}) do
  if item.id == "fixture.deterministic" then
    fixture = item
    break
  end
end
assert(fixture ~= nil, "deterministic fixture route was not exposed by the packaged runtime")

local selected = nil
local select_error = nil
runtime.select(fixture.id, function(result, err)
  selected = result
  select_error = err
end)
assert(vim.wait(10000, function()
  return selected ~= nil or select_error ~= nil
end, 10), "deterministic fixture selection timed out")
assert(select_error == nil, vim.inspect(select_error))
assert(selected.selected == fixture.id, "deterministic fixture route was not selected")

local prompt_result = nil
local prompt_error = nil
runtime.prompt(session_id, {
  { kind = "text", text = marker },
}, function(result, err)
  prompt_result = result
  prompt_error = err
end)
assert(vim.wait(10000, function()
  return prompt_result ~= nil or prompt_error ~= nil
end, 10), "deterministic model prompt timed out")
assert(prompt_error == nil, vim.inspect(prompt_error))
assert(type(prompt_result.execution_id) == "string" and prompt_result.execution_id ~= "", "prompt did not return an execution id")

local function normalized_kind(value)
  if type(value) == "table" then
    value = value.kind or value.tag
  end
  return string.lower(tostring(value or "")):gsub("_", "")
end

local function text_content(content)
  local parts = {}
  for _, item in ipairs(content or {}) do
    if normalized_kind(item.kind) == "text" and type(item.text) == "string" then
      table.insert(parts, item.text)
    end
  end
  return table.concat(parts)
end

local projection = assert(runtime.session_state().sessions[session_id], "live session projection is missing")
local saw_user = false
local saw_delta = false
local saw_assistant = false
local saw_running = false
local saw_completed = false
for _, entry in ipairs(projection.updates or {}) do
  local change = entry.update or {}
  local change_kind = normalized_kind(change.kind)
  if change_kind == "message" and change.message ~= nil then
    local role = normalized_kind(change.message.role)
    if role == "user" and text_content(change.message.content) == marker then
      saw_user = true
    elseif role == "assistant" and text_content(change.message.content) == expected then
      saw_assistant = true
    end
  elseif change_kind == "textdelta"
      and change.execution_id == prompt_result.execution_id
      and change.text == expected then
    saw_delta = true
  elseif change_kind == "execution"
      and change.execution_id == prompt_result.execution_id
      and change.update ~= nil
      and normalized_kind(change.update.kind) == "state" then
    local state = normalized_kind(change.update.state)
    if state == "running" then
      saw_running = true
    elseif state == "completed" then
      saw_completed = true
    end
  end
end

assert(saw_user, "user prompt did not survive the application/session projection")
assert(saw_delta, "deterministic provider output did not survive as a text delta")
assert(saw_assistant, "deterministic provider output did not survive as the final assistant message")
assert(saw_running, "execution never entered the running state")
assert(saw_completed, "execution never reached the completed state")

transcript.refresh()
local assistant_id = "session:" .. session_id .. ":execution:" .. prompt_result.execution_id .. ":assistant"
local node = assert(transcript.projection().nodes[assistant_id], "live transcript did not create the assistant node")
assert(node.text == expected, "live transcript changed the deterministic assistant response")
assert(node.final == true, "live transcript did not finalize the assistant node")

local buffer = transcript_buffer.ensure()
local rendered = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
assert(rendered:find(expected, 1, true) ~= nil, "rendered transcript does not contain the deterministic assistant response")

frontend.disconnect()

local reconnected = false
local reconnect_error = nil
frontend.connect(function(_, err)
  reconnect_error = err
  reconnected = true
end)
assert(vim.wait(10000, function()
  return reconnected
end, 10), "deterministic fixture reconnect timed out")
assert(reconnect_error == nil, vim.inspect(reconnect_error))

local resumed = false
local resume_error = nil
runtime.resume_session(session_id, function(snapshot, err)
  resume_error = err
  resumed = snapshot ~= nil
end)
assert(vim.wait(10000, function()
  return resumed or resume_error ~= nil
end, 10), "deterministic fixture session resume timed out")
assert(resume_error == nil, vim.inspect(resume_error))
assert(runtime.active_session() == session_id, "deterministic restart resumed the wrong session")

local recovered = assert(runtime.session_state().sessions[session_id], "restart lost the durable session projection")
local recovered_assistant = false
for _, entry in ipairs(recovered.updates or {}) do
  local change = entry.update or {}
  if normalized_kind(change.kind) == "message"
      and change.message ~= nil
      and normalized_kind(change.message.role) == "assistant"
      and text_content(change.message.content) == expected then
    recovered_assistant = true
    break
  end
end
assert(recovered_assistant, "restart lost the deterministic assistant message")

transcript.refresh()
local recovered_node = assert(
  transcript.projection().nodes[assistant_id],
  "restart did not reconstruct the assistant transcript node"
)
assert(recovered_node.text == expected, "restart changed the deterministic assistant response")
assert(recovered_node.final == true, "restart reconstructed the assistant node as unfinished")
local recovered_rendered = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
assert(
  recovered_rendered:find(expected, 1, true) ~= nil,
  "restart did not render the recovered deterministic assistant response"
)

local second_result = nil
local second_error = nil
runtime.prompt(session_id, {
  { kind = "text", text = marker .. " after restart" },
}, function(result, err)
  second_result = result
  second_error = err
end)
assert(vim.wait(10000, function()
  return second_result ~= nil or second_error ~= nil
end, 10), "post-restart deterministic prompt timed out")
assert(second_error == nil, vim.inspect(second_error))
assert(
  second_result.execution_id ~= prompt_result.execution_id,
  "post-restart prompt reused the previous durable execution id"
)

local post_restart_projection = assert(
  runtime.session_state().sessions[session_id],
  "post-restart prompt lost the session projection"
)
local second_delta = false
local second_completed = false
for _, entry in ipairs(post_restart_projection.updates or {}) do
  local change = entry.update or {}
  if normalized_kind(change.kind) == "textdelta"
      and change.execution_id == second_result.execution_id
      and change.text == expected then
    second_delta = true
  elseif normalized_kind(change.kind) == "execution"
      and change.execution_id == second_result.execution_id
      and change.update ~= nil
      and normalized_kind(change.update.kind) == "state"
      and normalized_kind(change.update.state) == "completed" then
    second_completed = true
  end
end
assert(second_delta, "post-restart model output did not reach the durable transcript")
assert(second_completed, "post-restart execution did not complete")

transcript.refresh()
local second_assistant_id =
  "session:" .. session_id .. ":execution:" .. second_result.execution_id .. ":assistant"
local second_node = assert(
  transcript.projection().nodes[second_assistant_id],
  "post-restart prompt did not create an assistant transcript node"
)
assert(second_node.text == expected, "post-restart transcript changed the deterministic response")
assert(second_node.final == true, "post-restart assistant node was not finalized")

frontend.disconnect()
print("phenix-ai.nvim deterministic model pipeline and restart passed")
