--[[
    Comprehensive & Destructive Test Suite for Cranked Mode (Black Ops 7)
    Targets: cranked-core.lua and cranked-hud.lua
    Validates authoritative GSC synchronization, standalone contingency,
    negative/destructive payloads, and UI resilience without forgiving mocks.
]]

local total_tests = 0
local total_assertions = 0

local function assert_eq(actual, expected, message)
    total_assertions = total_assertions + 1
    if actual ~= expected then
        error(string.format("[FAIL] %s: expected '%s', got '%s'",
            message or "Assertion failed", tostring(expected), tostring(actual)), 2)
    end
end

local function assert_true(condition, message)
    total_assertions = total_assertions + 1
    if condition ~= true then
        error(string.format("[FAIL] %s: expected true, got %s",
            message or "Assertion failed", tostring(condition)), 2)
    end
end

local function assert_near(actual, expected, eps, message)
    total_assertions = total_assertions + 1
    eps = eps or 0.001
    if math.abs((tonumber(actual) or 0) - (tonumber(expected) or 0)) > eps then
        error(string.format("[FAIL] %s: expected %s (+/-%s), got %s",
            message or "Near assertion failed", tostring(expected), tostring(eps), tostring(actual)), 2)
    end
end

local function run_test(name, fn)
    total_tests = total_tests + 1
    io.write(string.format("  [%02d] %s ... ", total_tests, name))
    io.flush()
    local ok, err = pcall(fn)
    if not ok then
        io.write("FAILED!\n")
        print(err)
        os.exit(1)
    else
        io.write("OK\n")
    end
end

print("======================================================================")
print("  CRANKED MODE RIGOROUS TEST SUITE - SATURN / KRONOS (BO7)")
print("======================================================================\n")

-- Helper to completely reset global environment between tests
local function reset_global_env()
    _G.Engine = nil
    _G.Dvar = nil
    _G.CLUA = nil
    _G.PushXHashDvar = nil
    _G.xhashdvar = nil
    _G.DataSources = nil
    _G._DataSources = nil
    _G.HudManager = nil
    _G.LUI = nil
    _G.ACTIONS = nil
    _G.CrankedCore = nil
    _G.CrankedHUD = nil
    package.loaded["cranked-core"] = nil
    package.loaded["cranked-hud"] = nil
end

-- ============================================================================
-- SUITE 1: DVAR ACCESSOR MULTI-STRATEGY FALLBACK & CRASH RESILIENCE
-- ============================================================================
print("SUITE 1: Safe Dvar Accessors & Multi-Strategy Fallback")

run_test("Strategy 1: Dvar.GetDvarString with name and hash key", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "2",
        ["cranked_time"] = "24.5"
    }
    _G.Dvar = {
        GetDvarString = function(key)
            return storage[key]
        end
    }

    local Core = dofile("cranked-core.lua")
    assert_eq(Core.GetDvarString("scr_cranked"), "1", "GetDvarString string")
    assert_eq(Core.GetDvarInt("scr_cranked"), 1, "GetDvarInt int")
    assert_near(Core.GetDvarFloat("cranked_time"), 24.5, 0.01, "GetDvarFloat float")
end)

run_test("Strategy 2: Dvar.GetDvarInt fallback when GetDvarString absent", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = 1,
        ["cranked_state"] = 2
    }
    _G.Dvar = {
        GetDvarInt = function(key)
            return storage[key]
        end
    }

    local Core = dofile("cranked-core.lua")
    assert_eq(Core.GetDvarInt("scr_cranked"), 1, "GetDvarInt strategy")
    assert_eq(Core.GetDvarString("cranked_state"), "2", "GetDvarString via GetDvarInt")
end)

run_test("Strategy 3: CLUA hash 0x254084d7ca2317bb (DV_GET_HASH)", function()
    reset_global_env()
    local storage = {
        ["xhash_scr_cranked"] = "1",
        ["xhash_cranked_time"] = "18.2"
    }
    _G.CLUA = {
        PushXHashDvar = function(name)
            return "xhash_" .. name
        end
    }
    _G.Dvar = {
        ["254084d7ca2317bb"] = function(key)
            return storage[key]
        end
    }

    local Core = dofile("cranked-core.lua")
    assert_eq(Core.GetDvarInt("scr_cranked"), 1, "CLUA getter int")
    assert_near(Core.GetDvarFloat("cranked_time"), 18.2, 0.01, "CLUA getter float")
end)

