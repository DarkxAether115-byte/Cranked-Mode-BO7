--[[
    Cranked Mode - Core Gameplay Engine
    Compatible with Call of Duty (Saturn / Kronos)
    Architecture: State machine with dynamic round scaling, safe pcall wrappers,
    authoritative GSC server synchronization, and standalone LUI DataSources contingency.
]]

local CrankedCore = {
    version = "1.2.0",
    state = 0, -- 0: Inactive/Lobby, 1: Waiting First Kill, 2: Active, 3: Detonated
    current_time = 0,
    max_time = 30,
    current_round = 1,
    party_count = 1,
    difficulty = "classic", -- "casual", "classic", "hardcore"
    is_ultra_cranked = false,
    is_cursed = false,
    last_kills = 0,
    inducer_disabled = false,
    active_controller = 0,
    detonation_elapsed = 0,
    is_authoritative_gsc = false
}

-- Constants and Engine Signatures
local DV_GET_HASH = "254084d7ca2317bb"
local DV_GET_XHASH = "0x254084d7ca2317bb"
local DV_INGAME = "b2d6f347952c7d99"
local RAMPAGE_INDUCER_DVAR = "#x354d97c81fc15dc50"
local RESPAWN_RECOVERY_TIMEOUT = 5.0 -- Seconds in detonated state before returning to waiting

