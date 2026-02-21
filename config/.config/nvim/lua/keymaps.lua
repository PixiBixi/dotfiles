-- Keymaps configuration

local function map(mode, shortcut, command)
	vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
end

-- Telescope
map('', '<C-P>', ':Telescope find_files<CR>')
map('', '<C-F>', ':Telescope grep_string<CR>')

-- File explorer
map('', '<C-X>', ':NvimTreeToggle<CR>')