run_test("Strategy 4: Native crash in Dvar getter is caught by pcall", function()
    reset_global_env()
    _G.Dvar = {
        GetDvarString = function()
            error("CRITICAL NATIVE ACCESS VIOLATION 0xC0000005")
        end,
        GetDvarInt = function()
            error("NATIVE CALLSTACK CORRUPTION")
        end,
        ["254084d7ca2317bb"] = function()
            error("MEMORY BUS ERROR")
        end
    }

    local Core = dofile("cranked-core.lua")
    -- Must not raise an unhandled error; must return safe default
    assert_eq(Core.GetDvarRaw("scr_cranked"), nil, "Raw must return nil on crash")
    assert_eq(Core.GetDvarInt("scr_cranked", 0), 0, "Int must return default on crash")
    assert_eq(Core.GetDvarFloat("cranked_time", 30.0), 30.0, "Float must return default on crash")
end)

run_test("Strategy 5: Missing Dvar table or nil globals entirely", function()
    reset_global_env()
    -- No Dvar, no CLUA, no Engine
    local Core = dofile("cranked-core.lua")
    assert_eq(Core.GetDvarRaw("scr_cranked"), nil, "Nil Dvar raw")
    assert_eq(Core.GetDvarString("scr_cranked"), nil, "Nil Dvar string")
    assert_eq(Core.GetDvarInt("scr_cranked", 42), 42, "Nil Dvar default int")
    assert_eq(Core.GetDvarFloat("cranked_time", 99.5), 99.5, "Nil Dvar default float")
end)

-- ============================================================================
-- SUITE 2: DESTRUCTIVE / NEGATIVE PAYLOADS & STRICT TYPE VALIDATION
-- ============================================================================
print("\nSUITE 2: Destructive Dvar Payloads & Strict Type Sanitization")

run_test("Corrupted non-numeric strings in numeric Dvars", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = "NOT_A_NUMBER",
        ["cranked_state"] = "--INVALID_STATE--",
        ["cranked_time"] = "CORRUPT_BUFFER#@!",
        ["cranked_max"] = "NaN"
    }
    _G.Dvar = {
        GetDvarString = function(key) return storage[key] end
    }

    local Core = dofile("cranked-core.lua")
    assert_eq(Core.GetDvarInt("scr_cranked", nil), nil, "Invalid int returns fallback")
    assert_eq(Core.GetDvarFloat("cranked_time", nil), nil, "Invalid float returns fallback")

    -- Now tick with already_in_game = true
    Core.state = 1
    Core.max_time = 30.0
    Core.current_time = 30.0
    Core.Tick(0.1, true)

    -- Because scr_cranked is invalid (not 1 and not 0), it falls back to standalone
    -- It must NOT crash, max_time must remain positive and not NaN
    assert_true(Core.max_time > 0, "max_time must remain positive")
    assert_true(Core.current_time >= 0, "current_time must remain non-negative")
end)

run_test("Negative and zero max_time injection", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "2",
        ["cranked_time"] = "15.0",
        ["cranked_max"] = "-100.0", -- Destructive negative max
        ["cranked_kills"] = "-5",   -- Destructive negative kills
        ["cranked_round"] = "-1"    -- Destructive negative round
    }
    _G.Dvar = {
        GetDvarString = function(key) return storage[key] end
    }

    local Core = dofile("cranked-core.lua")
    Core.Tick(0.05, true)

    assert_true(Core.is_authoritative_gsc, "Must identify as GSC mode")
    assert_eq(Core.state, 2, "State must be 2")
    assert_near(Core.current_time, 15.0, 0.01, "Current time synchronized")
    assert_true(Core.max_time > 0, "max_time must reject <= 0 and fallback safely")
    assert_true(Core.last_kills >= 0, "kills must reject negative values")
    assert_true(Core.current_round >= 1, "round must reject negative values")
end)

