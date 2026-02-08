-- UI configuration (theme, statusline, file explorer, etc.)

-- Theme
require('onedark').setup {
	style = 'warmer'
}
require('onedark').load()

-- Statusline (lualine)
require('lualine').setup {
	options = {
		icons_enabled = true,
		theme = 'onedark',
		component_separators = '|',
		section_separators = '',
	},
}

-- Bufferline
require("bufferline").setup{
	options = {
		offsets = {
			{ filetype = "NvimTree", text = "", padding = 1 },
			{ filetype = "neo-tree", text = "", padding = 1 },
			{ filetype = "Outline", text = "", padding = 1 },
		},
		buffer_close_icon = "",
		modified_icon = "",
		close_icon = "",
		show_close_icon = true,
		left_trunc_marker = "",
		right_trunc_marker = "",
		max_name_length = 14,
		max_prefix_length = 13,
		tab_size = 20,
		show_tab_indicators = true,
		enforce_regular_tabs = false,
		view = "multiwindow",
		show_buffer_close_icons = true,
		separator_style = "thin",
		always_show_bufferline = true,
		diagnostics = true,
	},
}

-- Gitsigns
require('gitsigns').setup {
	signs = {
		add          = {text = '+'},
		change       = {text = '~'},
		delete       = {text = '-'},
		topdelete    = {text = '-'},
		changedelete = {text = '~'},
	},
	current_line_blame = false
}

-- Indent blankline
require("ibl").setup()
vim.g.indent_blankline_char = '┊'
vim.g.indent_blankline_filetype_exclude = { 'help', 'packer' }
vim.g.indent_blankline_buftype_exclude = { 'terminal', 'nofile' }
vim.g.indent_blankline_show_trailing_blankline_indent = false

-- Telescope
require('telescope').load_extension 'fzf'
