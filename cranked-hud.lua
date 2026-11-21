--[[
    Cranked Mode - HUD Interface Engine
    Compatible with Call of Duty (Saturn / Kronos)
    Architecture: Decoupled LUI widget rendering, threat gradient styling,
    authoritative GSC synchronization, and safe lifecycle management.
]]

local CrankedHUD = {
    version = "1.2.0",
    active = false,
    container = nil,
    status_label = nil,
    timer_label = nil,
    bar_bg = nil,
    bar_fill = nil,
    timer_element = nil,
    timer_running = false,
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
    if type(core) == "table" then
        -- If core has already transitioned to an active in-game state (1, 2, 3), match is active
        local st = tonumber(core.state) or 0
        if st > 0 then
            return true
        end
        if type(core.IsInGame) == "function" then
            local ok, val = pcall(core.IsInGame)
            if ok and val == true then return true end
        end
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
        if type(rawget(lui, "primaryRoot")) == "table" then
            return lui.primaryRoot
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
    elseif type(elem.SetRGB) == "function" then
        local ok = pcall(elem.SetRGB, elem, r, g, b)
        if not ok then
            pcall(elem.SetRGB, elem, {r = r, g = g, b = b})
        end
    elseif type(elem.setRGBColor) == "function" then
        pcall(elem.setRGBColor, elem, r, g, b)
    end
end

local function safe_set_alpha(elem, alpha)
    if type(elem) ~= "table" then return end
    alpha = tonumber(alpha) or 0.0
    if type(elem.setAlpha) == "function" then
        pcall(elem.setAlpha, elem, alpha)
    elseif type(elem.SetAlpha) == "function" then
        pcall(elem.SetAlpha, elem, alpha)
    end
end

local function safe_set_text(elem, text)
    if type(elem) ~= "table" then return end
    local str = tostring(text or "")
    if type(elem.setText) == "function" then
        pcall(elem.setText, elem, str)
    elseif type(elem.SetText) == "function" then
        pcall(elem.SetText, elem, str)
    end
end

local function safe_set_left_right(elem, is_rel_left, is_rel_right, left, right)
    if type(elem) ~= "table" then return end
    if type(elem.setLeftRight) == "function" then
        pcall(elem.setLeftRight, elem, is_rel_left, is_rel_right, left, right)
    elseif type(elem.SetAnchorsAndPosition) == "function" then
        local lf = is_rel_left and 0 or 0.5
        local rf = is_rel_right and 1 or 0.5
        pcall(elem.SetAnchorsAndPosition, elem, lf, rf, 0, 0, left, right, 0, 0)
    end
end

local function safe_set_top_bottom(elem, is_rel_top, is_rel_bottom, top, bottom)
    if type(elem) ~= "table" then return end
    if type(elem.setTopBottom) == "function" then
        pcall(elem.setTopBottom, elem, is_rel_top, is_rel_bottom, top, bottom)
    end
end

local function safe_set_alignment(elem, align)
    if type(elem) ~= "table" then return end
    if type(elem.setAlignment) == "function" then
        pcall(elem.setAlignment, elem, align)
    elseif type(elem.SetAlignment) == "function" then
        pcall(elem.SetAlignment, elem, align)
    end
end

-- Remove element safely from hierarchy
local function safe_close(elem)
    if type(elem) ~= "table" then return end
    if type(elem.closeTree) == "function" then
        safe_call(elem.closeTree, elem)
    elseif type(elem.close) == "function" then
        safe_call(elem.close, elem)
    end
end

-- Safely add child to parent
local function safe_add_element(parent, child)
    if type(parent) ~= "table" or type(child) ~= "table" then return false end
    if type(parent.addElement) == "function" then
        return safe_call(parent.addElement, parent, child)
    end
    return false
end

-- Destroy and release entire HUD widget tree
function CrankedHUD.Destroy()
    if CrankedHUD.container ~= nil then
        safe_close(CrankedHUD.container)
        CrankedHUD.container = nil
    end
    CrankedHUD.status_label = nil
    CrankedHUD.timer_label = nil
    CrankedHUD.bar_bg = nil
    CrankedHUD.bar_fill = nil
    CrankedHUD.active = false
    CrankedHUD.last_sfx_second = -1
end

-- Construct HUD element hierarchy
function CrankedHUD.Create()
    if CrankedHUD.container ~= nil then
        return true
    end

    local parent = get_parent_container()
    if not parent then
        return false
    end

    local container = create_ui_element("UIElement")
    if not container then return false end

    -- Safe setup anchors: Top center (X: -150 to +150, Y: 40 to 120)
    safe_set_left_right(container, false, false, -150, 150)
    safe_set_top_bottom(container, true, false, 40, 120)
    safe_set_alpha(container, 0.0) -- Start hidden until state > 0

    -- 1. Status Title (CRANKED / ULTRA CRANKED / ESPERA PRIMER KILL)
    local status_label = create_ui_element("UIText") or create_ui_element("UIStyledText") or create_ui_element("UIElement")
    if status_label then
        safe_set_left_right(status_label, true, true, 0, 0)
        safe_set_top_bottom(status_label, true, false, 0, 22)
        safe_set_alignment(status_label, 2) -- Center alignment
        safe_set_text(status_label, "ESPERA PRIMER KILL")
        safe_set_rgb(status_label, 0.1, 0.9, 1.0)
        safe_set_alpha(status_label, 0.85)
        safe_add_element(container, status_label)
    end

    -- 2. Countdown Digits (XX.Xs)
    local timer_label = create_ui_element("UIText") or create_ui_element("UIStyledText") or create_ui_element("UIElement")
    if timer_label then
        safe_set_left_right(timer_label, true, true, 0, 0)
        safe_set_top_bottom(timer_label, true, false, 22, 62)
        safe_set_alignment(timer_label, 2) -- Center alignment
        safe_set_text(timer_label, "30.0s")
        safe_set_rgb(timer_label, 0.1, 0.9, 1.0)
        safe_set_alpha(timer_label, 0.75)
        safe_add_element(container, timer_label)
    end

    -- 3. Gauge Background Bar
    local bar_bg = create_ui_element("UIImage") or create_ui_element("UIElement")
    if bar_bg then
        safe_set_left_right(bar_bg, false, false, -132, 132)
        safe_set_top_bottom(bar_bg, true, false, 64, 76)
        safe_set_rgb(bar_bg, 0.05, 0.05, 0.08)
        safe_set_alpha(bar_bg, 0.7)
        safe_add_element(container, bar_bg)
    end

    -- 4. Gauge Dynamic Fill Bar
    local bar_fill = create_ui_element("UIImage") or create_ui_element("UIElement")
    if bar_fill then
        safe_set_left_right(bar_fill, false, false, -130, 130)
        safe_set_top_bottom(bar_fill, true, false, 66, 74)
        safe_set_rgb(bar_fill, 0.1, 0.9, 1.0)
        safe_set_alpha(bar_fill, 0.8)
        safe_add_element(container, bar_fill)
    end

    -- Attach container to parent root
    local attached = safe_add_element(parent, container)
    if not attached then
        safe_close(container)
        return false
    end

    CrankedHUD.container = container
    CrankedHUD.status_label = status_label
    CrankedHUD.timer_label = timer_label
    CrankedHUD.bar_bg = bar_bg
    CrankedHUD.bar_fill = bar_fill
    CrankedHUD.active = true
    return true
end

-- Frame update handler (20Hz refresh)
function CrankedHUD.Update()
    local core = rawget(_G, "CrankedCore")
    if type(core) ~= "table" then return end

    -- 1. Respetar Dvar scr_cranked: Si scr_cranked == 0, ocultar/destruir inmediatamente
    local scr_cranked
    if type(core.GetDvarInt) == "function" then
        scr_cranked = core.GetDvarInt("scr_cranked", nil)
    end
    if scr_cranked == 0 then
        if CrankedHUD.container ~= nil then
            safe_set_alpha(CrankedHUD.container, 0.0)
        end
        CrankedHUD.active = false
        return
    end

    -- 2. Verificar sesion en juego
    local in_game = CrankedHUD.IsInGame()
    if not in_game then
        if CrankedHUD.container ~= nil then
            safe_set_alpha(CrankedHUD.container, 0.0)
        end
        CrankedHUD.active = false
        return
    end

    -- 3. Crear elementos si no existen
    if CrankedHUD.container == nil then
        local ok = CrankedHUD.Create()
        if not ok or CrankedHUD.container == nil then return end
    end

    local state = tonumber(core.state) or 0
    local current_time = tonumber(core.current_time) or 0.0
    if current_time < 0.0 or current_time ~= current_time then
        current_time = 0.0
    end

    local max_time = tonumber(core.max_time) or 30.0
    if max_time <= 0.0 or max_time ~= max_time then
        max_time = 30.0
    end

    CrankedHUD.blink_counter = (CrankedHUD.blink_counter + 1) % 20
    local is_blink_on = CrankedHUD.blink_counter < 10

    -- State 0: Inactive / Lobby
    if state == 0 then
        safe_set_alpha(CrankedHUD.container, 0.0)
        CrankedHUD.active = false
        return
    end

    -- Mostrar contenedor activo
    safe_set_alpha(CrankedHUD.container, 1.0)
    CrankedHUD.active = true

    -- State 1: Esperando primera baja
    if state == 1 then
        safe_set_text(CrankedHUD.status_label, "ESPERA PRIMER KILL")
        safe_set_rgb(CrankedHUD.status_label, 0.1, 0.9, 1.0)
        safe_set_alpha(CrankedHUD.status_label, 0.85)

        safe_set_text(CrankedHUD.timer_label, string.format("%.1fs", max_time))
        safe_set_rgb(CrankedHUD.timer_label, 0.1, 0.9, 1.0)
        safe_set_alpha(CrankedHUD.timer_label, 0.75)

        -- Barra llena en estado de espera
        safe_set_left_right(CrankedHUD.bar_fill, false, false, -130, 130)
        safe_set_rgb(CrankedHUD.bar_fill, 0.1, 0.9, 1.0)
        safe_set_alpha(CrankedHUD.bar_fill, 0.5)

        CrankedHUD.last_sfx_second = -1
        return
    end

    -- State 2: Frenetico Activo
    if state == 2 then
        local round_num = tonumber(core.current_round) or 1
        local is_ultra = (core.is_ultra_cranked == true) or (round_num >= 31)
        if is_ultra then
            safe_set_text(CrankedHUD.status_label, "ULTRA CRANKED")
        else
            safe_set_text(CrankedHUD.status_label, "CRANKED")
        end
        safe_set_text(CrankedHUD.timer_label, string.format("%.1fs", current_time))

        -- Gradiente de color por nivel de amenaza
        local r, g, b, alpha
        if current_time > 10.0 then
            -- Seguro: Cian / Blanco electrico
            r, g, b = 0.85, 0.95, 1.0
            alpha = 1.0
            CrankedHUD.last_sfx_second = -1
        elseif current_time >= 5.0 then
            -- Advertencia: Ambar / Naranja
            r, g, b = 1.0, 0.65, 0.1
            alpha = 1.0
            CrankedHUD.last_sfx_second = -1
        else
            -- Critico (< 5s): Rojo parpadeante y pulso audible
            r, g, b = 1.0, 0.15, 0.15
            alpha = is_blink_on and 1.0 or 0.35

            local sec = math.floor(current_time)
            if sec ~= CrankedHUD.last_sfx_second and sec >= 0 then
                CrankedHUD.last_sfx_second = sec
                CrankedHUD.PlaySFX("uin_alert_lockon")
            end
        end

        local status_alpha = alpha
        if is_ultra then
            -- Parpadeo rapido para status label en ULTRA CRANKED
            local fast_blink = (CrankedHUD.blink_counter % 4) < 2
            status_alpha = fast_blink and 1.0 or 0.25
        end

        safe_set_rgb(CrankedHUD.status_label, r, g, b)
        safe_set_alpha(CrankedHUD.status_label, status_alpha)

        safe_set_rgb(CrankedHUD.timer_label, r, g, b)
        safe_set_alpha(CrankedHUD.timer_label, alpha)

        -- Barra de progreso proporcional al tiempo restante sin desincronizacion ni parpadeos
        local ratio = math.min(1.0, math.max(0.0, current_time / max_time))
        local fill_right = -130 + math.floor(260 * ratio)
        safe_set_left_right(CrankedHUD.bar_fill, false, false, -130, fill_right)
        safe_set_rgb(CrankedHUD.bar_fill, r, g, b)
        safe_set_alpha(CrankedHUD.bar_fill, alpha)
        return
    end

    -- State 3: Detonado / Tiempo Agotado
    if state == 3 then
        safe_set_text(CrankedHUD.status_label, "TIEMPO AGOTADO")
        local r, g, b = 1.0, 0.1, 0.1
        local alpha = is_blink_on and 1.0 or 0.2

        safe_set_rgb(CrankedHUD.status_label, r, g, b)
        safe_set_alpha(CrankedHUD.status_label, alpha)

        safe_set_text(CrankedHUD.timer_label, "0.0s")
        safe_set_rgb(CrankedHUD.timer_label, r, g, b)
        safe_set_alpha(CrankedHUD.timer_label, alpha)

        -- Barra completamente vacia
        safe_set_left_right(CrankedHUD.bar_fill, false, false, -130, -130)
        safe_set_rgb(CrankedHUD.bar_fill, r, g, b)
        safe_set_alpha(CrankedHUD.bar_fill, alpha)
        CrankedHUD.last_sfx_second = -1
        return
    end
end

-- Initialize refresh loop (20Hz / 50ms) with idempotency guard
function CrankedHUD.StartTimerLoop()
    if CrankedHUD.timer_element ~= nil or CrankedHUD.timer_running then
        return true
    end

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
        if ok then
            CrankedHUD.timer_running = true
            return true
        end
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
                CrankedHUD.timer_running = true
                return true
            end
        end
    end

    return false
end

-- Export globally and return module
rawset(_G, "CrankedHUD", CrankedHUD)

return CrankedHUD