run_test("NaN (0/0) and Infinity (1/0) Dvar injection", function()
    reset_global_env()
    local nan_val = 0 / 0
    local inf_val = 1 / 0
    local neg_inf = -1 / 0

    _G.Dvar = {
        GetDvarString = function(key)
            if key == "cranked_time" then return tostring(nan_val) end
            if key == "cranked_max" then return tostring(inf_val) end
            if key == "scr_cranked" then return tostring(neg_inf) end
            return nil
        end
    }

    local Core = dofile("cranked-core.lua")
    assert_eq(Core.GetDvarFloat("cranked_time", 25.0), 25.0, "NaN float returns default")
    assert_eq(Core.GetDvarFloat("cranked_max", 30.0), 30.0, "Inf float returns default")
    assert_eq(Core.GetDvarInt("scr_cranked", 0), 0, "Neg Inf int returns default")
end)

run_test("Corrupted delta_seconds in Tick()", function()
    reset_global_env()
    local Core = dofile("cranked-core.lua")
    Core.state = 2
    Core.current_time = 20.0
    Core.max_time = 30.0

    -- Pass NaN, negative, strings, nil as delta_seconds
    Core.Tick("BAD_DELTA", true)
    assert_true(Core.current_time < 20.0 and Core.current_time > 19.9, "Bad delta string fallback")

    Core.Tick(-5.0, true)
    assert_true(Core.current_time < 20.0, "Negative delta fallback")

    Core.Tick(0 / 0, true)
    assert_true(Core.current_time < 20.0, "NaN delta fallback")
end)

-- ============================================================================
-- SUITE 3: AUTHORITATIVE GSC SERVER SYNCHRONIZATION (0, 1, 2, 3)
-- ============================================================================
print("\nSUITE 3: Authoritative GSC State Machine Synchronization")

run_test("GSC: scr_cranked == 0 shuts down mode immediately (State 0)", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = "0",
        ["cranked_state"] = "2",
        ["cranked_time"] = "20.0"
    }
    _G.Dvar = {
        GetDvarString = function(key) return storage[key] end
    }

    local Core = dofile("cranked-core.lua")
    Core.state = 2
    Core.Tick(0.05, true)

    assert_eq(Core.state, 0, "Core state forced to 0 when scr_cranked == 0")
    assert_eq(Core.is_authoritative_gsc, false, "GSC auth false when disabled")
end)

run_test("GSC: State 0 (Server initialized, pre-spawn)", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "0"
    }
    _G.Dvar = {
        GetDvarString = function(key) return storage[key] end
    }

    local Core = dofile("cranked-core.lua")
    Core.Tick(0.05, true)

    assert_eq(Core.state, 0, "Core state must be 0")
    assert_true(Core.is_authoritative_gsc, "GSC authoritative mode recognized")
end)

run_test("GSC: State 1 (Waiting First Kill)", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "1",
        ["cranked_time"] = "30.0",
        ["cranked_max"] = "30.0",
        ["cranked_kills"] = "0",
        ["cranked_round"] = "1"
    }
    _G.Dvar = {
        GetDvarString = function(key) return storage[key] end
    }

    local Core = dofile("cranked-core.lua")
    Core.Tick(0.05, true)

    assert_eq(Core.state, 1, "Core state synchronized to 1")
    assert_near(Core.current_time, 30.0, 0.01, "Timer is 30.0s")
    assert_near(Core.max_time, 30.0, 0.01, "Max time is 30.0s")
    assert_eq(Core.last_kills, 0, "0 kills")
    assert_eq(Core.current_round, 1, "Round 1")
    assert_eq(Core.is_ultra_cranked, false, "Not ultra cranked")
end)

run_test("GSC: State 2 (Active Countdown & Kill updates)", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "2",
        ["cranked_time"] = "14.2",
        ["cranked_max"] = "20.0",
        ["cranked_kills"] = "12",
        ["cranked_round"] = "15"
    }
    _G.Dvar = {
        GetDvarString = function(key) return storage[key] end
    }

    local Core = dofile("cranked-core.lua")
    Core.Tick(0.05, true)

    assert_eq(Core.state, 2, "State 2 Active")
    assert_near(Core.current_time, 14.2, 0.01, "Current time synced from GSC")
    assert_near(Core.max_time, 20.0, 0.01, "Max time synced from GSC")
    assert_eq(Core.last_kills, 12, "Kills synced from GSC")
    assert_eq(Core.current_round, 15, "Round 15 synced")
    assert_eq(Core.is_ultra_cranked, false, "Round 15 is not ultra")

    -- Server updates Dvars on next server frame (kill registered)
    storage["cranked_time"] = "20.0"
    storage["cranked_kills"] = "13"
    Core.Tick(0.05, true)
    assert_near(Core.current_time, 20.0, 0.01, "Timer reset on kill synced from GSC")
    assert_eq(Core.last_kills, 13, "Kills incremented")
