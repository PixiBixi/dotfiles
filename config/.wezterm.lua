local wezterm = require 'wezterm'
local mux = wezterm.mux

-- Several options below only exist in nightly: the 20240203 stable rejects them.
local is_nightly = wezterm.version > '20240203-110809-5046fc22'

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

local function cwd_basename(cwd)
    local path = cwd and (cwd.file_path or tostring(cwd)) or ''
    return path:gsub('/$', ''):match('([^/]+)$') or path
end

-- Layout snapshot for ~/.local/bin/wezterm-restore. WezTerm has no pane created/closed event, so
-- update-status (about every second) fingerprints the layout and writes only when it changed.
local STATE_DIR = wezterm.home_dir .. '/.local/state/wezterm'
local LAYOUT_FILE = STATE_DIR .. '/layout.json'
local LAYOUT_HISTORY = 10
local CLAUDE_REFRESH_SECONDS = 30
wezterm.run_child_process { 'mkdir', '-p', STATE_DIR .. '/history' }

-- The Claude session behind a pane, from the file Claude Code keeps per process.
local function claude_session(pane)
    local info = pane:get_foreground_process_info()
    if not info then return nil end
    -- The binary is ~/.local/share/claude/versions/<version>: match argv[0], not the executable name.
    local arg0 = ((info.argv or {})[1] or ''):match('[^/]*$')
    if not arg0:match('^claude') and not (info.executable or ''):find('/claude/versions/', 1, true) then return nil end
    local f = io.open(string.format('%s/.claude/sessions/%d.json', wezterm.home_dir, info.pid))
    if not f then return nil end
    local ok, data = pcall(wezterm.serde.json_decode, f:read('a'))
    f:close()
    return ok and data.sessionId or nil
end

local function write_file(path, content)
    local f = io.open(path, 'w')
    if f then f:write(content) f:close() end
end

local function read_file(path)
    local f = io.open(path)
    if not f then return nil end
    local content = f:read('a')
    f:close()
    return content
end

local function save_layout(json)
    local previous = read_file(LAYOUT_FILE)
    if previous then
        write_file(string.format('%s/history/layout-%s.json', STATE_DIR, os.date('%Y%m%d-%H%M%S')), previous)
        local old = wezterm.glob(STATE_DIR .. '/history/layout-*.json')
        table.sort(old)
        for i = 1, #old - LAYOUT_HISTORY do os.remove(old[i]) end
    end
    write_file(LAYOUT_FILE, json)
end

wezterm.on('update-status', function()
    if not is_nightly then return end
    local g = wezterm.GLOBAL
    local now = os.time()
    local refresh_claude = now - (g.claude_refreshed_at or 0) >= CLAUDE_REFRESH_SECONDS
    local known, sessions = g.claude_sessions or {}, {}
    local windows, keys, count = {}, {}, 0
    for _, mw in ipairs(wezterm.mux.all_windows()) do
        local tabs = {}
        for _, tab in ipairs(mw:tabs()) do
            local panes = {}
            for _, p in ipairs(tab:panes_with_info()) do
                local id = tostring(p.pane:pane_id())
                if refresh_claude then sessions[id] = claude_session(p.pane) else sessions[id] = known[id] end
                local cwd = p.pane:get_current_working_dir()
                table.insert(panes, {
                    left = p.left, top = p.top, width = p.width, height = p.height,
                    cwd = cwd and cwd.file_path or wezterm.home_dir,
                    title = p.pane:get_title(), claude_session = sessions[id],
                })
                table.insert(keys, string.format('%s:%d,%d,%dx%d:%s', id, p.left, p.top, p.width, p.height, sessions[id] or ''))
                count = count + 1
            end
            table.insert(tabs, { panes = panes })
            table.insert(keys, '|')
        end
        table.insert(windows, { tabs = tabs })
        table.insert(keys, '#')
    end
    g.claude_sessions = sessions
    if refresh_claude then g.claude_refreshed_at = now end
    local fingerprint = table.concat(keys)
    if count == 0 or fingerprint == g.layout_fingerprint then return end
    g.layout_fingerprint = fingerprint
    local json = wezterm.serde.json_encode { saved_at = os.date('!%Y-%m-%dT%H:%M:%SZ'), windows = windows }
    -- Panes may close one by one on quit or reboot: a snapshot that lost over half of them goes aside
    -- instead of overwriting the good one, unless it holds for a minute (a deliberate cleanup).
    local previous = g.layout_pane_count or 0
    if previous > 2 and count < previous / 2 then
        g.layout_partial_since = g.layout_partial_since or now
        if now - g.layout_partial_since < 60 then
            write_file(STATE_DIR .. '/layout-partial.json', json)
            g.layout_fingerprint = nil
            return
        end
    end
    g.layout_partial_since = nil
    save_layout(json)
    g.layout_pane_count = count
end)

-- Startup: keep the previous session's final layout before the new window overwrites it, and when
-- it exists, open the first tab on wezterm-restore --prompt, which offers to bring it all back.
wezterm.on('gui-startup', function(cmd)
    local spawn = cmd or {}
    local last = read_file(LAYOUT_FILE)
    if last then
        write_file(STATE_DIR .. '/layout-last-session.json', last)
        if not spawn.args then
            spawn = { args = { '/opt/homebrew/bin/python3', wezterm.home_dir .. '/.local/bin/wezterm-restore', '--prompt' } }
        end
    end
    local _, _, window = mux.spawn_window(spawn)
    if is_nightly then
        window:gui_window():toggle_fullscreen()
    else
        window:gui_window():maximize()
    end
end)

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
        title = 'claude:' .. cwd_basename(shown.current_working_dir)
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

-- Pane picker (Cmd+P): fzf in a zoomed split of the current tab, see ~/.local/bin/wezterm-pane-picker.
local ESC = string.char(27)
local function ansi(color, text) return ESC .. '[' .. color .. 'm' .. text .. ESC .. '[0m' end

local function pick_tab(window, pane)
    local lines, current = {}, 1
    local home = os.getenv('HOME') or ''
    for _, t in ipairs(window:mux_window():tabs_with_info()) do
        for _, p in ipairs(t.tab:panes()) do
            local glyph, title = split_claude_glyph(p:get_title())
            local cwd = p:get_current_working_dir()
            local path = cwd and (cwd.file_path or tostring(cwd)) or ''
            if title == 'claude' then
                title = 'claude:' .. cwd_basename(cwd)
            end
            local mark = glyph == nil and '  ' or glyph == '✳' and ansi('38;2;86;95;137', '✳ ') or ansi('38;2;224;175;104', '● ')
            table.insert(lines, string.format('%d\t%d\t%s\t%s %s%s  %s', t.tab:tab_id(), p:pane_id(), path:gsub('^' .. home, '~'),
                ansi('38;2;122;162;247', string.format('%2d', t.index + 1)), mark, title, ansi('38;2;86;95;137', cwd_basename(cwd))))
            if p:pane_id() == pane:pane_id() then current = #lines end
        end
    end
    -- Zoomed so the picker fills the tab; the zoom goes away with the picker pane.
    local picker = pane:split {
        direction = 'Bottom',
        args = { home .. '/.local/bin/wezterm-pane-picker', table.concat(lines, '\n'), tostring(current) },
    }
    picker:activate()
    picker:tab():set_zoomed(true)
end

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

-- Tab bar font: JetBrains Mono ships with WezTerm, so it always resolves (the default is Roboto).
config.window_frame = {
    font = wezterm.font({ family = 'JetBrains Mono', weight = 'Bold' }),
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
    { key = 'p', mods = 'CMD', action = wezterm.action_callback(pick_tab) },

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
