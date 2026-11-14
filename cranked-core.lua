--[[
    Cranked Mode - Core Gameplay Engine
    Compatible with Call of Duty (Saturn / Kronos)
    Architecture: State machine with dynamic round scaling and safe pcall wrappers
]]

local CrankedCore = {
    version = "1.1.0",
    state = 0, -- 0: Inactive/Lobby, 1: Waiting First Kill, 2: Active, 3: Detonated
    current_time = 0,
    max_time = 30,
    current_round = 1,
    party_count = 1,
    difficulty = "classic", -- "casual", "classic", "hardcore"
    is_ultra_cranked = false,
    last_kills = 0,
    inducer_disabled = false,
    active_controller = 0,
    detonation_elapsed = 0
}

-- Constants and Engine Signatures
local DV_GET = "254084d7ca2317bb"
local DV_INGAME = "b2d6f347952c7d99"
local RAMPAGE_INDUCER_DVAR = "#x354d97c81fc15dc50"
local RESPAWN_RECOVERY_TIMEOUT = 5.0 -- Seconds in detonated state before returning to waiting

-- Safe accessor helper
local function safe_call(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
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

-- In-game status check with full pcall wrapper
function CrankedCore.IsInGame()
    local engine = rawget(_G, "Engine")
    if type(engine) == "table" and type(rawget(engine, "InFrontend")) == "function" then
        local ok, in_frontend = safe_call(engine.InFrontend)
        if ok and in_frontend == false then
            return true
        end
    end

    local dvar = rawget(_G, "Dvar")
    local clua = rawget(_G, "CLUA")
    if type(dvar) == "table" and type(clua) == "table" and type(clua.PushXHashDvar) == "function" then
        local getter = rawget(dvar, DV_GET)
        if type(getter) == "function" then
            local ok, val = pcall(function()
                local hash_key = clua.PushXHashDvar(DV_INGAME)
                return getter(hash_key)
            end)
            if ok and tostring(val) == "1" then
                return true
            end
        end
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

-- Read player count from DataSources
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
                    return math.max(1, math.floor(tonumber(val)))
                end
            end
        end
    end
    return 1
end

-- Calculate time ceiling based on current round, party count, and difficulty preset
function CrankedCore.GetMaxTimeForRound(round_number, party_count, difficulty)
    local r = tonumber(round_number) or 1
    local count = tonumber(party_count) or CrankedCore.party_count or 1
    local diff = tostring(difficulty or CrankedCore.difficulty or "classic"):lower()

    -- Curva base (1 jugador, classic)
    local base_time
    if r <= 5 then
        base_time = 30
    elseif r <= 10 then
        base_time = 25
    elseif r <= 15 then
        base_time = 20
    elseif r <= 20 then
        base_time = 15
    elseif r <= 30 then
        base_time = 10
    else
        base_time = 7.5 -- 31+: Ultra Cranked
    end

    -- Escalado por escuadron (party_count)
    local squad_bonus = 0
    if count == 2 then
        squad_bonus = 3
    elseif count >= 3 then
        squad_bonus = 5
    end

    -- Modificador por preset de dificultad
    local diff_mod = 0
    if diff == "casual" then
        diff_mod = 5
    elseif diff == "hardcore" then
        diff_mod = -5
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
                return math.max(1, math.floor(tonumber(val)))
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
                    return math.max(0, math.floor(tonumber(val)))
                end
            end
        end
    end
    return 0
end

-- Add bonus time (co-op assists, challenges) without exceeding max_time
function CrankedCore.AddBonusTime(seconds)
    local sec = tonumber(seconds) or 0
    if sec <= 0 then return end
    CrankedCore.current_time = math.min(CrankedCore.max_time, CrankedCore.current_time + sec)
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
    CrankedCore.current_time = CrankedCore.max_time
    CrankedCore.detonation_elapsed = 0
end

-- Execute lethal detonation
function CrankedCore.DetonatePlayer()
    CrankedCore.state = 3 -- Detonated
    CrankedCore.current_time = 0
    CrankedCore.detonation_elapsed = 0
    exec_command("kill", CrankedCore.active_controller)
end

-- Main tick function (called periodically with delta seconds)
function CrankedCore.Tick(delta_seconds)
    delta_seconds = tonumber(delta_seconds) or 0.05

    -- Check if we are inside a game
    if not CrankedCore.IsInGame() then
        CrankedCore.state = 0
        CrankedCore.inducer_disabled = false
        CrankedCore.last_kills = 0
        CrankedCore.detonation_elapsed = 0
        CrankedCore.is_ultra_cranked = false
        return
    end

    -- In-game: ensure Rampage Inducer is forced off
    if not CrankedCore.inducer_disabled then
        CrankedCore.DisableRampageInducer(CrankedCore.active_controller)
    end

    local current_kills = CrankedCore.GetPlayerKills()

    -- State 0 -> State 1: In game, waiting for first kill
    if CrankedCore.state == 0 then
        CrankedCore.state = 1
        CrankedCore.last_kills = current_kills
        CrankedCore.ResetTimer()
        return
    end

    -- State 1: Waiting for first kill
    if CrankedCore.state == 1 then
        if current_kills > CrankedCore.last_kills then
            -- First kill confirmed: transition to active
            CrankedCore.state = 2
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
        elseif current_kills < CrankedCore.last_kills then
            -- Stats reset by engine
            CrankedCore.last_kills = current_kills
        end
        return
    end

    -- State 2: Cranked Active
    if CrankedCore.state == 2 then
        -- Check for new kills
        if current_kills > CrankedCore.last_kills then
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
        elseif current_kills < CrankedCore.last_kills then
            -- Engine reset kills mid-game, synchronize
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
        else
            -- Decrement timer
            CrankedCore.current_time = CrankedCore.current_time - delta_seconds
            if CrankedCore.current_time <= 0 then
                CrankedCore.DetonatePlayer()
            end
        end
        return
    end

    -- State 3: Detonated (waiting for respawn or recovery)
    if CrankedCore.state == 3 then
        CrankedCore.detonation_elapsed = CrankedCore.detonation_elapsed + delta_seconds

        -- Recovery condition 1: New kill registered
        if current_kills > CrankedCore.last_kills then
            CrankedCore.state = 2
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
            return
        end

        -- Recovery condition 2: Engine reset kills upon respawn
        if current_kills < CrankedCore.last_kills then
            CrankedCore.state = 1
            CrankedCore.last_kills = current_kills
            CrankedCore.ResetTimer()
            return
        end

        -- Recovery condition 3: Timeout elapsed, force return to waiting state
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