-- Safe accessor helper
local function safe_call(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

-- Resolve Dvar key / hash safely using CLUA or global helpers if available
local function resolve_dvar_key(name)
    if type(name) ~= "string" or name == "" then return nil end
    local clua = rawget(_G, "CLUA")
    if type(clua) == "table" and type(rawget(clua, "PushXHashDvar")) == "function" then
        local ok, key = pcall(clua.PushXHashDvar, name)
        if ok and key ~= nil then return key end
    end
    local push_fn = rawget(_G, "PushXHashDvar") or rawget(_G, "xhashdvar")
    if type(push_fn) == "function" then
        local ok, key = pcall(push_fn, name)
        if ok and key ~= nil then return key end
    end
    return name
end

-- Robust multi-fallback Dvar accessor
-- Supports Dvar.GetDvarString, Dvar.GetDvarInt, CLUA hash 0x254084d7ca2317bb, and generic table indexing
function CrankedCore.GetDvarRaw(name)
    if type(name) ~= "string" or name == "" then return nil end
    local dvar = rawget(_G, "Dvar")
    if type(dvar) ~= "table" then return nil end

    local key = resolve_dvar_key(name)

    -- Strategy 1: Dvar.GetDvarString / Dvar.getDvarString
    local get_str = rawget(dvar, "GetDvarString") or rawget(dvar, "getDvarString")
    if type(get_str) == "function" then
        if key ~= nil then
            local ok, val = pcall(get_str, key)
            if ok and val ~= nil and val ~= "" then return val end
        end
        if key ~= name then
            local ok, val = pcall(get_str, name)
            if ok and val ~= nil and val ~= "" then return val end
        end
    end

    -- Strategy 2: Dvar.GetDvarInt / Dvar.getDvarInt
    local get_int = rawget(dvar, "GetDvarInt") or rawget(dvar, "getDvarInt")
    if type(get_int) == "function" then
        if key ~= nil then
            local ok, val = pcall(get_int, key)
            if ok and val ~= nil then return val end
        end
        if key ~= name then
            local ok, val = pcall(get_int, name)
            if ok and val ~= nil then return val end
        end
    end

    -- Strategy 3: CLUA hash 0x254084d7ca2317bb (DV_GET_HASH)
    local getter = rawget(dvar, DV_GET_HASH) or rawget(dvar, DV_GET_XHASH)
    if type(getter) == "function" then
        if key ~= nil then
            local ok, val = pcall(getter, key)
            if ok and val ~= nil and val ~= "" then return val end
        end
        if key ~= name then
            local ok, val = pcall(getter, name)
            if ok and val ~= nil and val ~= "" then return val end
        end
    end

    -- Strategy 4: Generic table get or raw index fallback
    local get_generic = rawget(dvar, "get") or rawget(dvar, "Get")
    if type(get_generic) == "function" then
        if key ~= nil then
            local ok, val = pcall(get_generic, key)
            if ok and val ~= nil and val ~= "" then return val end
        end
        local ok, val = pcall(get_generic, name)
        if ok and val ~= nil and val ~= "" then return val end
    end

    -- Direct table indexing if exposed as scalar field
    if rawget(dvar, name) ~= nil and type(rawget(dvar, name)) ~= "function" then
        return rawget(dvar, name)
    end

    return nil
end

-- Type-safe Dvar getters with strict validation (protecting against NaN / Inf / bad strings)
function CrankedCore.GetDvarString(name)
    local raw = CrankedCore.GetDvarRaw(name)
    if raw == nil then return nil end
    local str = tostring(raw)
    if str == "" then return nil end
    return str
end

function CrankedCore.GetDvarInt(name, default_val)
    local raw = CrankedCore.GetDvarRaw(name)
    if raw == nil then return default_val end
    local num = tonumber(raw)
    if num == nil or num ~= num or num == (1/0) or num == (-1/0) then
        return default_val
    end
    return math.floor(num)
end

function CrankedCore.GetDvarFloat(name, default_val)
    local raw = CrankedCore.GetDvarRaw(name)
    if raw == nil then return default_val end
    local num = tonumber(raw)
    if num == nil or num ~= num or num == (1/0) or num == (-1/0) then
        return default_val
    end
    return num
end

-- Native command execution
local function exec_command(cmd, controller)
    local engine = rawget(_G, "Engine")
    if type(engine) ~= "table" then return false end
    local exec_now = rawget(engine, "ExecNow")
    if type(exec_now) == "function" then
        local ok = pcall(exec_now, cmd, controller or 0)
        if ok then return true end
    end
    local exec_queued = rawget(engine, "Exec")
    if type(exec_queued) == "function" then
        return pcall(exec_queued, cmd, controller or 0)
    end
    return false
end

-- In-game status check with full pcall wrapper and Dvar fallback
function CrankedCore.IsInGame()
    local engine = rawget(_G, "Engine")
    if type(engine) == "table" and type(rawget(engine, "InFrontend")) == "function" then
        local ok, in_frontend = safe_call(engine.InFrontend)
        if ok and in_frontend == false then
            return true
        end
    end

    local ingame_val = CrankedCore.GetDvarRaw(DV_INGAME)
    if ingame_val ~= nil and tostring(ingame_val) == "1" then
        return true
    end

    return false
end

-- Neutralize Rampage Inducer
function CrankedCore.DisableRampageInducer(controller)
    if CrankedCore.inducer_disabled then return end
    local ok = exec_command("set " .. RAMPAGE_INDUCER_DVAR .. " 0", controller)
    if ok then
        CrankedCore.inducer_disabled = true
    end
end

-- Read player count from DataSources with strict type validation
function CrankedCore.GetPartyCount(controller)
    controller = controller or CrankedCore.active_controller or 0
    local data_sources = rawget(_G, "_DataSources") or rawget(_G, "DataSources")
    if type(data_sources) ~= "table" then return 1 end

    local always_loaded = rawget(data_sources, "alwaysLoaded") or rawget(data_sources, "always_loaded")
    if type(always_loaded) == "table" then
        local private_party = rawget(always_loaded, "privateParty") or rawget(always_loaded, "private_party")
        if type(private_party) == "table" then
            local count_source = rawget(private_party, "count") or rawget(private_party, "partyCount")
            if type(count_source) == "table" and type(rawget(count_source, "GetValue")) == "function" then
                local ok, val = safe_call(count_source.GetValue, count_source, controller)
                if ok and tonumber(val) then
                    local num = tonumber(val)
                    if num == num and num ~= (1/0) and num ~= (-1/0) then
                        return math.max(1, math.floor(num))
                    end
                end
            end
        end
    end
    return 1
end

-- Calculate time ceiling based on current round, party count, and difficulty preset
function CrankedCore.GetMaxTimeForRound(round_number, party_count, difficulty)
    local r = tonumber(round_number) or 1
    if r < 1 or r ~= r or r == (1/0) or r == (-1/0) then r = 1 end

    local count = tonumber(party_count) or CrankedCore.party_count or 1
    if count < 1 or count ~= count or count == (1/0) or count == (-1/0) then count = 1 end

    local diff = tostring(difficulty or CrankedCore.difficulty or "classic"):lower()

    -- Curva base (1 jugador, classic)
    local base_time
    if r <= 5 then
        base_time = 30.0
    elseif r <= 10 then
        base_time = 25.0
    elseif r <= 15 then
        base_time = 20.0
    elseif r <= 20 then
        base_time = 15.0
    elseif r <= 30 then
        base_time = 10.0
    else
        base_time = 7.5 -- 31+: Ultra Cranked
    end

    -- Variante Cursed: reduccion de tiempo base a 20s (o -5s con minimo de 10s)
    if CrankedCore.is_cursed then
        if base_time > 10.0 then
            base_time = math.max(10.0, base_time - 5.0)
            if base_time > 20.0 then
                base_time = 20.0
            end
        end
    end

    -- Escalado por escuadron (party_count)
    local squad_bonus = 0.0
    if count == 2 then
        squad_bonus = 3.0
    elseif count >= 3 then
        squad_bonus = 5.0
    end

    -- Modificador por preset de dificultad
    local diff_mod = 0.0
    if diff == "casual" then
        diff_mod = 5.0
    elseif diff == "hardcore" then
        diff_mod = -5.0
    end

    local final_time = base_time + squad_bonus + diff_mod
    -- Minimo 5.0s absoluto
    return math.max(5.0, final_time)
end

-- Read current round from DataSources
function CrankedCore.GetRoundNumber()
    local data_sources = rawget(_G, "_DataSources") or rawget(_G, "DataSources")
    if type(data_sources) ~= "table" then return 1 end

    local in_game = rawget(data_sources, "inGame") or rawget(data_sources, "in_game")
    if type(in_game) == "table" then
        local round_source = rawget(in_game, "round") or rawget(in_game, "roundNumber")
        if type(round_source) == "table" and type(rawget(round_source, "GetValue")) == "function" then
            local ok, val = safe_call(round_source.GetValue, round_source, CrankedCore.active_controller)
            if ok and tonumber(val) then
                local num = tonumber(val)
                if num == num and num ~= (1/0) and num ~= (-1/0) then
                    return math.max(1, math.floor(num))
                end
            end
        end
    end
    return 1
end

-- Read current kills from DataSources
function CrankedCore.GetPlayerKills()
    local data_sources = rawget(_G, "_DataSources") or rawget(_G, "DataSources")
    if type(data_sources) ~= "table" then return 0 end

    local in_game = rawget(data_sources, "inGame") or rawget(data_sources, "in_game")
    if type(in_game) == "table" then
        local player = rawget(in_game, "player")
        if type(player) == "table" then
            local kills_source = rawget(player, "kills") or rawget(player, "score")
            if type(kills_source) == "table" and type(rawget(kills_source, "GetValue")) == "function" then
                local ok, val = safe_call(kills_source.GetValue, kills_source, CrankedCore.active_controller)
                if ok and tonumber(val) then
                    local num = tonumber(val)
                    if num == num and num ~= (1/0) and num ~= (-1/0) then
                        return math.max(0, math.floor(num))
                    end
                end
            end
        end
    end
    return 0
end

-- Add bonus time (co-op assists, challenges) without exceeding max_time
function CrankedCore.AddBonusTime(seconds)
    local sec = tonumber(seconds) or 0
    if sec <= 0 or sec ~= sec or sec == (1/0) or sec == (-1/0) then return end
    CrankedCore.current_time = math.min(CrankedCore.max_time, CrankedCore.current_time + sec)
end

-- Set active controller
function CrankedCore.SetController(controller)
    CrankedCore.active_controller = controller or 0
end

-- Formally start match and initialize state
function CrankedCore.StartMatch(controller, is_cursed)
    CrankedCore.SetController(controller or 0)
    CrankedCore.is_cursed = (is_cursed == true)
    CrankedCore.state = 0
    CrankedCore.inducer_disabled = false
    CrankedCore.last_kills = 0
    CrankedCore.detonation_elapsed = 0
    CrankedCore.is_authoritative_gsc = false
    CrankedCore.ResetTimer()
end

-- Reset timer to current round limit
function CrankedCore.ResetTimer()
    CrankedCore.current_round = CrankedCore.GetRoundNumber()
    CrankedCore.party_count = CrankedCore.GetPartyCount(CrankedCore.active_controller)
    CrankedCore.is_ultra_cranked = (CrankedCore.current_round >= 31)
    CrankedCore.max_time = CrankedCore.GetMaxTimeForRound(
        CrankedCore.current_round,
        CrankedCore.party_count,
        CrankedCore.difficulty
    )
    if CrankedCore.max_time <= 0 or CrankedCore.max_time ~= CrankedCore.max_time then
        CrankedCore.max_time = 30.0
    end
    CrankedCore.current_time = CrankedCore.max_time
    CrankedCore.detonation_elapsed = 0
end

-- Execute lethal detonation
function CrankedCore.DetonatePlayer()
    CrankedCore.state = 3 -- Detonated
    CrankedCore.current_time = 0.0
    CrankedCore.detonation_elapsed = 0
    exec_command("kill", CrankedCore.active_controller)
end

-- Main tick function (called periodically with delta seconds)
function CrankedCore.Tick(delta_seconds, already_in_game)
    delta_seconds = tonumber(delta_seconds) or 0.05
    if delta_seconds <= 0 or delta_seconds ~= delta_seconds or delta_seconds == (1/0) then
        delta_seconds = 0.05
    end

    -- Check if we are inside a game (skip redundant engine probe if caller already verified)
    local in_game = (already_in_game == true) or CrankedCore.IsInGame()
    if not in_game then
        CrankedCore.state = 0
        CrankedCore.inducer_disabled = false
        CrankedCore.last_kills = 0
        CrankedCore.detonation_elapsed = 0
        CrankedCore.is_ultra_cranked = false
        CrankedCore.is_authoritative_gsc = false
        return
    end

    -- In-game: ensure Rampage Inducer is forced off
    if not CrankedCore.inducer_disabled then
        CrankedCore.DisableRampageInducer(CrankedCore.active_controller)
    end

    -- 1. Evaluacion de Dvars autoritativas del servidor GSC (zm_cranked.gsc)
    local scr_cranked = CrankedCore.GetDvarInt("scr_cranked", nil)

    -- Si scr_cranked == 0: Modo explicitamente desactivado por el servidor
    if scr_cranked == 0 then
        CrankedCore.state = 0
        CrankedCore.is_authoritative_gsc = false
        return
    end

    -- Si scr_cranked == 1: Sincronizacion autoritativa GSC
    if scr_cranked == 1 then
        local gsc_state = CrankedCore.GetDvarInt("cranked_state", nil)
        if gsc_state == 1 or gsc_state == 2 or gsc_state == 3 then
            -- MODO AUTORITATIVO GSC ACTIVO
            CrankedCore.is_authoritative_gsc = true
            CrankedCore.state = gsc_state

            -- Sincronizar tiempo actual
            local gsc_time = CrankedCore.GetDvarFloat("cranked_time", nil)
            if gsc_time ~= nil then
                CrankedCore.current_time = math.max(0.0, gsc_time)
            end

            -- Sincronizar tiempo maximo con validacion estricta (> 0)
            local gsc_max = CrankedCore.GetDvarFloat("cranked_max", nil)
            if gsc_max ~= nil and gsc_max > 0 then
                CrankedCore.max_time = gsc_max
            elseif CrankedCore.max_time <= 0 or CrankedCore.max_time ~= CrankedCore.max_time then
                CrankedCore.max_time = 30.0
            end

            -- Sincronizar bajas acumuladas
            local gsc_kills = CrankedCore.GetDvarInt("cranked_kills", nil)
            if gsc_kills ~= nil and gsc_kills >= 0 then
                CrankedCore.last_kills = gsc_kills
            end

            -- Sincronizar ronda
            local gsc_round = CrankedCore.GetDvarInt("cranked_round", nil)
            if gsc_round ~= nil and gsc_round >= 1 then
                CrankedCore.current_round = gsc_round
                CrankedCore.is_ultra_cranked = (gsc_round >= 31)
            end

            if gsc_state == 3 then
                CrankedCore.current_time = 0.0
            end

            return
        elseif gsc_state == 0 then
            -- Servidor GSC en espera (antes del spawn del jugador)
            CrankedCore.is_authoritative_gsc = true
            CrankedCore.state = 0
            return
        end
        -- Si gsc_state no es un valor valido, continua abajo hacia el modo de contingencia standalone
    end

    -- 2. MODO CONTINGENCIA / STANDALONE (DataSources de LUI)
    -- Se ejecuta si scr_cranked es nulo o las Dvars del servidor no existen
    CrankedCore.is_authoritative_gsc = false

    local current_kills = CrankedCore.GetPlayerKills()

    -- State 0 -> State 1: En juego, esperando primer kill
    if CrankedCore.state == 0 then
        CrankedCore.state = 1
        CrankedCore.last_kills = current_kills
        CrankedCore.ResetTimer()
        return
    end

    -- State 1: Esperando primera baja
    if CrankedCore.state == 1 then
        if current_kills > CrankedCore.last_kills then
            -- Primera baja confirmada: transicion a activo
            CrankedCore.state = 2
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
        elseif current_kills < CrankedCore.last_kills then
            -- Stats reseteadas por el motor
            CrankedCore.last_kills = current_kills
        end
        return
    end

    -- State 2: Frenetico Activo
    if CrankedCore.state == 2 then
        -- Comprobar nuevas bajas
        if current_kills > CrankedCore.last_kills then
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
        elseif current_kills < CrankedCore.last_kills then
            -- Engine reseteo kills mid-game, sincronizar
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
        else
            -- Decrementar temporizador de forma autonoma
            CrankedCore.current_time = CrankedCore.current_time - delta_seconds
            if CrankedCore.current_time <= 0 then
                CrankedCore.DetonatePlayer()
            end
        end
        return
    end

    -- State 3: Detonado (esperando respawn o timeout de recuperacion)
    if CrankedCore.state == 3 then
        CrankedCore.detonation_elapsed = CrankedCore.detonation_elapsed + delta_seconds

        -- Condicion 1 de recuperacion: Nueva baja registrada
        if current_kills > CrankedCore.last_kills then
            CrankedCore.state = 2
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
            return
        end

        -- Condicion 2 de recuperacion: Engine reseteo kills tras respawn
        if current_kills < CrankedCore.last_kills then
            CrankedCore.state = 1
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
            return
        end

        -- Condicion 3 de recuperacion: Timeout transcurrido, forzar retorno a espera
        if CrankedCore.detonation_elapsed >= RESPAWN_RECOVERY_TIMEOUT then
            CrankedCore.state = 1
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
            return
        end
    end
end

-- Export module globally
rawset(_G, "CrankedCore", CrankedCore)

return CrankedCore
