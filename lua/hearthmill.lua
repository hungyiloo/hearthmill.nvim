local M = {}

M.type_aliases_map = {
  tag = { "start_tag", "end_tag", "self_closing_tag" },
}

function M.setup(opts)
  opts = opts or {}
  M.type_aliases_map = opts.type_aliases_map or M.type_aliases_map
end

---@param keystrokes string
local function normal(keystrokes)
  vim.cmd("normal! " .. keystrokes)
end

---@param node TSNode
local function node_is_type(node, target_type)
  local matching_types = M.type_aliases_map[target_type] or { target_type }
  local node_type = node:type()
  for _, matching_type in ipairs(matching_types) do
    if matching_type == node_type then
      return true
    end
  end
  return false
end

---@param node TSNode
---@param show_selection (nil|true|false|"linewise")
local function mark_node(node, show_selection)
  local r1, c1 = node:start()
  local r2, c2 = node:end_()
  vim.fn.setpos("'<", { 0, r1 + 1, c1 + 1, 0 })
  vim.fn.setpos("'>", { 0, r2 + 1, c2, 0 })
  if show_selection == "linewise" then
    normal("'<V'>")
  elseif show_selection == nil or show_selection == true then
    normal("`<v`>")
  end
end

local function goto_pos(row, col)
  vim.fn.setpos(".", { 0, row + 1, col + 1, 0 })
end

---@param node TSNode
local function goto_node_start(node)
  local row, col = node:start()
  goto_pos(row, col)
end
---
---@param node TSNode
local function goto_node_end(node)
  local row, col = node:end_()
  goto_pos(row, col - 1)
end

---@param node TSNode
local function delete_node(node)
  mark_node(node)
  normal("d")
end

local function treesitter_reparse()
  vim.treesitter.get_parser():parse()
end

local function delete_blanks()
  -- collapse a single spaces before or after the cursor
  local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
  local cursor_char = vim.api.nvim_get_current_line():sub(cursor_col+1, cursor_col+1)
  if cursor_char == " " then
    normal("x")
  else
    cursor_char = vim.api.nvim_get_current_line():sub(cursor_col, cursor_col)
    if cursor_char == " " then
      normal("X")
    end
  end
  -- delete the line if it's blank
  vim.cmd([[silent! s/^\s*$\n//]])
  -- hide search highlights
  vim.cmd(":noh")
end

---@param type string
---@param row (nil|integer)
---@param col (nil|integer)
---@return (TSNode|nil)
local function node_at_pos(type, row, col)
  local node = vim.treesitter.get_node({
    bufnr = 0,
    -- unpack typing isn't supported in luals
    ---@diagnostic disable-next-line: assign-type-mismatch
    pos = row ~= nil and col ~= nil and unpack({ row, col }) or nil,
  })
  while node and type and not node_is_type(node, type) do
    node = node:parent()
  end
  return node
end

---@param node TSNode
local function first_child_of_type(node, type)
  for child in node:iter_children() do
    if node_is_type(child, type) then
      return child
    end
  end
end

---@param type string
---@return (TSNode|nil)
local function node_at_cursor(type)
  local _, row, col = vim.fn.getcurpos(0)
  return node_at_pos(type, row, col)
end

---@param node TSNode
---@param type string
---@return (TSNode|nil)
local function next_node(node, type)
  local n = node:next_sibling()
  while n and type and not node_is_type(n, type) do
    n = n:next_sibling()
  end
  return n
end

---@param node TSNode
---@param type string
---@return (TSNode|nil)
local function prev_node(node, type)
  local n = node:prev_sibling()
  while n and type and not node_is_type(n, type) do
    n = n:prev_sibling()
  end
  return n
end

M.__last_op = nil
M.__no_op = function() end
-- Make function f work with dot-repeat by wrapping it in operatorfunc magic
---@param f function
local function dot_repeatable(f)
  M.__last_op = function()
    f()

    -- save visual state in case we need to restore it after the NOOP hack
    local restore_visual_mode = string.lower(vim.fn.mode()) == "v"

    -- This little dance is required so that dot-repeat won't pick up any text
    -- operations in the last text edit and try to incorrectly dot-repeat that
    -- instead. We get around that by ensuring g@l is the last thing neovim
    -- executes, but we also don't want to do the actual hearthmill op twice
    -- (!), so we first set operatorfunc to a NOOP function before we call g@l
    -- as a "last word" to neovim, then set operatorfunc back to the last
    -- hearthmill op for the next dot-repeat.
    vim.go.operatorfunc = "v:lua.require'hearthmill'.__no_op"
    normal("g@l")
    vim.go.operatorfunc = "v:lua.require'hearthmill'.__last_op"

    if restore_visual_mode then
      normal("gv")
    end
  end
  vim.go.operatorfunc = "v:lua.require'hearthmill'.__last_op"
  normal("g@l")
end

---@param type string
function M.select(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if node then
      mark_node(node)
    end
  end)
end

---@param type string
function M.delete(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if node then
      delete_node(node)
      delete_blanks()
    end
  end)
end

---@param type string
function M.transpose(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if not node then
      return
    end
    local next = next_node(node, type)
    if node and next then
      mark_node(node)
      normal("y")
      mark_node(next)
      normal("p")
      mark_node(node)
      normal("p")

      -- set the cursor position at a sane position, best effort
      treesitter_reparse()
      node = node_at_cursor(type)
      if not node then
        return
      end
      next = next_node(node, type)
      if not next then
        return
      end
      goto_node_start(next)
    end
  end)
end

---@param type string
function M.goto_beginning(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if node then
      goto_node_start(node)
    end
  end)
end

---@param type string
function M.goto_end(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if node then
      goto_node_end(node)
    end
  end)
end

---@param type string
function M.goto_next(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if not node then
      return nil
    end
    local next = next_node(node, type)
    if next then
      goto_node_start(next)
    end
  end)
end

---@param type string
function M.goto_prev(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if not node then
      return nil
    end
    local prev = prev_node(node, type)
    if prev then
      goto_node_start(prev)
    end
  end)
end

function M.vanish()
  dot_repeatable(function()
    local element = node_at_cursor("element")
    if element then
      local start_tag = first_child_of_type(element, "start_tag")
      local end_tag = first_child_of_type(element, "end_tag")
      if end_tag then
        delete_node(end_tag)
      end
      if start_tag then
        delete_node(start_tag)
      end
    end
  end)
end

return M
