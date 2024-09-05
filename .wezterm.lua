-- Highly base on https://alexplescan.com/posts/2024/08/10/wezterm/

-- Import the wezterm module
local wezterm = require 'wezterm'
-- Creates a config object which we will be adding our config to
local config = wezterm.config_builder()

-- (This is where our config will go)

-- Find them here: https://wezfurlong.org/wezterm/colorschemes/index.html
config.color_scheme = 'Tokyo Night'

-- Slightly transparent and blurred background
config.window_background_opacity = 0.8
config.macos_window_background_blur = 30
config.window_decorations = 'RESIZE' -- disable the title bar but enable the resizable border
config.window_frame = {
	font = wezterm.font({ family = 'Berkeley Mono', weight = 'Bold' }),
	font_size = 11,
}

-- Leader as tmux default binding
config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1500 }

local function movePane(key, direction)
	return {
		key = key,
		mods = 'LEADER',
		action = wezterm.action.ActivatePaneDirection(direction),
	}
end
local function resizePane(key, direction)
	return {
		key = key,
		mods = 'CMD',
		action = wezterm.action.AdjustPaneSize { direction, 5 }
	}
end


config.keys = {
	-- Disable default behavior for Cmd+M on MacOS
	{
		key = 'm',
		mods = 'CMD',
		action = wezterm.action.DisableDefaultAssignment,
	},

	-- Pane resize
	resizePane('LeftArrow','Left'),
	resizePane('RightArrow','Right'),
	resizePane('UpArrow','Up'),
	resizePane('DownArrow','Down'),

	-- Pane move
	movePane('LeftArrow','Left'),
	movePane('RightArrow','Right'),
	movePane('UpArrow','Up'),
	movePane('DownArrow','Down'),

	{
		key = 'z',
		mods = "LEADER",
		action = wezterm.action.TogglePaneZoomState,
	},
	-- Pane split
	{
		mods = "LEADER",
		key = "%",
		action = wezterm.action.SplitHorizontal { domain = "CurrentPaneDomain" }
	},
	{
		mods = "LEADER",
		key = '"',
		action = wezterm.action.SplitVertical { domain = "CurrentPaneDomain" }
	},

	-- Make Option-Left equivalent to Alt-b which many line editors interpret as backward-word
	{key="LeftArrow", mods="OPT", action=wezterm.action{SendString="\x1bb"}},
	{key="LeftArrow", mods="CMD", action=wezterm.action{SendString="\x1bb"}},
	-- Make Option-Right equivalent to Alt-f; forward-word
	{key="RightArrow", mods="OPT", action=wezterm.action{SendString="\x1bf"}},
	{key="RightArrow", mods="CMD", action=wezterm.action{SendString="\x1bf"}},

}

config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = true

-- Can't use ~ or | without it
config.send_composed_key_when_left_alt_is_pressed = true

-- Returns our config to be evaluated. We must always do this at the bottom of this file
return config