end)

run_test("GSC: Ultra Cranked detection on Round 31+", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "2",
        ["cranked_time"] = "7.5",
        ["cranked_max"] = "7.5",
        ["cranked_kills"] = "55",
        ["cranked_round"] = "31"
    }
    _G.Dvar = {
        GetDvarString = function(key) return storage[key] end
    }

    local Core = dofile("cranked-core.lua")
    Core.Tick(0.05, true)

    assert_eq(Core.state, 2, "State 2")
    assert_eq(Core.is_ultra_cranked, true, "Round 31 must trigger ultra cranked")
    assert_near(Core.max_time, 7.5, 0.01, "Max time 7.5s")
end)

run_test("GSC: State 3 (Detonated) and recovery sync", function()
    reset_global_env()
    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "3",
        ["cranked_time"] = "0.0",
        ["cranked_max"] = "25.0",
        ["cranked_kills"] = "5",
        ["cranked_round"] = "8"
    }
    _G.Dvar = {
        GetDvarString = function(key) return storage[key] end
    }

    local Core = dofile("cranked-core.lua")
    Core.Tick(0.05, true)

    assert_eq(Core.state, 3, "State 3 Detonated")
    assert_eq(Core.current_time, 0.0, "Time must be 0.0 upon detonation")

    -- Server respawns player and sets state back to 1
    storage["cranked_state"] = "1"
    storage["cranked_time"] = "25.0"
    Core.Tick(0.05, true)

    assert_eq(Core.state, 1, "Player respawned, synced back to State 1")
    assert_near(Core.current_time, 25.0, 0.01, "Timer restored")
end)

-- ============================================================================
-- SUITE 4: STANDALONE CONTINGENCY (DataSources LUI ENGINE)
-- ============================================================================
print("\nSUITE 4: Standalone Contingency Mode (LUI DataSources)")

local function setup_datasources(round_val, kills_val, party_val)
    local round_num = round_val or 1
    local kills_num = kills_val or 0
    local party_num = party_val or 1

    local ds = {
        inGame = {
            round = {
                GetValue = function(self, ctrl) return round_num end
            },
            player = {
                kills = {
                    GetValue = function(self, ctrl) return kills_num end
                }
            }
        },
        alwaysLoaded = {
            privateParty = {
                count = {
                    GetValue = function(self, ctrl) return party_num end
                }
            }
        }
    }
    _G._DataSources = ds
    return {
        set_round = function(r) round_num = r end,
        set_kills = function(k) kills_num = k end,
        set_party = function(p) party_num = p end
    }
end

run_test("Standalone: State 0 -> State 1 on match entry", function()
    reset_global_env()
    -- Dvars completely absent
    local ds_ctrl = setup_datasources(1, 0, 1)

    local Core = dofile("cranked-core.lua")
    assert_eq(Core.state, 0, "Initial state 0")

    Core.Tick(0.05, true)
    assert_eq(Core.state, 1, "Transitioned to State 1 Waiting")
    assert_eq(Core.is_authoritative_gsc, false, "Must be standalone")
    assert_near(Core.current_time, 30.0, 0.01, "Timer set to 30.0s")
    assert_near(Core.max_time, 30.0, 0.01, "Max time is 30.0s")
end)

run_test("Standalone: State 1 -> State 2 on first kill", function()
    reset_global_env()
    local ds_ctrl = setup_datasources(1, 0, 1)

    local Core = dofile("cranked-core.lua")
    Core.Tick(0.05, true)
    assert_eq(Core.state, 1, "State 1")

    -- No kill yet
    Core.Tick(0.05, true)
    assert_eq(Core.state, 1, "Still State 1")

    -- First kill occurs
    ds_ctrl.set_kills(1)
    Core.Tick(0.05, true)
    assert_eq(Core.state, 2, "Transitioned to State 2 Active")
    assert_eq(Core.last_kills, 1, "Last kills updated to 1")
    assert_near(Core.current_time, 30.0, 0.01, "Timer reset on activation")
end)

