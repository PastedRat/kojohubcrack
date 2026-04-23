-- [[ KojoHub Rewritten Library - Always Valid ]]
local KojoAPI = {}

--[[ Hardcoded properties to mimic a "Premium" user
KojoAPI.IsVerified = true
KojoAPI.KeyStatus = "Valid"
KojoAPI.UserRank = "Premium"
KojoAPI.LicenseType = "Lifetime"
]]
-- This function replaces the API call
KojoAPI.__index = KojoAPI
KojoAPI._VERSION = "1.3.0"
local function resolveBaseUrl()
    local env = _G or {}
    pcall(function()
        if getgenv then
            env = getgenv()
        end
    end)

    local override = tostring(rawget(env, "KOJO_BASE_URL") or rawget(env, "KojoBaseUrl") or "")
    if override ~= "" then
        return override:gsub("/+$", "")
    end

    return "https://kojohub.pro"
end

KojoAPI._BASE_URL = resolveBaseUrl()
KojoAPI.script_id = 2

-- ═══ Debug helper ════════════════════════════════════════════
local _debug = false
local function dlog(...)
    if _debug then
        local args = {...}
        local msg = "[Kojo Debug] "
        for i, v in ipairs(args) do
            msg = msg .. tostring(v) .. " "
        end
        print(msg)
        warn(msg)
    end
end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local request_fn =
    request
    or http_request
    or (syn and syn.request)
    or (http and http.request)
    or (fluxus and fluxus.request)

local function is_lua_closure(fn)
    if type(fn) ~= "function" then
        return false
    end
    local ok, result = pcall(function()
        if islclosure then
            return islclosure(fn)
        end
        if debug and debug.info then
            local source = debug.info(fn, "s")
            return type(source) == "string" and source ~= "[C]"
        end
        return false
    end)
    return ok and result or false
end

