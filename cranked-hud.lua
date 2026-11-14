--[[
    Cranked Mode - HUD Interface Engine
    Compatible with Call of Duty (Saturn / Kronos)
    Architecture: Decoupled LUI widget rendering, threat gradient styling, and safe lifecycle management
]]

local CrankedHUD = {
    version = "1.0.0",
    active = false,
    container = nil,
    status_label = nil,
    timer_label = nil,
    bar_bg = nil,
    bar_fill = nil,
    timer_element = nil,
    last_sfx_second = -1,
    blink_counter = 0
}

-- Safe accessor helper
local function safe_call(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

-- Check if currently inside active game session
function CrankedHUD.IsInGame()
    local core = rawget(_G, "CrankedCore")
    if type(core) == "table" and type(core.IsInGame) == "function" then
        local ok, val = pcall(core.IsInGame)
        if ok and val ~= nil then return val == true end
    end

    local engine = rawget(_G, "Engine")
    if type(engine) == "table" and type(rawget(engine, "InFrontend")) == "function" then
        local ok, in_frontend = safe_call(engine.InFrontend)
        if ok and in_frontend == false then
            return true
        end
    end
    return false
end

-- Safe sound trigger
function CrankedHUD.PlaySFX(sound_name)
    sound_name = sound_name or "uin_alert_lockon"

    local actions = rawget(_G, "ACTIONS")
    if type(actions) == "table" and type(rawget(actions, "PlaySoundSetSound")) == "function" then
        local ok = pcall(actions.PlaySoundSetSound, sound_name)
        if ok then return true end
    end

    local engine = rawget(_G, "Engine")
    if type(engine) == "table" and type(rawget(engine, "PlaySound")) == "function" then
        local ok = pcall(engine.PlaySound, sound_name)
        if ok then return true end
    end

    return false
end

-- Resolve LUI Root or HudManager safely
local function get_parent_container()
    local hud_mgr = rawget(_G, "HudManager")
    if type(hud_mgr) == "table" then
        local get_root = rawget(hud_mgr, "GetRoot") or rawget(hud_mgr, "getRoot")
        if type(get_root) == "function" then
            local ok, root = safe_call(get_root, hud_mgr)
            if ok and type(root) == "table" then return root end
        end
    end

    local lui = rawget(_G, "LUI")
    if type(lui) == "table" then
        local get_root = rawget(lui, "GetRoot") or rawget(lui, "getRoot")
        if type(get_root) == "function" then
            local ok, root = safe_call(get_root)
            if ok and type(root) == "table" then return root end
        end
    end

    return nil
end

-- Safe element factory
local function create_ui_element(class_name)
    local lui = rawget(_G, "LUI")
    if type(lui) ~= "table" then return nil end

    local class_obj = rawget(lui, class_name)
    if type(class_obj) == "table" and type(rawget(class_obj, "new")) == "function" then
        local ok, elem = pcall(class_obj.new)
        if ok and type(elem) == "table" then
            return elem
        end
    end

    -- Fallback to basic UIElement if specialized class is missing
    local base_class = rawget(lui, "UIElement")
    if type(base_class) == "table" and type(rawget(base_class, "new")) == "function" then
        local ok, elem = pcall(base_class.new)
        if ok and type(elem) == "table" then
            return elem
        end
    end

    return nil
end

-- Safe styling wrappers
local function safe_set_rgb(elem, r, g, b)
    if type(elem) ~= "table" then return end
    if type(elem.setRGB) == "function" then
        local ok = pcall(elem.setRGB, elem, r, g, b)
        if not ok then
            pcall(elem.setRGB, elem, {r = r, g = g, b = b})
        end
    elseif type(elem.setRGBColor) == "function" then
        pcall(elem.setRGBColor, elem, r, g, b)
    end
end

local function safe_set_alpha(elem, alpha)
    if type(elem) ~= "table" or type(elem.setAlpha) ~= "function" then return end
    pcall(elem.setAlpha, elem, alpha)
end

local function safe_set_text(elem, text)
    if type(elem) ~= "table" or type(elem.setText) ~= "function" then return end
    pcall(elem.setText, elem, tostring(text))
end

local function safe_set_left_right(elem, is_rel_left, is_rel_right, left, right)
    if type(elem) ~= "table" or type(elem.setLeftRight) ~= "function" then return end
    pcall(elem.setLeftRight, elem, is_rel_left, is_rel_right, left, right)
end

local function safe_set_top_bottom(elem, is_rel_top, is_rel_bottom, top, bottom)
    if type(elem) ~= "table" or type(elem.setTopBottom) ~= "function" then return end
    pcall(elem.setTopBottom, elem, is_rel_top, is_rel_bottom, top, bottom)
end

local function safe_set_alignment(elem, align)
    if type(elem) ~= "table" or type(elem.setAlignment) ~= "function" then return end
    pcall(elem.setAlignment, elem, align)
end

-- Remove element from hierarchy safely
local function safe_close_element(elem)
    if type(elem) ~= "table" then return end
    if type(elem.close) == "function" then
        pcall(elem.close, elem)
    elseif type(elem.getParent) == "function" then
        local ok, parent = pcall(elem.getParent, elem)
        if ok and type(parent) == "table" and type(parent.removeElement) == "function" then
            pcall(parent.removeElement, parent, elem)
        end
    end
end

-- Initialize and build HUD visual hierarchy
function CrankedHUD.Build()
    if CrankedHUD.container ~= nil then return true end

    local parent = get_parent_container()
    if not parent then return false end

    -- Container element: centered at top (-150 to 150 px, top 40 to 120 px)
    local container = create_ui_element("UIElement")
    if not container then return false end

    safe_set_left_right(container, false, false, -150, 150)
    safe_set_top_bottom(container, true, false, 40, 120)
    safe_set_alpha(container, 1.0)

    -- Status label (Top portion: 0 to 22 px)
    local status_label = create_ui_element("UIStyledText") or create_ui_element("UIText")
    if status_label then
        safe_set_left_right(status_label, true, true, 0, 0)
        safe_set_top_bottom(status_label, true, false, 0, 22)
        safe_set_alignment(status_label, 2) -- Center alignment
        safe_set_text(status_label, "ESPERA PRIMER KILL")
        safe_set_rgb(status_label, 0.4, 0.8, 0.9)
        safe_set_alpha(status_label, 0.8)
        if type(container.addElement) == "function" then
            pcall(container.addElement, container, status_label)
        end
    end

    -- Digital timer label (Middle portion: 24 to 62 px)
    local timer_label = create_ui_element("UIStyledText") or create_ui_element("UIText")
    if timer_label then
        safe_set_left_right(timer_label, true, true, 0, 0)
        safe_set_top_bottom(timer_label, true, false, 24, 62)
        safe_set_alignment(timer_label, 2) -- Center alignment
        safe_set_text(timer_label, "--.-s")
        safe_set_rgb(timer_label, 0.85, 0.95, 1.0)
        safe_set_alpha(timer_label, 1.0)
        if type(container.addElement) == "function" then
            pcall(container.addElement, container, timer_label)
        end
    end

    -- Progress bar background (Bottom portion: width 260px, centered from -130 to 130, top 66 to 74)
    local bar_bg = create_ui_element("UIImage") or create_ui_element("UIElement")
    if bar_bg then
        safe_set_left_right(bar_bg, false, false, -130, 130)
        safe_set_top_bottom(bar_bg, true, false, 66, 74)
        safe_set_rgb(bar_bg, 0.05, 0.05, 0.08)
        safe_set_alpha(bar_bg, 0.6)
        if type(container.addElement) == "function" then
            pcall(container.addElement, container, bar_bg)
        end
    end

    -- Progress bar fill (Inside background: starts at -130)
    local bar_fill = create_ui_element("UIImage") or create_ui_element("UIElement")
    if bar_fill then
        safe_set_left_right(bar_fill, false, false, -130, 130)
        safe_set_top_bottom(bar_fill, true, false, 66, 74)
        safe_set_rgb(bar_fill, 0.85, 0.95, 1.0)
        safe_set_alpha(bar_fill, 0.9)
        if type(container.addElement) == "function" then
            pcall(container.addElement, container, bar_fill)
        end
    end

    -- Attach container to parent root
    if type(parent.addElement) == "function" then
        local ok = pcall(parent.addElement, parent, container)
        if not ok then return false end
    end

    CrankedHUD.container = container
    CrankedHUD.status_label = status_label
    CrankedHUD.timer_label = timer_label
    CrankedHUD.bar_bg = bar_bg
    CrankedHUD.bar_fill = bar_fill
    CrankedHUD.active = true
    CrankedHUD.last_sfx_second = -1

    return true
end

-- Cleanup and destroy all HUD visual nodes
function CrankedHUD.Destroy()
    if CrankedHUD.container ~= nil then
        safe_close_element(CrankedHUD.container)
    end
    CrankedHUD.container = nil
    CrankedHUD.status_label = nil
    CrankedHUD.timer_label = nil
    CrankedHUD.bar_bg = nil
    CrankedHUD.bar_fill = nil
    CrankedHUD.timer_element = nil
    CrankedHUD.active = false
    CrankedHUD.last_sfx_second = -1
    CrankedHUD.blink_counter = 0
end

-- Main render update tick
function CrankedHUD.Update()
    if not CrankedHUD.IsInGame() then
        if CrankedHUD.active then
            CrankedHUD.Destroy()
        end
        return
    end

    if not CrankedHUD.active or CrankedHUD.container == nil then
        local built = CrankedHUD.Build()
        if not built then return end
    end

    local core = rawget(_G, "CrankedCore")
    if type(core) ~= "table" then return end

    -- Drive core state machine and countdown tick (50ms interval)
    if type(core.Tick) == "function" then
        pcall(core.Tick, 0.05)
    end

    local state = tonumber(core.state) or 0
    local current_time = tonumber(core.current_time) or 0
    local max_time = tonumber(core.max_time) or 30
    if max_time <= 0 then max_time = 30 end

    CrankedHUD.blink_counter = (CrankedHUD.blink_counter + 1) % 20
    local is_blink_on = CrankedHUD.blink_counter < 10

    -- State 0: Inactive / In lobby
    if state == 0 then
        safe_set_alpha(CrankedHUD.container, 0.0)
        return
    end

    safe_set_alpha(CrankedHUD.container, 1.0)

    -- State 1: Waiting for first kill
    if state == 1 then
        safe_set_text(CrankedHUD.status_label, "ESPERA PRIMER KILL")
        safe_set_rgb(CrankedHUD.status_label, 0.4, 0.8, 0.9)
        safe_set_alpha(CrankedHUD.status_label, 0.8)

        safe_set_text(CrankedHUD.timer_label, string.format("%.1fs", max_time))
        safe_set_rgb(CrankedHUD.timer_label, 0.4, 0.8, 0.9)
        safe_set_alpha(CrankedHUD.timer_label, 0.7)

        -- Full bar in standby
        safe_set_left_right(CrankedHUD.bar_fill, false, false, -130, 130)
        safe_set_rgb(CrankedHUD.bar_fill, 0.4, 0.8, 0.9)
        safe_set_alpha(CrankedHUD.bar_fill, 0.5)

        CrankedHUD.last_sfx_second = -1
        return
    end

    -- State 2: Cranked Active
    if state == 2 then
        safe_set_text(CrankedHUD.status_label, "CRANKED")
        safe_set_text(CrankedHUD.timer_label, string.format("%.1fs", math.max(0, current_time)))

        -- Color gradient by threat level
        local r, g, b, alpha
        if current_time > 10.0 then
            -- Safe: Cyan / White
            r, g, b = 0.85, 0.95, 1.0
            alpha = 1.0
            CrankedHUD.last_sfx_second = -1
        elseif current_time >= 5.0 then
            -- Warning: Amber / Orange
            r, g, b = 1.0, 0.65, 0.1
            alpha = 1.0
            CrankedHUD.last_sfx_second = -1
        else
            -- Critical: Flashing Red
            r, g, b = 1.0, 0.15, 0.15
            alpha = is_blink_on and 1.0 or 0.35

            -- Audible warning: 1 pulse per second in critical zone
            local sec = math.floor(current_time)
            if sec ~= CrankedHUD.last_sfx_second and sec >= 0 then
                CrankedHUD.last_sfx_second = sec
                CrankedHUD.PlaySFX("uin_alert_lockon")
            end
        end

        safe_set_rgb(CrankedHUD.status_label, r, g, b)
        safe_set_alpha(CrankedHUD.status_label, alpha)

        safe_set_rgb(CrankedHUD.timer_label, r, g, b)
        safe_set_alpha(CrankedHUD.timer_label, alpha)

        -- Progress bar proportional to remaining time
        local ratio = math.min(1.0, math.max(0.0, current_time / max_time))
        local fill_right = -130 + math.floor(260 * ratio)
        safe_set_left_right(CrankedHUD.bar_fill, false, false, -130, fill_right)
        safe_set_rgb(CrankedHUD.bar_fill, r, g, b)
        safe_set_alpha(CrankedHUD.bar_fill, alpha)
        return
    end

    -- State 3: Detonated / Time Out
    if state == 3 then
        safe_set_text(CrankedHUD.status_label, "TIEMPO AGOTADO")
        local r, g, b = 1.0, 0.1, 0.1
        local alpha = is_blink_on and 1.0 or 0.2

        safe_set_rgb(CrankedHUD.status_label, r, g, b)
        safe_set_alpha(CrankedHUD.status_label, alpha)

        safe_set_text(CrankedHUD.timer_label, "0.0s")
        safe_set_rgb(CrankedHUD.timer_label, r, g, b)
        safe_set_alpha(CrankedHUD.timer_label, alpha)

        -- Empty bar
        safe_set_left_right(CrankedHUD.bar_fill, false, false, -130, -130)
        safe_set_rgb(CrankedHUD.bar_fill, r, g, b)
        safe_set_alpha(CrankedHUD.bar_fill, alpha)
        CrankedHUD.last_sfx_second = -1
        return
    end
end

-- Initialize refresh loop (20Hz / 50ms)
function CrankedHUD.StartTimerLoop()
    local parent = get_parent_container()
    if not parent then return false end

    -- Pattern 1: Native LUI CreateEventTimer if available
    local create_timer = rawget(parent, "CreateEventTimer")
    if type(create_timer) == "function" then
        local ok = pcall(create_timer, parent, "cranked_hud_loop", 50, {
            immediate = false,
            callbackFunc = function()
                CrankedHUD.Update()
            end
        })
        if ok then return true end
    end

    -- Pattern 2: LUI.UITimer element registration
    local lui = rawget(_G, "LUI")
    if type(lui) == "table" then
        local ui_timer = rawget(lui, "UITimer")
        if type(ui_timer) == "table" and type(rawget(ui_timer, "new")) == "function" then
            local ok_new, timer_inst = pcall(ui_timer.new, 50, "cranked_hud_event")
            if ok_new and type(timer_inst) == "table" then
                if type(parent.registerEventHandler) == "function" then
                    pcall(parent.registerEventHandler, parent, "cranked_hud_event", function()
                        CrankedHUD.Update()
                    end)
                end
                if type(parent.addElement) == "function" then
                    pcall(parent.addElement, parent, timer_inst)
                end
                CrankedHUD.timer_element = timer_inst
                return true
            end
        end
    end

    return false
end

-- Export globally and return module
rawset(_G, "CrankedHUD", CrankedHUD)

return CrankedHUD
