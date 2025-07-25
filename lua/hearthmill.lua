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
  start_tag = { "start_tag", "jsx_opening_element" },
  end_tag = { "end_tag", "jsx_closing_element" },
  attribute = { "attribute", "jsx_attribute" },
  tag_name = { "tag_name", "identifier", "member_expression" },
  angled_brackets = { "<", ">" },
  content = { "text", "interpolation" }
}

function M.setup(opts)
  opts = opts or {}
  M.type_aliases_map = opts.type_aliases_map or M.type_aliases_map
end

-- TODO: Refactor internal methods to other files
---@param keystrokes string
local function normal(keystrokes)
  vim.cmd("normal! " .. keystrokes)
end

---@param str string|nil
local function is_whitespace_or_empty(str)
  if str == nil then
    return true
  end
  return str:match("^%s*$") ~= nil
end

---@param lnum integer
local function line_indentation(lnum)
  -- remember: vim API line numbers are 1-indexed
  return string.rep(" ", vim.fn.indent(lnum + 1))
end

---@param node TSNode
---@return string[]
local function node_to_string(node)
  local from_row, from_col = node:start()
  local to_row, to_col = node:end_()
  return vim.api.nvim_buf_get_text(0, from_row, from_col, to_row, to_col, {})
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
  -- convert from 1-indexed rows to 0-indexed, for consistency with treesitter node positions
  return row - 1, col
end

---@param row integer
---@param col integer
local function set_cursor(row, col)
  -- convert from 0-indexed treesitter rows to 1-indexed for vim API.
  -- also add safety clamping to all the values.
  row = math.max(1, math.min(row + 1, vim.api.nvim_buf_line_count(0)))
  col = math.max(0, math.min(col, string.len(vim.fn.getline(row)) - 1))
  vim.api.nvim_win_set_cursor(0, { row, col })
end

---@param from_row integer
---@param from_col integer
---@param to_row integer
---@param to_col integer
local function mark_range(from_row, from_col, to_row, to_col)
  local existing_virtualedit = vim.o.virtualedit
  vim.o.virtualedit = "onemore"
  set_cursor(from_row, from_col)
  if vim.fn.mode() ~= "v" then
    normal("v")
  else
    normal("o")
  end
  set_cursor(to_row, to_col)
  vim.o.virtualedit = existing_virtualedit
end

---@param node TSNode
local function mark_node(node)
  local from_row, from_col = node:start()
  local to_row, to_col = node:end_()
  mark_range(from_row, from_col, to_row, to_col - 1)
end

---@param node TSNode
local function goto_node_start(node)
  local row, col = node:start()
  set_cursor(row, col)
end

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
  local node_text = table.concat(node_to_string(node), "\n")
  vim.fn.setreg("*", node_text)
  vim.fn.setreg("+", node_text)
  vim.fn.setreg("", node_text)
  replace_node(node, { "" })
end

---@param node TSNode
local function occupies_own_start_line(node)
  local start_row, start_col = node:start()
  local start_line = vim.api.nvim_buf_get_lines(0, start_row, start_row + 1, false)[1]
  local text_before_element = start_line:sub(0, start_col)
  return is_whitespace_or_empty(text_before_element)
end

---@param node TSNode
local function occupies_own_end_line(node)
  local end_row, end_col = node:end_()
  local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1]
  local text_after_element = end_line:sub(end_col + 1)
  return is_whitespace_or_empty(text_after_element)
end

-- Returns true if the node occupies the entirety of its own lines,
-- or false if it shares any of its lines with other nodes
---@param node TSNode
local function occupies_own_lines(node)
  return occupies_own_start_line(node) and occupies_own_end_line(node)
end

local function treesitter_reparse()
  vim.treesitter.get_parser():parse()
end