run_test("Standalone: State 2 timer decrement and kill refresh", function()
    reset_global_env()
    local ds_ctrl = setup_datasources(1, 1, 1)

    local Core = dofile("cranked-core.lua")
    Core.state = 2
    Core.last_kills = 1
    Core.current_time = 30.0
    Core.max_time = 30.0

    -- 1 second elapses (10 ticks of 0.1s)
    for _ = 1, 10 do
        Core.Tick(0.1, true)
    end
    assert_near(Core.current_time, 29.0, 0.05, "Timer decremented to ~29.0s")

    -- Player gets kill #2
    ds_ctrl.set_kills(2)
    Core.Tick(0.1, true)
    assert_eq(Core.state, 2, "State remains 2")
    assert_eq(Core.last_kills, 2, "Kills updated")
    assert_near(Core.current_time, 30.0, 0.01, "Timer reset back to max (30.0s)")
end)

run_test("Standalone: State 2 -> State 3 Detonation on timeout", function()
    reset_global_env()
    local kill_cmd_executed = false
    _G.Engine = {
        ExecNow = function(cmd, ctrl)
            if cmd == "kill" then kill_cmd_executed = true end
        end
    }
    local ds_ctrl = setup_datasources(1, 1, 1)

    local Core = dofile("cranked-core.lua")
    Core.state = 2
    Core.last_kills = 1
    Core.current_time = 0.1
    Core.max_time = 30.0

    -- Advance tick past remaining 0.1s
    Core.Tick(0.15, true)
    assert_eq(Core.state, 3, "Transitioned to State 3 Detonated")
    assert_eq(Core.current_time, 0.0, "Time is 0.0s")
    assert_true(kill_cmd_executed, "Lethal 'kill' command was executed")
end)

run_test("Standalone: State 3 recovery via timeout (5 seconds)", function()
    reset_global_env()
    local ds_ctrl = setup_datasources(1, 1, 1)

    local Core = dofile("cranked-core.lua")
    Core.state = 3
    Core.detonation_elapsed = 0
    Core.last_kills = 1

    -- Advance 4 seconds: should stay in State 3
    for _ = 1, 40 do
        Core.Tick(0.1, true)
    end
    assert_eq(Core.state, 3, "Still in State 3 after 4.0s")

    -- Advance 1.1 more seconds (total 5.1s >= 5.0s timeout)
    for _ = 1, 11 do
        Core.Tick(0.1, true)
    end
    assert_eq(Core.state, 1, "Recovered to State 1 Waiting after timeout")
end)

run_test("Standalone: State 3 recovery via fresh kill during last stand", function()
    reset_global_env()
    local ds_ctrl = setup_datasources(1, 1, 1)

    local Core = dofile("cranked-core.lua")
    Core.state = 3
    Core.detonation_elapsed = 1.0
    Core.last_kills = 1

    -- Kill registered in bleedout
    ds_ctrl.set_kills(2)
    Core.Tick(0.1, true)
    assert_eq(Core.state, 2, "Immediate recovery to State 2 Active upon kill")
    assert_near(Core.current_time, 30.0, 0.01, "Timer reset")
end)

run_test("Standalone: Destructive corrupt DataSources (failing GetValue)", function()
    reset_global_env()
    _G._DataSources = {
        inGame = {
            round = {
                GetValue = function() error("LUI DATA CRASH 0xDEADBEEF") end
            },
            player = {
                kills = {
                    GetValue = function() return "INVALID_KILLS" end
                }
            }
        },
        alwaysLoaded = {
            privateParty = {
                count = {
                    GetValue = function() return -50 end -- Negative party count
                }
            }
        }
    }

    local Core = dofile("cranked-core.lua")
    -- Must not raise errors; must return sanitized defaults
    assert_eq(Core.GetRoundNumber(), 1, "Round fallback 1")
    assert_eq(Core.GetPlayerKills(), 0, "Kills fallback 0")
    assert_eq(Core.GetPartyCount(), 1, "Party count fallback 1")
end)

