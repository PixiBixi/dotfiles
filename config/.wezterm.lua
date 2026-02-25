local wezterm = require 'wezterm'
local mux = wezterm.mux

wezterm.on("gui-startup", function(cmd)
    local _, _, window = mux.spawn_window(cmd or {})
    window:gui_window():maximize()
end)

-- Right status : affiche l'heure avec couleurs Tokyo Night
wezterm.on('update-right-status', function(window, _)
    window:set_right_status(wezterm.format {
        { Foreground = { Color = '#565f89' } },
        { Text = '  ' },
        { Foreground = { Color = '#7aa2f7' } },
        { Text = wezterm.strftime('%H:%M') },
        { Foreground = { Color = '#565f89' } },
        { Text = '  ' },
    })
end)

local config = wezterm.config_builder()

-- Apparence
config.color_scheme = 'Tokyo Night'
config.colors = {
    tab_bar = {
        active_tab = { fg_color = '#073642', bg_color = '#2aa198' }
    }
}
config.window_background_opacity = 0.85
config.macos_window_background_blur = 30
config.window_decorations = 'RESIZE'
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

-- Fonts
config.window_frame = {
    font = wezterm.font({ family = 'Berkeley Mono', weight = 'Bold' }),
    font_size = 10,
}

-- Confort
config.audible_bell = "Disabled"
config.scrollback_lines = 10000
config.adjust_window_size_when_changing_font_size = false
config.check_for_updates = false

-- Tab bar
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = true

-- Leader : OPT+b (évite conflit avec tmux Ctrl+b)
config.leader = { key = "b", mods = "OPT", timeout_milliseconds = 1000 }

-- Allows ~ | etc. with left Alt on macOS
config.send_composed_key_when_left_alt_is_pressed = true


local function movePane(key, direction)
    return { key = key, mods = 'LEADER', action = wezterm.action.ActivatePaneDirection(direction) }
end
local function resizePane(key, direction)
    return { key = key, mods = 'CMD', action = wezterm.action.AdjustPaneSize { direction, 5 } }
end

config.keys = {
    { key = 'm', mods = 'CMD', action = wezterm.action.DisableDefaultAssignment },

    resizePane('LeftArrow', 'Left'),
    resizePane('RightArrow', 'Right'),
    resizePane('UpArrow', 'Up'),
    resizePane('DownArrow', 'Down'),

    movePane('LeftArrow', 'Left'),
    movePane('RightArrow', 'Right'),
    movePane('UpArrow', 'Up'),
    movePane('DownArrow', 'Down'),

    { key = 'z', mods = 'LEADER', action = wezterm.action.TogglePaneZoomState },
    { key = '%', mods = 'LEADER', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
    { key = '"', mods = 'LEADER', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
    { key = 'w', mods = 'LEADER', action = wezterm.action.CloseCurrentPane { confirm = true } },

    -- Word navigation (backward/forward)
    { key = 'LeftArrow',  mods = 'OPT', action = wezterm.action.SendString("\x1bb") },
    { key = 'RightArrow', mods = 'OPT', action = wezterm.action.SendString("\x1bf") },
}

-- Override hyperlink rules to exclude trailing punctuation (e.g. trailing ')' from markdown links)
config.hyperlink_rules = {
    -- URLs: stop before trailing ), ], and common punctuation
    {
        regex = [=[\b\w+://[^\s<>"\[\]()]*[^\s<>"\[\]()\.,;:!?'`]]=],
        format = '$0',
    },
    -- email addresses
    {
        regex = [[\b\w+@[\w-]+(\.[\w-]+)+\b]],
        format = 'mailto:$0',
    },
}

return config