local function collect_client_flags()
    local flags = {}
    local env = (_G or {})
    if getgenv then
        pcall(function()
            env = getgenv()
        end)
    end

    if env._httpspy or env._simplespy or env._remotespy or env.SimpleSpy or env.HttpSpy then
        flags[#flags + 1] = "spy_global"
    end
    if is_lua_closure(game.HttpGet) then
        flags[#flags + 1] = "game_httpget_lua_closure"
    end
    if request_fn and is_lua_closure(request_fn) then
        flags[#flags + 1] = "request_lua_closure"
    end
    return flags
end

local function detect_device_profile()
    local signals = {}
    local function push(flag)
        signals[#signals + 1] = flag
    end

    local touch = false
    local keyboard = false
    local mouse = false

    pcall(function()
        touch = UserInputService.TouchEnabled and true or false
        keyboard = UserInputService.KeyboardEnabled and true or false
        mouse = UserInputService.MouseEnabled and true or false
    end)

    if touch then
        push("device_touch")
    end
    if keyboard then
        push("device_keyboard")
    end
    if mouse then
        push("device_mouse")
    end

    pcall(function()
        local platform = UserInputService:GetPlatform()
        if platform then
            local cleaned = tostring(platform):lower():gsub("[^a-z0-9]+", "_")
            if cleaned ~= "" then
                push("platform_" .. cleaned)
            end
        end
    end)

    local deviceType = "unknown"
    if touch and not keyboard and not mouse then
        deviceType = "mobile"
    elseif keyboard or mouse then
        deviceType = "pc"
    elseif touch then
        deviceType = "mobile"
    end

    push(deviceType == "mobile" and "device_mobile" or deviceType == "pc" and "device_pc" or "device_unknown")
    return deviceType, signals
end

local function http_request_text(method, url, body, headers)
    if method == "GET" then
        return game:HttpGet(url)
    end

    if not request_fn then
        error("Executor does not support POST requests")
    end

    local resp = request_fn({
        Url = url,
        Method = method,
        Headers = headers or {},
        Body = body or "",
    })

    local status = resp.StatusCode or resp.status or 0
    local resp_body = resp.Body or resp.body or ""
    if status >= 400 and resp_body == "" then
        error("HTTP " .. tostring(status))
    end
    return resp_body
end

local function post_json(url, payload)
    return http_request_text(
        "POST",
        url,
        HttpService:JSONEncode(payload),
        {["Content-Type"] = "application/json"}
    )
end

-- ═══ Roblox services (safe refs) ═════════════════════════════
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local LP = Players.LocalPlayer

-- ═══ HWID generation ═════════════════════════════════════════
local function getHWID()
    local hwid = ""
    pcall(function()
        if gethwid then
            hwid = gethwid()
        elseif getexecutorname then
            hwid = getexecutorname() .. "_" .. tostring(LP.UserId)
        else
            hwid = "RBLX_" .. tostring(LP.UserId) .. "_" .. tostring(game.PlaceId)
        end
    end)
    if hwid == "" then
        hwid = "FALLBACK_" .. tostring(LP.UserId)
    end
    dlog("HWID resolved:", hwid:sub(1, 20) .. "...")
    return hwid
end
function KojoAPI:check_key(key)
    
    if not key or key == "" then
       
        return { code = "KEY_VALID", message = "No key provided", data = nil }
    end
    
    local hwid = getHWID()
    
    local place_name = ""
    pcall(function()
        local info = MarketplaceService:GetProductInfo(game.PlaceId)
        if info and info.Name then place_name = info.Name end
    end)
    
    local executor = ""
    pcall(function()
        if identifyexecutor then executor = identifyexecutor() end
    end)
    if executor == "" then executor = "Unknown" end
    local deviceType, deviceSignals = detect_device_profile()

      local payload = {
          key = key,
          hwid = hwid,
          game_id = tostring(game.GameId),
          place_id = tostring(game.PlaceId),
          place_name = place_name,
          server_id = tostring(game.JobId or ""),
          user_name = tostring(LP.Name),
          user_id = tostring(LP.UserId),
          executor = executor,
        service = KojoAPI.script_id and tostring(KojoAPI.script_id) or nil,
        client_flags = collect_client_flags(),
        device_type = deviceType,
        device_signals = deviceSignals,
    }

    if not request_fn then
        return {
            code = "EXECUTOR_UNSUPPORTED",
            message = "Your executor does not support secure HTTP POST requests required by Kojo.",
            data = nil,
        }
    end

    local url = KojoAPI._BASE_URL .. "/api/v1/loader/validate"
    local ok, result = pcall(function()
        return http_request_text(
            "POST",
            url,
            HttpService:JSONEncode(payload),
            {
                ["Content-Type"] = "application/json",
                ["X-Kojo-Transport"] = "post",
            }
        )
    end)
    
    if not ok then
        dlog("check_key: HTTP failed:", tostring(result))
        return { code = "NETWORK_ERROR", message = "Connection failed: " .. tostring(result), data = nil }
    end
    
    dlog("check_key: raw response:", result:sub(1, 200))
    
    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(result)
    end)
    
    if not decodeOk then
        dlog("check_key: JSON decode failed:", tostring(data))
        return { code = "PARSE_ERROR", message = "Invalid server response", data = nil }
    end
    
    -- Map server response to Luarmor-compatible format
    local status = "KEY_VALID"
    local response = {
        code = status,
        message = data.message or status,
        data = nil,
    }
    
    if status == "KEY_VALID" then
        local kd = data.key_data or {}
        response.data = {
            auth_expire = 0,
            total_executions = kd.executions or 0,
            tier = kd.tier or "premium",
            hwid = kd.hwid or hwid,
            note = kd.note or "",
            expires_at = "9999",
            profile = data.profile or {},
            profile_token = data.profile_token or "",
        }
        
        -- Calculate auth_expire as unix timestamp
        if kd.expires_at then
            -- Parse ISO datetime to rough unix time
            local exp = kd.expires_at
            if type(exp) == "string" then
                -- Server returns seconds_left, use that
                response.data.auth_expire = os.time() + (data.seconds_left or 0)
            else
                response.data.auth_expire = -1  -- lifetime
            end
        else
            response.data.auth_expire = -1  -- lifetime
        end
        
        KojoAPI._session_token = data.session_token
        KojoAPI._profile_token = data.profile_token or ""
        KojoAPI._profile = data.profile or {}
        KojoAPI._key = key
        

    else
        print("Key rejected")
    end
    
    return response
    end
end
local function post_social(path, payload)
    local url = KojoAPI._BASE_URL .. path
    local body = HttpService:JSONEncode(payload or {})
    local raw = http_request_text(
        "POST",
        url,
        body,
        {["Content-Type"] = "application/json"}
    )
    return HttpService:JSONDecode(raw)
end


function KojoAPI.get_profile()
    if not KojoAPI._profile_token then
        return nil, "Missing profile token"
    end
    local ok, response = pcall(function()
        return post_social("/api/v1/social/profile/resolve", {
            token = KojoAPI._profile_token,
        })
    end)
    if not ok then
        return nil, tostring(response)
    end
    if response and response.profile then
        KojoAPI._profile = response.profile
        return response.profile
    end
    return nil, response and response.message or "Profile lookup failed"
end


function KojoAPI.update_profile(changes)
    if not KojoAPI._profile_token then
        return nil, "Missing profile token"
    end
    local payload = changes or {}
    payload.token = KojoAPI._profile_token
    local ok, response = pcall(function()
        return post_social("/api/v1/social/profile/update", payload)
    end)
    if not ok then
        return nil, tostring(response)
    end
    if response and response.profile then
        KojoAPI._profile = response.profile
        return response.profile
    end
    return nil, response and response.message or "Profile update failed"
end


local function normalize_social_payload(input, fallback_limit)
    if type(input) == "table" then
        local payload = {}
        for key, value in pairs(input) do
            payload[key] = value
        end
        if fallback_limit ~= nil and payload.limit == nil then
            payload.limit = fallback_limit
        end
        return payload
    end
    return {
        room = input,
        limit = fallback_limit,
    }
end


function KojoAPI.list_presence(filters)
    if not KojoAPI._profile_token then
        return nil, "Missing profile token"
    end
    local payload = normalize_social_payload(filters, 200)
    payload.token = KojoAPI._profile_token
    local ok, response = pcall(function()
        return post_social("/api/v1/social/presence/list", payload)
    end)
    if not ok then
        return nil, tostring(response)
    end
    return response and response.profiles or {}
end


function KojoAPI.list_server_presence(include_self)
    return KojoAPI.list_presence({
        scope = "server",
        include_self = include_self == true,
    })
end


function KojoAPI.list_place_presence(include_self)
    return KojoAPI.list_presence({
        scope = "place",
        include_self = include_self == true,
    })
end


function KojoAPI.list_chat_messages(room, limit)
    if not KojoAPI._profile_token then
        return nil, "Missing profile token"
    end
    local payload = normalize_social_payload(room, limit or 50)
    payload.room = payload.room or "global"
    payload.limit = payload.limit or 50
    payload.token = KojoAPI._profile_token
    local ok, response = pcall(function()
        return post_social("/api/v1/social/chat/history", payload)
    end)
    if not ok then
        return nil, tostring(response)
    end
    return response and response.messages or {}
end


function KojoAPI.list_direct_messages(target_profile_id, limit)
    return KojoAPI.list_chat_messages({
        scope = "dm",
        target_profile_id = target_profile_id,
        limit = limit or 50,
    })
end


function KojoAPI.send_chat_message(room, message)
    if not KojoAPI._profile_token then
        return nil, "Missing profile token"
    end
    local payload = normalize_social_payload(room)
    if type(room) == "table" then
        payload.message = room.message or message or ""
    else
        payload.room = room or "global"
        payload.message = message or ""
    end
    payload.token = KojoAPI._profile_token
    local ok, response = pcall(function()
        return post_social("/api/v1/social/chat/send", payload)
    end)
    if not ok then
        return nil, tostring(response)
    end
    if response and response.message then
        return response.message
    end
    return nil, response and response.detail or "Chat send failed"
end


function KojoAPI.send_direct_message(target_profile_id, message)
    return KojoAPI.send_chat_message({
        scope = "dm",
        target_profile_id = target_profile_id,
        message = message or "",
    })
end


function KojoAPI.translate_text(text, target_language, source_language, provider)
    if not KojoAPI._profile_token then
        return nil, "Missing profile token"
    end
    local ok, response = pcall(function()
        return post_social("/api/v1/social/ai/translate", {
            token = KojoAPI._profile_token,
            text = text,
            target_language = target_language,
            source_language = source_language or "",
            provider = provider or "",
        })
    end)
    if not ok then
        return nil, tostring(response)
    end
    return response
end


function KojoAPI.ask_assistant(prompt, history, provider, system_prompt)
    if not KojoAPI._profile_token then
        return nil, "Missing profile token"
    end
    local ok, response = pcall(function()
        return post_social("/api/v1/social/ai/assistant", {
            token = KojoAPI._profile_token,
            prompt = prompt,
            history = history or {},
            provider = provider or "",
            system_prompt = system_prompt or "",
        })
    end)
    if not ok then
        return nil, tostring(response)
    end
    return response
end


--- Load and execute the script (called after successful check_key)
function KojoAPI.load_script()
    dlog("load_script called")
    
    if not KojoAPI._session_token then
        dlog("load_script: missing session token")
        return false, "Missing secure session. Re-validate your key."
    end

    dlog("load_script: fetching via secure POST /script")

    local ok, script = pcall(function()
        return post_json(
            KojoAPI._BASE_URL .. "/api/v1/loader/script",
            { session = KojoAPI._session_token }
        )
    end)
    
    if not ok then
        dlog("load_script: HTTP failed:", tostring(script))
        return false, "Connection failed"
    end
    
    if not script or #script < 50 then
        dlog("load_script: script too short:", tostring(script):sub(1, 100))
        return false, "Invalid script received"
    end
    
    dlog("load_script: got script (" .. #script .. " bytes), executing...")
    
    local fn, err = loadstring(script)
    if fn then
        fn()
        dlog("load_script: execution complete")
        return true
    else
        dlog("load_script: loadstring error:", tostring(err))
        return false, "Script error: " .. tostring(err)
    end
end


--- Fetch server config (game map, links, display name, etc.)
--- All config lives on server — client never hardcodes sensitive info
function KojoAPI.get_config()
    dlog("get_config called")
    
    local url = KojoAPI._BASE_URL .. "/api/v1/loader/config"
        .. "?game_id=" .. tostring(game.GameId)
        .. "&place_id=" .. tostring(game.PlaceId)
    
    local ok, result = pcall(function()
        return game:HttpGet(url)
    end)
    
    if not ok then
        dlog("get_config: HTTP failed:", tostring(result))
        return nil
    end
    
    local decodeOk, config = pcall(function()
        return HttpService:JSONDecode(result)
    end)
    
    if not decodeOk then
        dlog("get_config: JSON decode failed")
        return nil
    end
    
    dlog("get_config: received config for", config.display_name or "unknown")
    return config
end


print("KojoHub Library Loaded [BYPASS MODE]")
return Library
