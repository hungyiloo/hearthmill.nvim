local M = {}

M.type_aliases_map = {
  element = { "element", "jsx_element", "jsx_self_closing_element" },
  tag = {
    "start_tag",
    "end_tag",
    "self_closing_tag",
    "jsx_opening_element",
    "jsx_closing_element",
    "jsx_self_closing_element",
  },
  attribute = { "attribute", "jsx_attribute" },
  tag_name = { "tag_name", "identifier" },
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

local function get_cursor()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  return row - 1, col
end

---@param row integer
---@param col integer
local function set_cursor(row, col)
  vim.api.nvim_win_set_cursor(0, { row + 1, col })
end

---@param node TSNode
local function mark_node(node)
  local from_row, from_col = node:start()
  local to_row, to_col = node:end_()
  set_cursor(from_row, from_col)
  normal("v")
  set_cursor(to_row, to_col - 1)
end

---@param node TSNode
local function goto_node_start(node)
  local row, col = node:start()
  set_cursor(row, col)
end
---
---@param node TSNode
local function goto_node_end(node)
  local row, col = node:end_()
  set_cursor(row, col - 1)
end

---@param node TSNode
---@param new_text string[]
local function replace_node(node, new_text)
  local from_row, from_col = node:start()
  local to_row, to_col = node:end_()
  vim.api.nvim_buf_set_text(0, from_row, from_col, to_row, to_col, new_text)
end

---@param row integer
---@param col integer
---@param text string[]
local function insert_text_at_pos(row, col, text)
  vim.api.nvim_buf_set_text(0, row, col, row, col, text)
end

---@param node TSNode
local function delete_node(node)
  replace_node(node, { "" })
end

local function treesitter_reparse()
  vim.treesitter.get_parser():parse()
end

local function collapse_blank_spaces()
  -- collapse a single space before or after the cursor
  local _, cursor_col = get_cursor()
  local cursor_char = vim.api.nvim_get_current_line():sub(cursor_col + 1, cursor_col + 1)
  if cursor_char == " " then
    normal("x")
  else
    cursor_char = vim.api.nvim_get_current_line():sub(cursor_col, cursor_col)
    if cursor_char == " " then
      normal("X")
    end
  end
end

local function collapse_blank_lines()
  -- delete the line if it's blank
  vim.cmd([[silent! s/^\s*$\n//]])
  -- hide search highlights
  vim.cmd(":noh")
end

---@param type string
---@param row integer
---@param col integer
---@return TSNode|nil
local function node_at_pos(type, row, col)
  local node = vim.treesitter.get_node({
    bufnr = 0,
    -- unpack typing isn't supported in luals
    ---@diagnostic disable-next-line: assign-type-mismatch
    pos = { row, col },
  })
  while node and type and not node_is_type(node, type) do
    node = node:parent()
  end
  return node
end

---@param node TSNode
---@return TSNode|nil
local function first_child_of_type(node, type)
  for child in node:iter_children() do
    if node_is_type(child, type) then
      return child
    end
  end
end

---@param node TSNode
---@return TSNode[]
local function children_of_type(node, type)
  local results = {}
  for child in node:iter_children() do
    if node_is_type(child, type) then
      results[#results + 1] = child
    end
  end
  return results
end

---@param type string
---@return TSNode|nil
local function node_at_cursor(type)
  local row, col = get_cursor()
  return node_at_pos(type, row, col)
end

---@param node TSNode
---@param type string
---@return TSNode|nil
local function next_node(node, type)
  local next = node:next_sibling()
  while next and type and not node_is_type(next, type) do
    next = next:next_sibling()
  end
  return next
end

---@param node TSNode
---@param type string
---@return TSNode|nil
local function prev_node(node, type)
  local prev = node:prev_sibling()
  while prev and type and not node_is_type(prev, type) do
    prev = prev:prev_sibling()
  end
  return prev
end

---@param node TSNode
---@return string[]
local function node_to_string(node)
  local from_row, from_col = node:start()
  local to_row, to_col = node:end_()
  return vim.api.nvim_buf_get_text(0, from_row, from_col, to_row, to_col, {})
end

---@param str string|nil
local function is_whitespace_or_empty(str)
  if str == nil then
    return true
  end
  return str:match("^%s*$") ~= nil
end

M.__last_op = nil
M.__no_op = function() end
-- Make function f work with dot-repeat by wrapping it in operatorfunc magic
---@param f fun(is_dot_repeat: boolean|nil)
local function dot_repeatable(f)
  local is_dot_repeat = false
  M.__last_op = function()
    f(is_dot_repeat)
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

    is_dot_repeat = true
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
      collapse_blank_spaces()
      collapse_blank_lines()
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
      local node_text = node_to_string(node)
      local next_text = node_to_string(next)
      replace_node(next, node_text)
      replace_node(node, next_text)

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
      return
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
      return
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
        goto_node_start(end_tag)
        collapse_blank_lines()
      end
      if start_tag then
        delete_node(start_tag)
        goto_node_start(start_tag)
        collapse_blank_lines()
      end

      mark_node(element)
      normal("=")
    end
  end)
end

function M.rename()
  local initial_element = node_at_cursor("element")
  if not initial_element then
    return
  end
  local initial_tag = node_is_type(initial_element, "tag") and initial_element
    or first_child_of_type(initial_element, "tag")
  if not initial_tag then
    return
  end
  local initial_tag_name = first_child_of_type(initial_tag, "tag_name")
  if not initial_tag_name then
    return
  end

  vim.ui.input(
    {
      prompt = "Rename Element To: ",
      default = node_to_string(initial_tag_name)[1],
    },
    ---@param new_tag_name string|nil
    function(new_tag_name)
      if new_tag_name == nil then
        -- user cancelled input
        return
      end

      dot_repeatable(function()
        local element = node_at_cursor("element")
        if element then
          ---@type TSNode|nil
          local last_touched_node = nil

          local tags = children_of_type(element, "tag")
          if node_is_type(element, "tag") then
            tags[#tags + 1] = element
          end
          -- reverse order is important:
          -- allows editing without worrying about positions changing.
          for i = #tags, 1, -1 do
            local tag_name_node = first_child_of_type(tags[i], "tag_name")
            if tag_name_node then
              replace_node(tag_name_node, { new_tag_name })
              last_touched_node = tag_name_node
            end
          end

          if last_touched_node then
            goto_node_start(last_touched_node)
          end
        end
      end)
    end
  )
end

function M.wrap()
  local mode = vim.fn.mode()

  vim.ui.input(
    { prompt = "Wrap with Element: " },
    ---@param new_tag_name string|nil
    function(new_tag_name)
      if new_tag_name == nil then
        -- user cancelled input
        return
      end

      dot_repeatable(function(is_dot_repeat)
        local insert_new_lines = false
        ---@type number|nil
        local start_row = nil
        ---@type number|nil
        local start_col = nil
        ---@type number|nil
        local end_row = nil
        ---@type number|nil
        local end_col = nil
        ---@type string

        if is_dot_repeat and (mode == "v" or mode == "V") then
          vim.notify(
            "Dot repeating a wrap of a visual selection is not supported; falling back to wrapping the entire element at the cursor",
            vim.log.levels.WARN
          )
          mode = "n"
        end

        if mode == "v" or mode == "V" then
          _, start_row, start_col = unpack(vim.fn.getpos("'<"))
          _, end_row, end_col = unpack(vim.fn.getpos("'>"))
          start_col = start_col - 1
          start_row = start_row - 1
          end_col = math.min(end_col, string.len(vim.fn.getline(end_row)))
          end_row = end_row - 1
          insert_new_lines = mode == "V"
        else
          local element = node_at_cursor("element")
          if element then
            start_row, start_col = element:start()
            end_row, end_col = element:end_()

            -- check if element doesn't share lines with any other content.
            -- if it does, wrap without using new lines.
            ---@type string
            local start_line = vim.api.nvim_buf_get_lines(0, start_row, start_row + 1, false)[1]
            ---@type string
            local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1]
            local text_before_element = start_line:sub(0, start_col)
            local text_after_element = end_line:sub(end_col + 1)
            insert_new_lines = is_whitespace_or_empty(text_before_element)
              and is_whitespace_or_empty(text_after_element)
          end
        end

        if start_row == nil or start_col == nil or end_row == nil or end_col == nil then
          return
        end

        local new_start_tag_text = string.format("<%s>", new_tag_name)
        local new_end_tag_text = string.format("</%s>", new_tag_name)

        if insert_new_lines then
          local indentation = string.rep(" ", vim.fn.indent(start_row))
          insert_text_at_pos(end_row, end_col, { "", indentation .. new_end_tag_text })
          insert_text_at_pos(start_row, start_col, { new_start_tag_text, indentation })
          set_cursor(start_row, start_col)
          treesitter_reparse()
          local new_element = node_at_cursor("element")
          if new_element then
            mark_node(new_element)
            normal("=")
          end
        else
          insert_text_at_pos(end_row, end_col, { new_end_tag_text })
          insert_text_at_pos(start_row, start_col, { new_start_tag_text })
        end
      end)
    end
  )
end

return M
