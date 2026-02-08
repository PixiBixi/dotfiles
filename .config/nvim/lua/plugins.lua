-- Plugin management with Packer

-- Auto-install packer if not present
local fn = vim.fn
local install_path = fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
if fn.empty(fn.glob(install_path)) > 0 then
	packer_bootstrap = fn.system({
		'git', 'clone', '--depth', '1',
		'https://github.com/wbthomason/packer.nvim',
		install_path
	})
	vim.cmd [[packadd packer.nvim]]
end

-- Auto-reload on plugins.lua save
vim.cmd [[
	augroup packer_user_config
		autocmd!
		autocmd BufWritePost plugins.lua source <afile> | PackerSync
	augroup end
]]

-- Use protected call
local status_ok, packer = pcall(require, "packer")
if not status_ok then
	return
end

-- Packer configuration
packer.init {
	display = {
		open_fn = function()
			return require("packer.util").float { border = "rounded" }
		end,
	},
	git = {
		clone_timeout = 300
	}
}

-- Load impatient early for performance
pcall(require, 'impatient')

-- Plugin definitions
return packer.startup(function(use)
	-- Core
	use 'wbthomason/packer.nvim'
	use 'lewis6991/impatient.nvim'

	-- Git integration
	use 'tpope/vim-fugitive'
	use { 'lewis6991/gitsigns.nvim', requires = { 'nvim-lua/plenary.nvim' } }

	-- UI
	use 'navarasu/onedark.nvim'
	use 'nvim-lualine/lualine.nvim'
	use {'akinsho/bufferline.nvim', tag = "*", requires = 'kyazdani42/nvim-web-devicons'}
	use {
		'kyazdani42/nvim-tree.lua',
		requires = { 'kyazdani42/nvim-web-devicons' },
		config = function() require'nvim-tree'.setup {} end
	}

	-- Fuzzy finder
	use { 'nvim-telescope/telescope.nvim', requires = { 'nvim-lua/plenary.nvim' } }
	use {'nvim-telescope/telescope-fzf-native.nvim', run = 'make' }

	-- Editing
	use 'Raimondi/delimitMate'
	use 'lukas-reineke/indent-blankline.nvim'

	-- Syntax & Language support
	use 'nvim-treesitter/nvim-treesitter'
	use 'nvim-treesitter/nvim-treesitter-textobjects'
	use 'hashivim/vim-terraform'
	use 'Joorem/vim-haproxy'
	use 'pearofducks/ansible-vim'
	use 'towolf/vim-helm'

	-- LSP & Completion
	use 'williamboman/mason.nvim'
	use 'hrsh7th/nvim-cmp'
	use 'hrsh7th/cmp-nvim-lsp'
	use 'hrsh7th/cmp-buffer'
	use 'saadparwaiz1/cmp_luasnip'
	use 'onsails/lspkind-nvim'
	use 'L3MON4D3/LuaSnip'

	-- Utilities
	use { 'dstein64/vim-startuptime' }

	-- Automatically set up configuration after cloning packer.nvim
	if packer_bootstrap then
		require('packer').sync()
	end
end)
