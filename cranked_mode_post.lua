--[[

    cranked_mode_post.lua

    Modo Frenetico / Cranked Mode HUD & Client Engine

    Compatible con Call of Duty (Saturn / Kronos BO7)

    Total Sequential Integration - Fairy Type III Engine

]]



local C = rawget(_G, "CLUA")

local HD = rawget(_G, "xhashdvar") or rawget(_G, "PushXHashDvar") or (type(C) == "table" and C.PushXHashDvar)

local H = rawget(_G, "xhash")



-- Dvar Accessors

local function dvarGet(name)
    if type(HD) ~= "function" or type(rawget(_G, "Dvar")) ~= "table" then return nil end
    local ok, v = pcall(function() return rawget(_G, "Dvar").GetDvarString(HD(name)) end)
    if ok and v ~= nil and v ~= "" then return tostring(v) end
    return nil
end

local function dvarSet(name, value)
    if type(HD) ~= "function" or type(rawget(_G, "Dvar")) ~= "table" then return false end
    pcall(function() rawget(_G, "Dvar").SetDvarString(HD(name), tostring(value)) end)
    return dvarGet(name) == tostring(value)
end

-- Singleton state container
local S = rawget(_G, "KronosCrankedClient")
if type(S) == "table" and S.version == 2 and S.ensureTimer then
    pcall(S.ensureTimer)
    return
end

S = {
    version = 2,
    enabled = true,
    active = false,
    container = nil,
    status_label = nil,
    timer_label = nil,
    bar_bg = nil,
    bar_fill = nil,
    timer_host = nil,
    last_sfx_second = -1,
    blink_counter = 0,
    -- Fallback local state if GSC is absent
    local_state = 1,
    local_time = 30.0,
    local_max = 30.0,
    local_kills = 0
}
rawset(_G, "KronosCrankedClient", S)

-- Safe setters
local function safe_set_text(elem, text)
    if type(elem) == "table" and type(elem.setText) == "function" then
        pcall(elem.setText, elem, tostring(text))
    end
end

local function safe_set_rgb(elem, r, g, b)
    if type(elem) == "table" and type(elem.SetRGB) == "function" then
        pcall(elem.SetRGB, elem, r, g, b)
    end
end

local function safe_set_alpha(elem, a)
    if type(elem) == "table" and type(elem.SetAlpha) == "function" then
        pcall(elem.SetAlpha, elem, a)
    end
end

local function safe_set_box(elem, lf, rf, tf, bf, l, r, t, b)
    if type(elem) == "table" and type(elem.SetAnchorsAndPosition) == "function" then
        pcall(elem.SetAnchorsAndPosition, elem, lf, rf, tf, bf, l, r, t, b)
    end
end

local function safe_close(elem)
    if type(elem) ~= "table" then return end
    if type(elem.closeTree) == "function" then
        pcall(elem.closeTree, elem)
    elseif type(elem.close) == "function" then
        pcall(elem.close, elem)
    end
end

-- In-Game Detector
local function IsInGame()
    local engine = rawget(_G, "Engine")
    if type(engine) == "table" and type(rawget(engine, "InFrontend")) == "function" then
        local ok, in_frontend = pcall(engine.InFrontend)
        if ok and in_frontend == false then
            return true
        end
    end
    return false
end

-- Safe Sound Trigger
local function PlaySFX(sound_name)
    sound_name = sound_name or "uin_alert_lockon"
    local actions = rawget(_G, "ACTIONS")
    if type(actions) == "table" and type(rawget(actions, "PlaySoundSetSound")) == "function" then
        pcall(actions.PlaySoundSetSound, sound_name)
    end
    local engine = rawget(_G, "Engine")
    if type(engine) == "table" and type(rawget(engine, "PlaySound")) == "function" then
        pcall(engine.PlaySound, sound_name)
    end
end

-- Resolve Root Element
local function GetRoot()
    local lui = rawget(_G, "LUI")
    if type(lui) ~= "table" then return nil end
    local ok, r = pcall(function() return lui.GetRoot() end)
    if ok and r then return r end
    return lui.primaryRoot
end

