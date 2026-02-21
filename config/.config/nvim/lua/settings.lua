-- Global Neovim settings
local opt = vim.opt

-- Leader key
vim.g.mapleader = ":"

-- UI
opt.number = true
opt.cursorline = true
opt.laststatus = 4
opt.termguicolors = true

-- Editing
opt.breakindent = true
opt.autoindent = true
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.wrap = true

-- Search
opt.hlsearch = true
opt.smartcase = true
opt.ignorecase = true

-- Files
opt.encoding = 'utf-8'
opt.fileencoding = 'utf-8'

-- Misc
opt.ruler = true
opt.syntax = "on"
opt.list = true
opt.clipboard = "unnamedplus"

-- Undo persistence
opt.undodir = vim.fn.expand('~/.config/nvim/undo-dir')
opt.undofile = true

-- Create undo directory if it doesn't exist
local undodir = vim.fn.expand('~/.config/nvim/undo-dir')
if vim.fn.isdirectory(undodir) == 0 then
	vim.fn.mkdir(undodir, 'p', 0700)
end

-- Completion settings
opt.completeopt = 'menuone,noselect'

-- Autocommands
vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = "*",
	command = [[%s/\s\+$//e]],  -- Remove trailing whitespace on save
})

-- Custom filetype detection
vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
	pattern = "haproxy*",
	command = "set ft=haproxy",
})

-- Terraform settings
vim.g.terraform_fmt_on_save = 1
vim.g.terraform_align = 1
