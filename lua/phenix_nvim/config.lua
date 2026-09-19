local M = {}

local defaults = {
  command = "phenix-acp",
  args = {},
  env = {},
  log_file = vim.fn.stdpath("state") .. "/phenix/phenix-ai.nvim.jsonl",
  auto_connect = false,
  poll_interval_ms = 25,
  poll_budget = 32,
  side = "right",
  width = 56,
  compose_height = 8,
}

local current = vim.deepcopy(defaults)

function M.setup(options)
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options or {})
  return M.get()
end

function M.get()
  return vim.deepcopy(current)
end

function M.runtime_env(config)
  local resolved = config or current
  local environment = vim.deepcopy(resolved.env or {})
  local log_file = resolved.log_file
  if log_file ~= false and log_file ~= nil then
    if type(log_file) ~= "string" or log_file == "" then
      error("phenix-ai.nvim log_file must be a non-empty path or false")
    end
    local explicit_log = environment.PHENIX_LOG ~= nil
      or environment.PHENIX_DEBUG_LOG ~= nil
      or vim.env.PHENIX_LOG ~= nil
      or vim.env.PHENIX_DEBUG_LOG ~= nil
    if not explicit_log then
      environment.PHENIX_LOG = "append:" .. log_file
    end
  end
  return environment
end

return M