-- Build HUD Tree
local function BuildHUD()
    if S.container ~= nil then return true end
    local r = GetRoot()
    if not r then return false end

    local lui = rawget(_G, "LUI")
    if type(lui) ~= "table" or type(lui.UIElement) ~= "table" or type(lui.UIElement.new) ~= "function" then
        return false
    end

    -- Contenedor superior centrado
    local container = lui.UIElement.new()
    safe_set_box(container, 0.5, 0.5, 0, 0, -150, 150, 40, 120)
    safe_set_alpha(container, 1.0)

    -- Etiqueta de Estado (Superior: 0 a 22 px)
    local text_class = lui.UIStyledText or lui.UIText or lui.UIElement
    local status_label = text_class.new()
    safe_set_box(status_label, 0, 1, 0, 0, 0, 0, 0, 22)
    if type(status_label.setAlignment) == "function" then pcall(status_label.setAlignment, status_label, 2) end
    safe_set_text(status_label, "ESPERA PRIMER KILL")
    safe_set_rgb(status_label, 0.1, 0.9, 1.0)
    safe_set_alpha(status_label, 0.9)
    container:addElement(status_label)

    -- Etiqueta Digital de Temporizador (Medio: 22 a 62 px)
    local timer_label = text_class.new()
    safe_set_box(timer_label, 0, 1, 0, 0, 0, 0, 22, 62)
    if type(timer_label.setAlignment) == "function" then pcall(timer_label.setAlignment, timer_label, 2) end
    safe_set_text(timer_label, "30.0s")
    safe_set_rgb(timer_label, 0.9, 0.95, 1.0)
    safe_set_alpha(timer_label, 1.0)
    container:addElement(timer_label)

    -- Fondo de barra de progreso (Inferior: 66 a 74 px)
    local img_class = lui.UIImage or lui.UIElement
    local bar_bg = img_class.new()
    safe_set_box(bar_bg, 0.5, 0.5, 0, 0, -130, 130, 66, 74)
    safe_set_rgb(bar_bg, 0.05, 0.05, 0.08)
    safe_set_alpha(bar_bg, 0.6)
    container:addElement(bar_bg)

    -- Relleno de barra de progreso
    local bar_fill = img_class.new()
    safe_set_box(bar_fill, 0.5, 0.5, 0, 0, -130, 130, 66, 74)
    safe_set_rgb(bar_fill, 0.1, 0.9, 1.0)
    safe_set_alpha(bar_fill, 0.9)
    container:addElement(bar_fill)

    r:addElement(container)

    S.container = container
    S.status_label = status_label
    S.timer_label = timer_label
    S.bar_bg = bar_bg
    S.bar_fill = bar_fill
    S.active = true
    S.last_sfx_second = -1

    return true
end

-- Destroy HUD Tree
local function DestroyHUD()
    if S.container ~= nil then
        safe_close(S.container)
    end
    S.container = nil
    S.status_label = nil
    S.timer_label = nil
    S.bar_bg = nil
    S.bar_fill = nil
    S.active = false
    S.last_sfx_second = -1
    S.blink_counter = 0
end

