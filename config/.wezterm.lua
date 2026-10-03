local wezterm = require 'wezterm'
local mux = wezterm.mux

-- Notch fullscreen, contrast and alignment options only exist in nightly: the 20240203 stable rejects them.
local is_nightly = wezterm.version > '20240203-110809-5046fc22'

wezterm.on("gui-startup", function(cmd)
    local _, _, window = mux.spawn_window(cmd or {})
    if is_nightly then
        window:gui_window():toggle_fullscreen()
    else
        window:gui_window():maximize()
    end
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

-- Highlight inactive tabs where any pane reports progress (OSC 9;4), e.g. a working Claude session.
-- The default tab bar only looks at the active pane of each tab.
wezterm.on('format-tab-title', function(tab, _, _, _, _, max_width)
    local busy, failed = false, false
    for _, p in ipairs(tab.panes) do
        local progress = p.progress or 'None'
        if type(progress) == 'table' and progress.Error then
            failed = true
        elseif progress ~= 'None' then
            busy = true
        end
    end
    local title = tab.tab_title ~= '' and tab.tab_title or tab.active_pane.title
    title = wezterm.truncate_right(string.format(' %d: %s ', tab.tab_index + 1, title), max_width)
    if tab.is_active or not (busy or failed) then
        return title
    end
    return {
        { Background = { Color = failed and '#f7768e' or '#e0af68' } },
        { Foreground = { Color = '#1a1b26' } },
        { Text = title },
    }
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
if is_nightly then
    -- Native fullscreen must stay off, the notch option is ignored with it.
    config.native_macos_fullscreen_mode = false
    config.macos_fullscreen_extend_behind_notch = true
    -- Spread the leftover pixels of a non-cell-aligned fullscreen evenly instead of right/bottom.
    config.window_content_alignment = { horizontal = 'Center', vertical = 'Center' }
    -- WCAG AA: Tokyo Night dim text is hard to read over the translucent background.
    config.text_min_contrast_ratio = 4.5
end

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
    { key = 'f', mods = 'CMD|CTRL', action = wezterm.action.ToggleFullScreen },

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