-- Collapses a single space before or after the cursor.
-- Useful to keep things tidy when removing elements or attributes that are
-- adjacent to other content.
local function collapse_blank_spaces()
  local _, cursor_col = get_cursor()
  local cursor_char = vim.api.nvim_get_current_line():sub(cursor_col + 1, cursor_col + 1)
  if cursor_char == " " then
    normal('"_x')
  else
    cursor_char = vim.api.nvim_get_current_line():sub(cursor_col, cursor_col)
    if cursor_char == " " then
      normal('"_X')
    end
  end
end

-- Deletes the line at the cursor if it's only whitespace.
-- Useful when removing elements or attributes don't share lines with other
-- content, which means the remaining newline can be removed.
local function collapse_blank_line()
  -- delete the line if it's blank
  vim.cmd([[silent! s/^\s*$\n//]])
  -- hide search highlights
  vim.cmd("noh")
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
---@param type string
---@return TSNode|nil
local function first_child_of_type(node, type)
  for child in node:iter_children() do
    if node_is_type(child, type) then
      return child
    end
  end
end

---@param node TSNode
---@param type string
---@return TSNode|nil
local function first_ancestor_of_type(node, type)
  local ancestor = node:parent()
  while ancestor and type and not node_is_type(ancestor, type) do
    ancestor = ancestor:parent()
  end
  return ancestor
end

---@param node TSNode
---@param type string
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
---@param type string|nil
---@return TSNode|nil
local function next_node(node, type)
  local next = node:next_sibling()
  if not type then
    return next
  end
  while next and type and not node_is_type(next, type) do
    next = next:next_sibling()
  end
  return next
end

---@param node TSNode
---@param type string|nil
---@return TSNode|nil
local function prev_node(node, type)
  local prev = node:prev_sibling()
  if not type then
    return prev
  end
  while prev and type and not node_is_type(prev, type) do
    prev = prev:prev_sibling()
  end
  return prev
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
  M.__last_op()
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
function M.select_contents(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if not node then
      return
    end

    if type == "element" then
      local start_tag = first_child_of_type(node, "start_tag")
      local end_tag = first_child_of_type(node, "end_tag")
      if not start_tag or not end_tag then
        return
      end
      local node_after_start_tag = next_node(start_tag)
      local node_before_end_tag = prev_node(end_tag)
      if not node_after_start_tag or not node_before_end_tag then
        return
      end

      local from_row, from_col = start_tag:end_()
      local to_row, to_col = end_tag:start()

      -- These shenanigans are to select all whitespace, including linebreaks,
      -- so that if the contents is deleted, we're left with two adjacent
      -- start/end tags. There could be a much more elegant way to do this, but
      -- so far it's eluded me.
      local row_node_after_start_tag = node_after_start_tag:start()
      local row_node_before_end_tag = node_before_end_tag:end_()
      mark_node(node)
      set_cursor(to_row, to_col)
      if row_node_before_end_tag < to_row and to_col == 0 then
        normal("k$")
      else
        normal("h")
      end
      normal("o")
      set_cursor(from_row, from_col)
      if row_node_after_start_tag > from_row then
        normal("l")
      end
      normal("o")
    elseif type == "attribute" then
      local second_child = node:child(2)
      if not second_child then
        return
      end
      mark_node(second_child)
    elseif type == "tag" then
      local tag_name = first_child_of_type(node, "tag_name")
      if not tag_name then
        return
      end
      mark_node(tag_name)
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
      collapse_blank_line()

      -- format the line that we're on to tidy things up, best effort
      normal("==")
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
function M.transpose_backward(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if not node then
      return
    end
    local prev = prev_node(node, type)
    if node and prev then
      local node_text = node_to_string(node)
      local prev_text = node_to_string(prev)
      replace_node(node, prev_text)
      replace_node(prev, node_text)

      -- set the cursor position at a sane position, best effort
      goto_node_start(prev)
    end
  end)
end

---@param type string
function M.goto_beginning(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if not node then
      return
    end

    -- If already at the start of an element, cleverly go to the start of the
    -- *previous* element. This makes selecting multiple siblings much easier.
    local cursor_row, cursor_col = get_cursor()
    local node_row, node_col = node:start()
    if cursor_row == node_row and cursor_col == node_col then
      node = prev_node(node, type)
    end
    if not node then
      return
    end

    goto_node_start(node)
  end)
end

---@param type string
function M.goto_end(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if not node then
      return
    end

    -- If already at the end of an element, cleverly go to the end of the
    -- *next* element. This makes selecting multiple siblings much easier.
    local cursor_row, cursor_col = get_cursor()
    local node_row, node_col = node:end_()
    if cursor_row == node_row and cursor_col == node_col - 1 then
      node = next_node(node, type)
    end
    if not node then
      return
    end

    goto_node_end(node)
  end)
end

---@param type string
function M.goto_next(type)
  dot_repeatable(function()
    local cursor_row, cursor_col = get_cursor()
    local node = node_at_cursor(type)

    if node then
      -- If we're on a node of the target type, go to the next one
      local next = next_node(node, type)
      if next then
        goto_node_start(next)
      end
    else
      -- If we're not on a node of the target type, find the first one after the cursor
      local root = vim.treesitter.get_parser():parse()[1]:root()

      local function find_next_node_of_type(current_node, target_type, after_row, after_col)
        if node_is_type(current_node, target_type) then
          local node_row, node_col = current_node:start()
          if node_row > after_row or (node_row == after_row and node_col > after_col) then
            return current_node
          end
        end

        for child in current_node:iter_children() do
          local result = find_next_node_of_type(child, target_type, after_row, after_col)
          if result then
            return result
          end
        end

        return nil
      end

      local next_node_found = find_next_node_of_type(root, type, cursor_row, cursor_col)
      if next_node_found then
        goto_node_start(next_node_found)
      end
    end
  end)
end

function M.goto_parent_element()
  dot_repeatable(function()
    local node = node_at_cursor("element")
    if not node then
      return
    end
    local outer = first_ancestor_of_type(node, "element")
    if outer then
      goto_node_start(outer)
    end
  end)
end

---@param type string
function M.goto_prev(type)
  dot_repeatable(function()
    local cursor_row, cursor_col = get_cursor()
    local node = node_at_cursor(type)

    if node then
      -- If we're on a node of the target type, go to the previous one
      local prev = prev_node(node, type)
      if prev then
        goto_node_start(prev)
      end
    else
      -- If we're not on a node of the target type, find the last one before the cursor
      local root = vim.treesitter.get_parser():parse()[1]:root()
      local found_node = nil

      local function find_prev_node_of_type(current_node, target_type, before_row, before_col)
        if node_is_type(current_node, target_type) then
          local node_row, node_col = current_node:start()
          if node_row < before_row or (node_row == before_row and node_col < before_col) then
            found_node = current_node
          end
        end

        for child in current_node:iter_children() do
          find_prev_node_of_type(child, target_type, before_row, before_col)
        end
      end

      find_prev_node_of_type(root, type, cursor_row, cursor_col)
      if found_node then
        goto_node_start(found_node)
      end
    end
  end)
end

function M.unwrap()
  dot_repeatable(function()
    local element = node_at_cursor("element")
    if element then
      local start_tag = first_child_of_type(element, "start_tag")
      local end_tag = first_child_of_type(element, "end_tag")

      if end_tag then
        delete_node(end_tag)
        goto_node_start(end_tag)
        collapse_blank_line()
      end
      if start_tag then
        delete_node(start_tag)
        goto_node_start(start_tag)
        collapse_blank_line()
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
            insert_new_lines = occupies_own_lines(element)
          end
        end

        if start_row == nil or start_col == nil or end_row == nil or end_col == nil then
          return
        end

        local new_start_tag_text = string.format("<%s>", new_tag_name)
        local new_end_tag_text = string.format("</%s>", new_tag_name)

        if insert_new_lines then
          local indentation = line_indentation(start_row)
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

---@param type string
function M.clone(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if not node then
      return
    end
    local insert_new_lines = occupies_own_lines(node)
    local row, col = node:end_()
    local text_to_insert = node_to_string(node)
    if insert_new_lines then
      table.insert(text_to_insert, 1, "")
      text_to_insert[2] = line_indentation(row) .. text_to_insert[2]
    else
      -- add a space when cloning adjacently; this seems appropriate in the majority of cases
      text_to_insert[1] = " " .. text_to_insert[1]
    end
    insert_text_at_pos(row, col, text_to_insert)

    treesitter_reparse()
    node = node_at_cursor(type)
    local cloned_node = node and next_node(node)
    if cloned_node then
      goto_node_start(cloned_node)
    end
  end)
end

---@param type string
function M.break_lines(type)
  dot_repeatable(function()
    local node = node_at_cursor(type)
    if not node then
      return
    end
    local child_count = node:child_count()
    for i = child_count, 1, -1 do
      local child = node:child(i - 1)
      if child and not node_is_type(child, "content") and not node_is_type(child, "tag_name") and not node_is_type(child, "angled_brackets") then
        if (i == child_count or i == 1) and not occupies_own_end_line(child) then
          local end_row, end_col = child:end_()
          insert_text_at_pos(end_row, end_col, { "", line_indentation(end_row) })
        end
        if not occupies_own_start_line(child) then
          local start_row, start_col = child:start()
          insert_text_at_pos(start_row, start_col, { "", line_indentation(start_row) })
        end
      end
    end

    treesitter_reparse()
    node = node_at_cursor(type)
    if node then
      -- clean up trailing white space and blank lines, best effort
      mark_node(node)
      normal("v")
      vim.cmd([[silent! '<,'>s/\s\+$//]])
      vim.cmd([[silent! '<,'>s/\n\n/\r/g]])
      vim.cmd("noh")

      -- format nicely, best effort
      mark_node(node)
      normal("=")
    end
  end)
end

function M.toggle_self_closing_element()
  dot_repeatable(function()
    local element = node_at_cursor("element")
    if not element then
      return
    end

    local tag = first_child_of_type(element, "tag")

    -- Check if it's already a self-closing element
    if node_is_type(element, "jsx_self_closing_element") or (tag and node_is_type(tag, "self_closing_tag")) then
      -- Convert self-closing to regular element
      local element_text = table.concat(node_to_string(element), "\n")

      -- Extract tag name and attributes from self-closing element
      local tag_name_match = element_text:match("<([%w%-:]+)")
      local attributes_match = element_text:match("<[%w%-:]+%s*(.-)%s*/?%s*>")

      if not tag_name_match then
        return
      end

      -- Build new element text
      local start_tag = "<" .. tag_name_match
      if attributes_match and attributes_match:match("%S") then
        start_tag = start_tag .. " " .. attributes_match:gsub("/%s*$", "")
      end
      start_tag = start_tag .. ">"

      local end_tag = "</" .. tag_name_match .. ">"
      local new_element_text = { start_tag .. end_tag }

      replace_node(element, new_element_text)

      -- Position cursor between the tags
      treesitter_reparse()
      local new_element = node_at_cursor("element")
      if new_element then
        local start_tag_node = first_child_of_type(new_element, "start_tag")
        if start_tag_node then
          local _, end_col = start_tag_node:end_()
          local row, _ = start_tag_node:start()
          set_cursor(row, end_col)
        end
      end
    else
      -- Convert regular element to self-closing
      local start_tag = first_child_of_type(element, "start_tag")

      if not start_tag then
        return
      end

      -- Get start tag content and modify it to be self-closing
      local start_tag_text = table.concat(node_to_string(start_tag), "\n")
      local self_closing_text = start_tag_text:gsub(">%s*$", "/>")

      replace_node(element, { self_closing_text })

      -- Position cursor at the end of the new self-closing tag
      treesitter_reparse()
      local new_element = node_at_cursor("element")
      if new_element then
        goto_node_end(new_element)
      end
    end
  end)
end

---@param type string
function M.add(type)
  if type == "attribute" then
    local element = node_at_cursor("element")
    if not element then
      vim.notify("No element found at cursor", vim.log.levels.WARN)
      return
    end

    local start_tag = first_child_of_type(element, "start_tag")
    if not start_tag then
      vim.notify("No start tag found", vim.log.levels.WARN)
      return
    end

    vim.ui.input(
      { prompt = "Attribute name: " },
      ---@param attr_name string|nil
      function(attr_name)
        if attr_name == nil or attr_name == "" then
          return
        end

        vim.ui.input(
          { prompt = "Attribute value (optional): " },
          ---@param attr_value string|nil
          function(attr_value)
            dot_repeatable(function()
              local current_element = node_at_cursor("element")
              if not current_element then
                return
              end

              local current_start_tag = first_child_of_type(current_element, "start_tag")
              if not current_start_tag then
                return
              end

              -- Find the position just before the closing >
              local insert_row, insert_col = current_start_tag:end_()
              insert_col = insert_col - 1 -- Position before the >

              -- Build attribute text
              local attr_text = " " .. attr_name
              if attr_value and attr_value ~= "" then
                -- We don't wrap the attr_value with double quotes; this is the user's responsibility.
                -- Reason: JSX attribute values sometimes need enclosing with curly braces instead of quotes.
                attr_text = attr_text .. '=' .. attr_value .. ''
              end

              insert_text_at_pos(insert_row, insert_col, { attr_text })

              -- Position cursor at the end of the inserted attribute
              set_cursor(insert_row, insert_col + string.len(attr_text) - 1)
            end)
          end
        )
      end
    )
  elseif type == "element" then
    vim.ui.input(
      { prompt = "Element name: " },
      ---@param element_name string|nil
      function(element_name)
        if element_name == nil or element_name == "" then
          return
        end

        dot_repeatable(function()
          local cursor_row, cursor_col = get_cursor()
          local start_tag = "<" .. element_name .. ">"
          local end_tag = "</" .. element_name .. ">"

          insert_text_at_pos(cursor_row, cursor_col, { start_tag .. end_tag })

          -- Position cursor between the tags
          set_cursor(cursor_row, cursor_col + string.len(start_tag))
        end)
      end
    )
  end
end

---@param type string
function M.hoist(type)
  dot_repeatable(function()
    if type == "element" then
      local element = node_at_cursor("element")
      if not element then
        return
      end

      local parent_element = first_ancestor_of_type(element, "element")
      if not parent_element then
        return
      end

      -- Get the element text before we delete it
      local element_text = node_to_string(element)
      local parent_element_occupies_own_lines = occupies_own_lines(parent_element)

      -- Delete the current element
      delete_node(element)
      collapse_blank_spaces()
      collapse_blank_line()

      -- Insert the element before the parent element
      local parent_start_row, parent_start_col = parent_element:start()

      if parent_element_occupies_own_lines then
        local parent_indentation = line_indentation(parent_start_row)
        table.insert(element_text, #element_text + 1, parent_indentation .. "")
      else
        element_text[1] = element_text[1] .. " "
      end

      insert_text_at_pos(parent_start_row, parent_start_col, element_text)

      -- Position cursor at the hoisted element
      treesitter_reparse()
      local hoisted_element = node_at_pos("element", parent_start_row, parent_start_col)
      if hoisted_element then
        goto_node_start(hoisted_element)
        -- format nicely, best effort
        mark_node(hoisted_element)
        normal("=")
      end

    elseif type == "tag" then
      local element = node_at_cursor("element")
      if not element then
        return
      end

      local parent_element = first_ancestor_of_type(element, "element")
      if not parent_element then
        return
      end
      local parent_start_row, parent_start_col = parent_element:start()

      -- Get the tag information before unwrapping
      local start_tag = first_child_of_type(element, "start_tag")
      local end_tag = first_child_of_type(element, "end_tag")

      if not start_tag then
        return
      end

      local tag_name_node = first_child_of_type(start_tag, "tag_name")
      if not tag_name_node then
        return
      end

      -- Unwrap the current element
      local end_tag_text = {}
      local start_tag_text = {}
      if end_tag then
        end_tag_text = node_to_string(end_tag)
        delete_node(end_tag)
        goto_node_start(end_tag)
        collapse_blank_line()
      end
      if start_tag then
        start_tag_text = node_to_string(start_tag)
        delete_node(start_tag)
        goto_node_start(start_tag)
        collapse_blank_line()
      end

      treesitter_reparse()

      -- Now wrap the parent element with the saved tags
      local updated_parent = node_at_pos("element", parent_start_row, parent_start_col)
      if not updated_parent then
        return
      end

      local parent_end_row, parent_end_col = updated_parent:end_()
      local parent_occupies_own_lines = occupies_own_lines(updated_parent)

      if parent_occupies_own_lines then
        local parent_indentation = line_indentation(parent_start_row)
        table.insert(start_tag_text, #start_tag_text + 1, parent_indentation)
        end_tag_text[1] = parent_indentation .. end_tag_text[1]
        table.insert(end_tag_text, 1, "")
        insert_text_at_pos(parent_end_row, parent_end_col, end_tag_text)
        insert_text_at_pos(parent_start_row, parent_start_col, start_tag_text)

        treesitter_reparse()
        local new_element = node_at_pos("element", parent_start_row, parent_start_col)
        if new_element then
          mark_node(new_element)
          normal("=")
        end
      else
        insert_text_at_pos(parent_end_row, parent_end_col, end_tag_text)
        insert_text_at_pos(parent_start_row, parent_start_col, start_tag_text)
      end

    elseif type == "attribute" then
      local attribute = node_at_cursor("attribute")
      if not attribute then
        return
      end

      local current_element = first_ancestor_of_type(attribute, "element")
      if not current_element then
        return
      end

      local parent_element = first_ancestor_of_type(current_element, "element")
      if not parent_element then
        return
      end
      local parent_start_row, parent_start_col = parent_element:start()

      local parent_start_tag = first_child_of_type(parent_element, "start_tag")
      if not parent_start_tag then
        return
      end

      -- Get the attribute text before deleting it
      local attribute_text = node_to_string(attribute)

      -- Delete the attribute from current element
      delete_node(attribute)
      collapse_blank_spaces()
      collapse_blank_line()

      treesitter_reparse()

      -- Find the updated parent start tag and insert the attribute
      local updated_parent = node_at_pos("element", parent_start_row, parent_start_col)
      if not updated_parent then
        return
      end

      local updated_parent_start_tag = first_child_of_type(updated_parent, "start_tag")
      if not updated_parent_start_tag then
        return
      end

      -- Insert attribute before the closing > of parent start tag
      local insert_row, insert_col = updated_parent_start_tag:end_()
      insert_col = insert_col - 1 -- Position before the >

      -- Handle multi-line attributes properly
      local attr_text_to_insert = {}
      if #attribute_text == 1 then
        -- Single line attribute
        attr_text_to_insert = { " " .. attribute_text[1] }
      else
        -- Multi-line attribute - preserve the line structure
        attr_text_to_insert[1] = " " .. attribute_text[1]
        for i = 2, #attribute_text do
          attr_text_to_insert[i] = attribute_text[i]
        end
      end
      
      insert_text_at_pos(insert_row, insert_col, attr_text_to_insert)

      -- Position cursor at the moved attribute
      local total_length = 0
      for _, line in ipairs(attr_text_to_insert) do
        total_length = total_length + string.len(line)
      end
      if #attr_text_to_insert == 1 then
        set_cursor(insert_row, insert_col + total_length - 1)
      else
        set_cursor(insert_row + #attr_text_to_insert - 1, string.len(attr_text_to_insert[#attr_text_to_insert]) - 1)
      end
    end
  end)
end

-- TODO: new operation: selection expand and contract?
-- TODO: new operation: insert html entity/character reference (see ./data/entities.json)
-- TODO: write tests (try https://github.com/echasnovski/mini.test)

return M