-- ============================================================================
-- SUITE 5: CRANKED HUD ENGINE & THREAT GRADIENT VERIFICATION
-- ============================================================================
print("\nSUITE 5: Cranked HUD Engine & Threat Gradient Styling")

-- Lightweight mock of LUI UIElement hierarchy
local function create_mock_lui()
    local function new_elem(kind)
        local elem = {
            kind = kind,
            children = {},
            alpha = 1.0,
            text = "",
            r = 1, g = 1, b = 1,
            left = 0, right = 0, top = 0, bottom = 0,
            alignment = 0
        }
        function elem:setAlpha(a) self.alpha = tonumber(a) or 0 end
        function elem:SetAlpha(a) self.alpha = tonumber(a) or 0 end
        function elem:setText(t) self.text = tostring(t or "") end
        function elem:SetText(t) self.text = tostring(t or "") end
        function elem:setRGB(r, g, b)
            if type(r) == "table" then
                self.r, self.g, self.b = r.r, r.g, r.b
            else
                self.r, self.g, self.b = r, g, b
            end
        end
        function elem:SetRGB(r, g, b) self:setRGB(r, g, b) end
        function elem:setLeftRight(rl, rr, l, r)
            self.left, self.right = l, r
        end
        function elem:setTopBottom(rt, rb, t, b)
            self.top, self.bottom = t, b
        end
        function elem:setAlignment(a) self.alignment = a end
        function elem:addElement(c) table.insert(self.children, c) end
        function elem:closeTree() self.children = {} end
        function elem:close() self.children = {} end
        return elem
    end

    local root = new_elem("Root")
    local mock_lui = {
        primaryRoot = root,
        GetRoot = function() return root end,
        UIElement = { new = function() return new_elem("UIElement") end },
        UIText = { new = function() return new_elem("UIText") end },
        UIImage = { new = function() return new_elem("UIImage") end }
    }
    _G.LUI = mock_lui
    return root
end

run_test("HUD: scr_cranked == 0 immediately hides HUD", function()
    reset_global_env()
    create_mock_lui()
    local storage = {
        ["scr_cranked"] = "0"
    }
    _G.Dvar = {
        GetDvarString = function(k) return storage[k] end
    }

    local Core = dofile("cranked-core.lua")
    local HUD = dofile("cranked-hud.lua")

    -- Pre-create HUD container
    HUD.Create()
    assert_true(HUD.container ~= nil, "Container created")

    -- Call Update with scr_cranked == 0
    HUD.Update()
    assert_eq(HUD.container.alpha, 0.0, "HUD container must be hidden (alpha 0.0)")
    assert_eq(HUD.active, false, "HUD must not be active")
end)

run_test("HUD: State 1 (Waiting First Kill) rendering", function()
    reset_global_env()
    create_mock_lui()
    _G.Dvar = {
        GetDvarString = function(k)
            if k == "scr_cranked" then return "1" end
            if k == "cranked_state" then return "1" end
            if k == "cranked_time" then return "30.0" end
            if k == "cranked_max" then return "30.0" end
            return nil
        end
    }

    local Core = dofile("cranked-core.lua")
    local HUD = dofile("cranked-hud.lua")
    Core.Tick(0.05, true)
    HUD.Update()

    assert_true(HUD.container ~= nil, "Container exists")
    assert_eq(HUD.container.alpha, 1.0, "HUD is visible in State 1")
    assert_eq(HUD.status_label.text, "ESPERA PRIMER KILL", "Status label text")
    assert_eq(HUD.timer_label.text, "30.0s", "Timer label text")
    assert_eq(HUD.bar_fill.left, -130, "Bar fill left")
    assert_eq(HUD.bar_fill.right, 130, "Bar fill right (full bar)")
end)