-- Render Update Frame (20Hz)
local function UpdateFrame()
    if not IsInGame() then
        if S.active then DestroyHUD() end
        return
    end

    -- Comprobar si scr_cranked esta habilitado
    local scr = dvarGet("scr_cranked")
    if scr == "0" then
        if S.active then DestroyHUD() end
        return
    end

    if not S.active or S.container == nil then
        local ok = BuildHUD()
        if not ok then return end
    end

    -- Sincronizar estado con Dvars de GSC
    local gsc_state_str = dvarGet("cranked_state")
    local state = tonumber(gsc_state_str) or S.local_state
    local time = tonumber(dvarGet("cranked_time")) or S.local_time
    local max_t = tonumber(dvarGet("cranked_max")) or S.local_max
    if max_t <= 0 then max_t = 30.0 end
    local round_num = tonumber(dvarGet("cranked_round")) or 1

    S.blink_counter = (S.blink_counter + 1) % 20
    local is_blink_on = S.blink_counter < 10

    -- Estado 0: Desactivado
    if state == 0 then
        safe_set_alpha(S.container, 0.0)
        return
    end

    safe_set_alpha(S.container, 1.0)

    -- Estado 1: Esperando primer kill
    if state == 1 then
        safe_set_text(S.status_label, "ESPERA PRIMER KILL")
        safe_set_rgb(S.status_label, 0.1, 0.9, 1.0)
        safe_set_alpha(S.status_label, 0.85)

        safe_set_text(S.timer_label, string.format("%.1fs", max_t))
        safe_set_rgb(S.timer_label, 0.1, 0.9, 1.0)
        safe_set_alpha(S.timer_label, 0.75)

        safe_set_box(S.bar_fill, 0.5, 0.5, 0, 0, -130, 130, 66, 74)
        safe_set_rgb(S.bar_fill, 0.1, 0.9, 1.0)
        safe_set_alpha(S.bar_fill, 0.5)

        S.last_sfx_second = -1
        return
    end

    -- Estado 2: Frenetico Activo
    if state == 2 then
        local is_ultra = (round_num >= 31)
        local title = is_ultra and "ULTRA CRANKED" or "CRANKED"
        safe_set_text(S.status_label, title)
        safe_set_text(S.timer_label, string.format("%.1fs", math.max(0.0, time)))

        -- Gradiente de amenaza y feedback auditivo
        local r, g, b, alpha
        if time > 10.0 then
            -- Seguro: Azul Electrico / Blanco Cian
            r, g, b = 0.1, 0.9, 1.0
            alpha = 1.0
            S.last_sfx_second = -1
        elseif time >= 5.0 then
            -- Advertencia: Ambar / Naranja
            r, g, b = 1.0, 0.65, 0.1
            alpha = 1.0
            S.last_sfx_second = -1
        else
            -- Critico (< 5s): Rojo parpadeante y pulso sonoro
            r, g, b = 1.0, 0.15, 0.15
            alpha = is_blink_on and 1.0 or 0.35

            local sec = math.floor(time)
            if sec ~= S.last_sfx_second and sec >= 0 then
                S.last_sfx_second = sec
                PlaySFX("uin_alert_lockon")
            end
        end

        local status_alpha = alpha
        if is_ultra then
            status_alpha = ((S.blink_counter % 4) < 2) and 1.0 or 0.3
        end

        safe_set_rgb(S.status_label, r, g, b)
        safe_set_alpha(S.status_label, status_alpha)

        safe_set_rgb(S.timer_label, r, g, b)
        safe_set_alpha(S.timer_label, alpha)

        -- Barra de progreso proporcional al tiempo restante
        local ratio = math.min(1.0, math.max(0.0, time / max_t))
        local fill_right = -130 + math.floor(260 * ratio)
        safe_set_box(S.bar_fill, 0.5, 0.5, 0, 0, -130, fill_right, 66, 74)
        safe_set_rgb(S.bar_fill, r, g, b)
        safe_set_alpha(S.bar_fill, alpha)
        return
    end

    -- Estado 3: Detonado / Tiempo Agotado
    if state == 3 then
        safe_set_text(S.status_label, "TIEMPO AGOTADO")
        safe_set_rgb(S.status_label, 1.0, 0.1, 0.1)
        safe_set_alpha(S.status_label, is_blink_on and 1.0 or 0.2)

        safe_set_text(S.timer_label, "0.0s")
        safe_set_rgb(S.timer_label, 1.0, 0.1, 0.1)
        safe_set_alpha(S.timer_label, is_blink_on and 1.0 or 0.2)

        safe_set_box(S.bar_fill, 0.5, 0.5, 0, 0, -130, -130, 66, 74)
        safe_set_rgb(S.bar_fill, 1.0, 0.1, 0.1)
        safe_set_alpha(S.bar_fill, 0.2)
        S.last_sfx_second = -1
        return
    end
end

-- Continuous resilient timer loop (attaches to active root)
local function ensureTimer()
    if not S.enabled then return end
    local r = GetRoot()
    if not r then return end

    if S.timer_host then
        local ok, parent = pcall(function() return S.timer_host:getParent() end)
        if ok and parent == r then return end
        safe_close(S.timer_host)
        S.timer_host = nil
    end

    local ok = pcall(function()
        local host = rawget(_G, "LUI").UIElement.new()
        pcall(function() host:SetHandleMouse(false) end)
        pcall(function() host:setFocusable(false) end)
        r:addElement(host)
        S.timer_host = host

        local function schedule()
            if not S.enabled or S.timer_host ~= host then return end
            local anim = host:Wait(50) -- 50ms (20Hz update loop)
            if not anim then S.timer_host = nil; return end
            anim.onComplete = function()
                if not S.enabled or S.timer_host ~= host then return end
                pcall(UpdateFrame)
                pcall(schedule)
            end
        end
        schedule()
    end)
    if not ok then S.timer_host = nil end
end

S.ensureTimer = ensureTimer
pcall(ensureTimer)
