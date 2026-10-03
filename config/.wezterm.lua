local wezterm = require 'wezterm'
local mux = wezterm.mux

-- Several options below only exist in nightly: the 20240203 stable rejects them.
local is_nightly = wezterm.version > '20240203-110809-5046fc22'

wezterm.on("gui-startup", function(cmd)
    local _, _, window = mux.spawn_window(cmd or {})
    if is_nightly then
        window:gui_window():toggle_fullscreen()
    else
        window:gui_window():maximize()
    end
end)

-- New window in the same state as the current one (notch fullscreen or maximized).
-- The GUI window shows up shortly after the mux window, hence the bounded retry.
local function spawn_window_like_current(window, _)
    local fullscreen = window:get_dimensions().is_full_screen
    local _, _, mux_window = mux.spawn_window {}
    local attempts = 0
    local function apply()
        local gui = mux_window:gui_window()
        if not gui then
            attempts = attempts + 1
            if attempts < 20 then wezterm.time.call_after(0.05, apply) end
            return
        end
        if fullscreen then gui:toggle_fullscreen() else gui:maximize() end
    end
    apply()
end

-- Right status: clock in Tokyo Night colors
wezterm.on('update-status', function(window, _)
    window:set_right_status(wezterm.format {
        { Foreground = { Color = '#565f89' } },
        { Text = '  ' },
        { Foreground = { Color = '#7aa2f7' } },
        { Text = wezterm.strftime('%H:%M') },
        { Foreground = { Color = '#565f89' } },
        { Text = '  ' },
    })
end)

-- Claude Code prefixes its title with a status glyph: '✳' when idle, a spinner frame while working.
local function split_claude_glyph(title)
    local glyph, rest = title:match('^([\128-\255]+)%s+(.*)$')
    return glyph, rest or title
end

local function cwd_basename(pane)
    local cwd = pane.current_working_dir
    local path = cwd and (cwd.file_path or tostring(cwd)) or ''
    return path:gsub('/$', ''):match('([^/]+)$') or path
end

-- Inactive tabs turn yellow while any of their panes works: OSC 9;4 progress or a Claude spinner.
-- The default tab bar only looks at the active pane of each tab.
wezterm.on('format-tab-title', function(tab, _, _, _, _, max_width)
    local busy, failed, shown = false, false, tab.active_pane
    for _, p in ipairs(tab.panes) do
        local progress = p.progress or 'None'
        local glyph = split_claude_glyph(p.title)
        if type(progress) == 'table' and progress.Error then
            failed = true
        elseif progress ~= 'None' or (glyph and glyph ~= '✳') then
            -- Name the tab after the first working pane, not the focused one.
            if not busy then shown = p end
            busy = true
        end
    end
    local _, title = split_claude_glyph(tab.tab_title ~= '' and tab.tab_title or shown.title)
    -- An unnamed Claude session is just titled 'claude': show where it runs instead.
    if title == 'claude' then
        title = 'claude:' .. cwd_basename(shown)
    end
    title = wezterm.truncate_right(string.format(' %d: %s%s ', tab.tab_index + 1, busy and '● ' or '', title), max_width)
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

-- Appearance
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

-- Comfort
config.audible_bell = "Disabled"
config.scrollback_lines = 10000
config.adjust_window_size_when_changing_font_size = false
config.check_for_updates = false

-- Tab bar
config.tab_bar_at_bottom = true
config.hide_tab_bar_if_only_one_tab = true
config.tab_max_width = 32
config.show_new_tab_button_in_tab_bar = false
if is_nightly then
    config.show_close_tab_button_in_tabs = false
end

-- Leader: OPT+b (avoids clashing with tmux Ctrl+b)
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
    { key = 'n', mods = 'CMD', action = wezterm.action_callback(spawn_window_like_current) },

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
