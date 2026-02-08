-- ============================================================================
-- Neovim Configuration
-- ============================================================================
-- Modular configuration for SRE/Platform Engineering
-- Focus: Terraform, Kubernetes, Python, Ansible, Helm
-- ============================================================================

-- Load core modules
require('settings')    -- Global vim options and settings
require('plugins')     -- Plugin management with Packer
require('keymaps')     -- Keyboard mappings
require('ui')          -- Theme, statusline, file explorer
require('treesitter')  -- Syntax highlighting and AST
require('lsp')         -- Language Server Protocol configuration
require('completion')  -- Completion engine (nvim-cmp)