run_test("HUD: State 2 Threat gradients (Safe > 10s, Warning 5-10s, Critical < 5s)", function()
    reset_global_env()
    create_mock_lui()
    local sfx_played = nil
    _G.ACTIONS = {
        PlaySoundSetSound = function(s) sfx_played = s end
    }

    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "2",
        ["cranked_time"] = "25.0",
        ["cranked_max"] = "30.0",
        ["cranked_round"] = "5"
    }
    _G.Dvar = {
        GetDvarString = function(k) return storage[k] end
    }

    local Core = dofile("cranked-core.lua")
    local HUD = dofile("cranked-hud.lua")

    -- Zone 1: Safe (> 10s)
    Core.Tick(0.05, true)
    HUD.Update()
    assert_eq(HUD.status_label.text, "CRANKED", "Title CRANKED")
    assert_near(HUD.status_label.r, 0.85, 0.05, "Safe color cyan R")
    assert_near(HUD.status_label.g, 0.95, 0.05, "Safe color cyan G")
    assert_near(HUD.status_label.b, 1.00, 0.05, "Safe color cyan B")
    assert_eq(sfx_played, nil, "No SFX in safe zone")

    -- Zone 2: Warning (5.0s to 10.0s)
    storage["cranked_time"] = "7.5"
    Core.Tick(0.05, true)
    HUD.Update()
    assert_near(HUD.status_label.r, 1.00, 0.05, "Warning amber R")
    assert_near(HUD.status_label.g, 0.65, 0.05, "Warning amber G")
    assert_eq(sfx_played, nil, "No SFX in warning zone")

    -- Zone 3: Critical (< 5.0s)
    storage["cranked_time"] = "3.2"
    Core.Tick(0.05, true)
    HUD.Update()
    assert_near(HUD.status_label.r, 1.00, 0.05, "Critical red R")
    assert_near(HUD.status_label.g, 0.15, 0.05, "Critical red G")
    assert_eq(sfx_played, "uin_alert_lockon", "SFX triggered in critical zone")
end)

run_test("HUD: Ultra Cranked title and blink on Round 31+", function()
    reset_global_env()
    create_mock_lui()
    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "2",
        ["cranked_time"] = "6.0",
        ["cranked_max"] = "7.5",
        ["cranked_round"] = "35"
    }
    _G.Dvar = {
        GetDvarString = function(k) return storage[k] end
    }

    local Core = dofile("cranked-core.lua")
    local HUD = dofile("cranked-hud.lua")
    Core.Tick(0.05, true)
    HUD.Update()

    assert_eq(HUD.status_label.text, "ULTRA CRANKED", "Title is ULTRA CRANKED")
end)

run_test("HUD: State 3 (Detonated) empty bar & TIEMPO AGOTADO", function()
    reset_global_env()
    create_mock_lui()
    local storage = {
        ["scr_cranked"] = "1",
        ["cranked_state"] = "3",
        ["cranked_time"] = "0.0",
        ["cranked_max"] = "30.0"
    }
    _G.Dvar = {
        GetDvarString = function(k) return storage[k] end
    }

    local Core = dofile("cranked-core.lua")
    local HUD = dofile("cranked-hud.lua")
    Core.Tick(0.05, true)
    HUD.Update()

    assert_eq(HUD.status_label.text, "TIEMPO AGOTADO", "Title TIEMPO AGOTADO")
    assert_eq(HUD.timer_label.text, "0.0s", "Timer label 0.0s")
    assert_eq(HUD.bar_fill.left, -130, "Bar fill left empty")
    assert_eq(HUD.bar_fill.right, -130, "Bar fill right empty (width = 0)")
end)

run_test("HUD: Destructive invalid values (zero max_time, negative time, NaN)", function()
    reset_global_env()
    create_mock_lui()

    local Core = dofile("cranked-core.lua")
    local HUD = dofile("cranked-hud.lua")

    Core.state = 2
    Core.current_time = -999.0  -- Negative time
    Core.max_time = 0.0         -- Zero max_time (division by zero risk)

    -- Must not raise an error, divide by zero, or output NaN
    HUD.Update()

    assert_true(HUD.container ~= nil, "Container valid")
    assert_eq(HUD.timer_label.text, "0.0s", "Negative time clamped to 0.0s")
    assert_eq(HUD.bar_fill.left, -130, "Bar fill clamped safely")
    assert_eq(HUD.bar_fill.right, -130, "Bar fill right clamped safely")
end)

print("\n======================================================================")
print(string.format("  ALL TESTS PASSED: %d tests, %d assertions verified.", total_tests, total_assertions))
print("======================================================================")

os.exit(0)
