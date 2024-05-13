local M = {}

local parsers = require("nvim-treesitter.parsers")
local ts_utils = require("nvim-treesitter.ts_utils")

local get_node_text = function(node)
  return vim.treesitter.get_node_text(node, 0)
end

local get_string_content = function(node)
  for _, child in ipairs(ts_utils.get_named_children(node)) do
    if child:type() == "string_content" then
      return get_node_text(child)
    end
  end

  return ""
end

local starts_with_number = function(str)
  return str:match("^%d")
end

local contains_special_characters = function(str)
  return str:match("[^a-zA-Z0-9_]")
end

-- plagiarized from https://github.com/cuducos/yaml.nvim/blob/main/lua/yaml_nvim/init.lua
local function get_keys(root)
  local keys = {}
  for node, name in root:iter_children() do
    if name == "key" then
      table.insert(keys, node)
    end

    if node:child_count() > 0 then
      for _, child in pairs(get_keys(node)) do
        table.insert(keys, child)
      end
    end
  end
  return keys
end

-- plagiarized from https://github.com/cuducos/yaml.nvim/blob/main/lua/yaml_nvim/init.lua
M.all_keys = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_buf_get_option(bufnr, "ft")
  local tree = vim.treesitter.get_parser(bufnr, ft):parse()[1]
  local root = tree:root()
  return get_keys(root)
end

-- plagiarized from https://github.com/cuducos/yaml.nvim/blob/main/lua/yaml_nvim/init.lua
M.get_key_relevant_to_cursor = function()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local previous_node = nil

  for _, node in pairs(M.all_keys()) do
    local node_line, _ = node:start()
    node_line = node_line + 1

    if cursor_line == node_line then
      return node
    end

    if cursor_line < node_line then
      return previous_node
    end

    previous_node = node
  end
end

M.get = function()
  if not parsers.has_parser() then
    return ""
  end

  local current_node = M.get_key_relevant_to_cursor()
  if not current_node then
    return ""
  end

  local accessors = {}
  local node = current_node

  while node do
    local accessor = ""

    if node:type() == "pair" then
      local key_node = unpack(node:field("key"))
      local key = get_string_content(key_node)

      if key and starts_with_number(key) or contains_special_characters(key) then
        accessor = string.format('["%s"]', key)
      else
        accessor = string.format("%s", key)
      end
    end

    if node:type() == "array" then
      accessor = "[]"

      for i, child in ipairs(ts_utils.get_named_children(node)) do
        if ts_utils.is_parent(child, current_node) then
          accessor = string.format("[%d]", i - 1)
        end
      end
    end

    if accessor ~= "" then
      table.insert(accessors, 1, accessor)
    end

    node = node:parent()
  end

  if #accessors == 0 then
    return "."
  end

  local path = ""

  for i, accessor in ipairs(accessors) do
    if i == 1 then
      path = path .. "." .. accessor
    elseif vim.startswith(accessor, "[") then
      path = path .. accessor
    else
      path = path .. "." .. accessor
    end
  end

  return path
end

return M
