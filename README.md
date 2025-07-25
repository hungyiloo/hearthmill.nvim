# `</>` Hearthmill

Hand-crafted HTML navigation, manipulation and utilities for Neovim, powered by [tree-sitter](https://tree-sitter.github.io/tree-sitter/). 

> [!note] 
> Although I dogfood this plugin for work everyday, this is still in alpha as
> it's been developed against my personal workflow and coding environment,
> which may not correspond to yours. Any suggestions will be considered!

## 📜 Features

- Works with JSX/TSX, Angular templates, and anything else with a tree-sitter AST similar to HTML
- Roll your own keymaps to code how you like; pick and choose what you need and ignore what you don't
- Opinionated white space handling and text manipulation to keep things tidy and save you work
- Dot-repeatable operations wherever reasonable
- Manipulate HTML based on your existing understanding of elements/attributes/tags

| Operation                    | Elements | Attributes | Tags | What does this do?                                             |
| ---------------------------- | -------- | ---------- | ---- | -------------------------------------------------------------- |
| Select                       | ✔️        | ✔️          | ✔️    | Visually selects the node                                      |
| Select contents              | ✔️        | ✔️          | ✔️    | Visually selects the inner contents of a node                  |
| Go to beginning              | ✔️        | ✔️          | ✔️    | Navigates to the very start of the node                        |
| Go to end                    | ✔️        | ✔️          | ✔️    | Navigates to the very end of the node                          |
| Go to next                   | ✔️        | ✔️          | ✔️    | Navigates to the next node of that type                        |
| Go to previous               | ✔️        | ✔️          | ✔️    | Navigates to the previous node of that type                    |
| Go to parent element         | ✔️        |            |      | Navigates to the parent element                                |
| Delete                       | ✔️        | ✔️          | ✔️    | Deletes the node (tries to tidy up white space)                |
| Transpose forward            | ✔️        | ✔️          |      | Swaps a node with the next one of that type                    |
| Transpose backward           | ✔️        | ✔️          |      | Swaps a node with the previous one of that type                |
| Clone                        | ✔️        | ✔️          |      | Makes a copy of the node directly below                        |
| Break into lines             | ✔️        |            | ✔️    | Spreads the node contents onto multiple lines for readability  |
| Rename                       | ✔️        |            |      | Renames the start/end tags of an element                       |
| Wrap                         | ✔️        |            |      | Wraps an element with a new container element                  |
| Unwrap                       | ✔️        |            |      | Removes an element's start/end tags, leaving only its contents |
| Toggle self-closing element  | ✔️        |            |      | Converts between self-closing and regular element formats      |
| Add                          | ✔️        | ✔️          |      | Adds a new element or attribute                                |
| Hoist                        | ✔️        | ✔️          | ✔️    | Moves a node up one level in the hierarchy                     |


## 🔧 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
  return { 
    "hungyiloo/hearthmill.nvim" 

    -- Suggested keymaps (customise or omit this section as necessary)
    -- stylua: ignore
    keys = {
      -- Element operations
      { mode = { "n", "o", "x" }, "ghes", function() require("hearthmill").select("element") end, desc = "[e]lement [s]elect" },
      { mode = { "n", "o", "x" }, "ghec", function() require("hearthmill").select_contents("element") end, desc = "[e]lement select [c]ontents" },
      { mode = { "n", "o", "x" }, "gheb", function() require("hearthmill").goto_beginning("element") end, desc = "[e]lement [b]eginning" },
      { mode = { "n", "o", "x" }, "ghee", function() require("hearthmill").goto_end("element") end, desc = "[e]lement [e]nd" },
      { mode = { "n", "o", "x" }, "ghen", function() require("hearthmill").goto_next("element") end, desc = "[e]lement [n]ext" },
      { mode = { "n", "o", "x" }, "ghep", function() require("hearthmill").goto_prev("element") end, desc = "[e]lement [p]revious" },
      { mode = "n", "gheo", function() require("hearthmill").goto_parent_element() end, desc = "[e]lement [o]uter parent" },
      { mode = "n", "ghed", function() require("hearthmill").delete("element") end, desc = "[e]lement [d]elete" },
      { mode = "n", "ghet", function() require("hearthmill").transpose("element") end, desc = "[e]lement [t]ranspose" },
      { mode = "n", "gheT", function() require("hearthmill").transpose_backward("element") end, desc = "[e]lement [T]ranspose backwards" },
      { mode = "n", "gher", function() require("hearthmill").rename() end, desc = "[e]lement [r]ename" },
      { mode = { "n", "x" }, "ghew", function() require("hearthmill").wrap() end, desc = "[e]lement [w]rap" },
      { mode = "n", "gheu", function() require("hearthmill").unwrap() end, desc = "[e]lement [u]nwrap" },
      { mode = "n", "ghe=", function() require("hearthmill").clone("element") end, desc = "[e]lement clone [=]" },
      { mode = "n", "ghe<CR>", function() require("hearthmill").break_lines("element") end, desc = "[e]lement break lines [RET]" },
      { mode = "n", "ghes", function() require("hearthmill").toggle_self_closing_element() end, desc = "[e]lement toggle [s]elf-closing" },
      { mode = "n", "ghea", function() require("hearthmill").add("element") end, desc = "[e]lement [a]dd" },
      { mode = "n", "gheh", function() require("hearthmill").hoist("element") end, desc = "[e]lement [h]oist" },

      -- Attribute operations
      { mode = { "n", "o", "x" }, "ghas", function() require("hearthmill").select("attribute") end, desc = "[a]ttribute [s]elect" },
      { mode = { "n", "o", "x" }, "ghac", function() require("hearthmill").select_contents("attribute") end, desc = "[a]ttribute select [c]ontents" },
      { mode = { "n", "o", "x" }, "ghab", function() require("hearthmill").goto_beginning("attribute") end, desc = "[a]ttribute [b]eginning" },
      { mode = { "n", "o", "x" }, "ghae", function() require("hearthmill").goto_end("attribute") end, desc = "[a]ttribute [e]nd" },
      { mode = { "n", "o", "x" }, "ghan", function() require("hearthmill").goto_next("attribute") end, desc = "[a]ttribute [n]ext" },
      { mode = { "n", "o", "x" }, "ghap", function() require("hearthmill").goto_prev("attribute") end, desc = "[a]ttribute [p]revious" },
      { mode = "n", "ghad", function() require("hearthmill").delete("attribute") end, desc = "[a]ttribute [d]elete" },
      { mode = "n", "ghat", function() require("hearthmill").transpose("attribute") end, desc = "[a]ttribute [t]ranspose" },
      { mode = "n", "ghaT", function() require("hearthmill").transpose_backward("attribute") end, desc = "[a]ttribute [T]ranspose" },
      { mode = "n", "gha=", function() require("hearthmill").clone("attribute") end, desc = "[a]ttribute clone [=]" },
      { mode = "n", "ghaa", function() require("hearthmill").add("attribute") end, desc = "[a]ttribute [a]dd" },
      { mode = "n", "ghah", function() require("hearthmill").hoist("attribute") end, desc = "[a]ttribute [h]oist" },

      -- Tag operations
      { mode = { "n", "o", "x" }, "ghts", function() require("hearthmill").select("tag") end, desc = "[t]ag [s]elect" },
      { mode = { "n", "o", "x" }, "ghtc", function() require("hearthmill").select_contents("tag") end, desc = "[t]ag select [c]ontents" },
      { mode = { "n", "o", "x" }, "ghtb", function() require("hearthmill").goto_beginning("tag") end, desc = "[t]ag [b]eginning" },
      { mode = { "n", "o", "x" }, "ghte", function() require("hearthmill").goto_end("tag") end, desc = "[t]ag [e]nd" },
      { mode = { "n", "o", "x" }, "ghtn", function() require("hearthmill").goto_next("tag") end, desc = "[t]ag [n]ext" },
      { mode = { "n", "o", "x" }, "ghtp", function() require("hearthmill").goto_prev("tag") end, desc = "[t]ag [p]revious" },
      { mode = "n", "ghtd", function() require("hearthmill").delete("tag") end, desc = "[t]ag [d]elete" },
      { mode = "n", "ght<CR>", function() require("hearthmill").break_lines("tag") end, desc = "[t]ag break lines [RET]" },
      { mode = "n", "ghth", function() require("hearthmill").hoist("tag") end, desc = "[t]ag [h]oist" },

      -- Combined operations
      {
        mode = "n",
        "gh<CR>",
        function()
          require("hearthmill").break_lines("element")
          require("hearthmill").break_lines("tag")
        end,
        desc = "Break lines [RET]"
      },
    }
  }
```

## ⚙️ Configuration

Hearthmill can be configured to work with different tree-sitter node types. The default configuration supports HTML, JSX, and TSX:

```lua
require("hearthmill").setup({
  type_aliases_map = {
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
})
```

You can customise these mappings to work with other tree-sitter parsers or to add support for additional node types.

## 🎯 Usage Tips

- **Dot-repeat support**: Most operations support Vim's dot-repeat (`.`) functionality, making it easy to perform the same operation multiple times
- **Visual mode**: Many operations work in visual mode, allowing you to select content first and then operate on it
- **Smart whitespace handling**: Operations automatically handle indentation and whitespace to keep your code tidy
- **Hierarchical operations**: Use `hoist` to move elements up in the DOM hierarchy, or `goto_parent_element` to navigate upwards

## 🤝 Contributing

This plugin is still in alpha development. Contributions, bug reports, and feature requests are welcome! Please feel free to open issues or submit pull requests.

## 📄 License

MIT License - see the LICENSE file for details.
