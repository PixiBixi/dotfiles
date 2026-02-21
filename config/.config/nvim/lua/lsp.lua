-- LSP configuration with Mason

-- Mason setup for LSP management (install tools only)
require('mason').setup({
	ui = {
		border = 'rounded',
		icons = {
			package_installed = "✓",
			package_pending = "➜",
			package_uninstalled = "✗"
		}
	}
})

-- LSP capabilities
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

-- LSP keymaps on buffer attach
vim.api.nvim_create_autocmd('LspAttach', {
	callback = function(args)
		local bufnr = args.buf
		local opts = { noremap = true, silent = true, buffer = bufnr }
		vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
		vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
		vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
		vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
		vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
		vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
		vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
		vim.keymap.set('n', '<leader>wl', function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, opts)
		vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, opts)
		vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
		vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
		vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
		vim.keymap.set('n', '<leader>so', require('telescope.builtin').lsp_document_symbols, opts)
	end,
})

-- Configure LSP servers with native vim.lsp.config (Neovim 0.11+)
vim.lsp.config.ansiblels = {
	cmd = {'ansible-language-server', '--stdio'},
	filetypes = {'yaml.ansible'},
	root_markers = {'ansible.cfg', '.ansible-lint'},
	capabilities = capabilities,
}

vim.lsp.config.dockerls = {
	cmd = {'docker-langserver', '--stdio'},
	filetypes = {'dockerfile'},
	root_markers = {'Dockerfile'},
	capabilities = capabilities,
}

vim.lsp.config.bashls = {
	cmd = {'bash-language-server', 'start'},
	filetypes = {'sh', 'bash', 'zsh'},
	root_markers = {'.git'},
	capabilities = capabilities,
}

vim.lsp.config.pyright = {
	cmd = {'pyright-langserver', '--stdio'},
	filetypes = {'python'},
	root_markers = {'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile', '.git'},
	capabilities = capabilities,
	settings = {
		python = {
			analysis = {
				autoSearchPaths = true,
				useLibraryCodeForTypes = false,
				diagnosticMode = 'openFilesOnly',
				typeCheckingMode = 'basic',
			},
		},
	},
}

vim.lsp.config.yamlls = {
	cmd = {'yaml-language-server', '--stdio'},
	filetypes = {'yaml', 'yaml.docker-compose'},
	root_markers = {'.git'},
	capabilities = capabilities,
	settings = {
		yaml = {
			schemas = {
				["https://raw.githubusercontent.com/instrumenta/kubernetes-json-schema/master/v1.18.0-standalone-strict/all.json"] = "/*.k8s.yaml",
			},
		},
	},
}

vim.lsp.config.terraformls = {
	cmd = {'terraform-ls', 'serve'},
	filetypes = {'terraform', 'tf', 'hcl'},
	root_markers = {'.terraform', '.git'},
	capabilities = capabilities,
}

vim.lsp.config.tflint = {
	cmd = {'tflint', '--langserver'},
	filetypes = {'terraform', 'tf'},
	root_markers = {'.terraform', '.git', '.tflint.hcl'},
	capabilities = capabilities,
}

-- Auto-enable LSP servers on matching filetypes
vim.api.nvim_create_autocmd('FileType', {
	pattern = {'yaml.ansible'},
	callback = function() vim.lsp.enable('ansiblels') end,
})

vim.api.nvim_create_autocmd('FileType', {
	pattern = {'dockerfile'},
	callback = function() vim.lsp.enable('dockerls') end,
})

vim.api.nvim_create_autocmd('FileType', {
	pattern = {'sh', 'bash', 'zsh'},
	callback = function() vim.lsp.enable('bashls') end,
})

vim.api.nvim_create_autocmd('FileType', {
	pattern = {'python'},
	callback = function() vim.lsp.enable('pyright') end,
})

vim.api.nvim_create_autocmd('FileType', {
	pattern = {'yaml'},
	callback = function() vim.lsp.enable('yamlls') end,
})

vim.api.nvim_create_autocmd('FileType', {
	pattern = {'terraform', 'tf', 'hcl'},
	callback = function()
		vim.lsp.enable('terraformls')
		vim.lsp.enable('tflint')
	end,
})
