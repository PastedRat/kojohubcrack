--[[
    Kojo Hub — Custom Loader (Luarmor-style)
    
    Architecture:
      - ALL config comes from the SERVER (/loader/config) — anti-skid
      - API library loaded from SERVER (/loader/library.lua)
      - Client just handles UI + calls server APIs
      - Debug logging: [Kojo Debug] in output for executor testing
    
    Usage (this is what buyers paste in their executor):
      loadstring(game:HttpGet("https://kojohub.pro/api/v1/loader/key_ui.lua"))()
    
    Or with queue_on_teleport for persistence:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/.../loader.lua"))()
]]

-- ═══════════════════════════════════════════════════════════════
-- DEBU
-- ═══════════════════════════════════════════════════════════════
local _DEBUG = false
local function dlog(...)
    if not _DEBUG then return end
    local args = {...}
    local msg = "[Kojo Debug] "
    for i, v in ipairs(args) do
        if i > 1 then msg = msg .. " " end
        msg = msg .. tostring(v)
    end
    print(msg)
    warn(msg)
end
rconsoleprint("Loading KOJO crack by rustygooners.\n")
dlog("=== Kojo Hub Loader Starting ===")
dlog("GameId:", game.GameId, "| PlaceId:", game.PlaceId)

-- ═══════════════════════════════════════════════════════════════
-- WAIT FOR GAME TO LOAD
-- ═══════════════════════════════════════════════════════════════
if not game:IsLoaded() then
    dlog("Waiting for game to load...")
    game.Loaded:Wait()
end
dlog("Game loaded!")

-- ═══════════════════════════════════════════════════════════════
-- SERVICES (safe refs via cloneref if available)
-- ═══════════════════════════════════════════════════════════════
local cloneref = cloneref or function(o) return o end
local Players = cloneref(game:GetService("Players"))
local LP = Players.LocalPlayer
local PlayerGui = LP:FindFirstChildOfClass("PlayerGui")
local HttpService = cloneref(game:GetService("HttpService"))
local TweenService = cloneref(game:GetService("TweenService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local RunService = cloneref(game:GetService("RunService"))
local MarketplaceService = cloneref(game:GetService("MarketplaceService"))

dlog("Services loaded")

-- ═══════════════════════════════════════════════════════════════
-- SERVER CONFIG (anti-skid: everything comes from server)
-- ═══════════════════════════════════════════════════════════════
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

local BASE_URL = resolveBaseUrl()
local SERVER_CONFIG = nil

dlog("Fetching server config...")
local configOk, configResult = pcall(function()
    local raw = game:HttpGet("https://kojohub.pro/api/v1/loader/config?game_id=7633926880&place_id=114234929420007")
    return HttpService:JSONDecode(raw)
end)

if configOk and configResult then
    SERVER_CONFIG = configResult
    dlog("Config loaded:", SERVER_CONFIG.display_name or "Kojo Hub")
    dlog("Game supported:", tostring(SERVER_CONFIG.supported))
    if SERVER_CONFIG.matched_service then
        dlog("Matched service:", SERVER_CONFIG.matched_service.name, "| ID:", SERVER_CONFIG.matched_service.id)
    end
else
    dlog("Config fetch failed:", tostring(configResult))
    SERVER_CONFIG = {
        supported = false,
        config_error = true,
        display_name = "Kojo Hub",
        version = "1.0.0",
        discord = "",
        base_url = BASE_URL,
        key_page = BASE_URL .. "/checkpoint.html",
        file_directory = "kojohub/key.txt",
        matched_service = nil,
        services = {},
        ad_links = { lootlabs = "" },
    }
end

-- ═══════════════════════════════════════════════════════════════
-- GAME SUPPORT CHECK — Roblox notification if game not supported
-- ═══════════════════════════════════════════════════════════════
local _gameSupported = SERVER_CONFIG.supported
local ALLOW_UNSUPPORTED_UI = false
pcall(function()
    local env = getgenv and getgenv() or _G
    ALLOW_UNSUPPORTED_UI = rawget(env, "KOJO_ALLOW_UNSUPPORTED_UI") == true
        or BASE_URL:find("127.0.0.1", 1, true) ~= nil
        or BASE_URL:find("localhost", 1, true) ~= nil
end)
local PREVIEW_UI_ONLY = ALLOW_UNSUPPORTED_UI
if not _gameSupported then
    -- Get game name for the notification
    local gameName = "this game"
    pcall(function()
        local info = MarketplaceService:GetProductInfo(game.PlaceId)
        if info and info.Name then gameName = info.Name end
    end)
    -- Send a Roblox StarterGui notification (visible even without our UI)
    pcall(function()
        local text = "This game (" .. gameName .. ") is not supported by Kojo Hub."
        if SERVER_CONFIG.config_error then
            text = "Could not verify loader config for " .. gameName .. ". Try again later."
        end
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Kojo Hub",
            Text = text,
            Duration = 8,
        })
    end)
    if not ALLOW_UNSUPPORTED_UI then
        dlog("Loader config unavailable or game unsupported - stopping loader")
        return  -- STOP: do not load script or show UI for unsupported games
    end

    dlog("Unsupported game preview mode enabled")
end

-- LOAD API LIBRARY FROM SERVER
-- ═══════════════════════════════════════════════════════════════
dlog("Loading API library from server...")
local api = loadstring(game:HttpGet("https://raw.githubusercontent.com/PastedRat/kojohubcrack/refs/heads/main/library.lua"))()


dlog("API library loaded, version:", api._VERSION or "?")

-- Set the service/script ID from server config
if SERVER_CONFIG.matched_service then
    api.script_id = tostring(SERVER_CONFIG.matched_service.id)
    dlog("API script_id set to:", api.script_id)
end

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP OLD UI (prevent duplicates)
-- ═══════════════════════════════════════════════════════════════
pcall(function()
    if getgenv().KojoHub_UI then
        dlog("Cleaning up old UI instance")
        getgenv().KojoHub_UI:Destroy()
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- UI SETUP — CoreGui injection (anti-detection)
-- ═══════════════════════════════════════════════════════════════
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KojoUI_" .. HttpService:GenerateGUID(false):sub(1, 8)
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.ResetOnSpawn = false

local guiParented = false
pcall(function()
    if gethui then
        screenGui.Parent = gethui()
        guiParented = true
        dlog("UI parented to gethui()")
    end
end)
if not guiParented then
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(screenGui)
            screenGui.Parent = CoreGui
            guiParented = true
            dlog("UI parented to CoreGui (syn.protect_gui)")
        end
    end)
end
if not guiParented then
    pcall(function()
        screenGui.Parent = CoreGui
        guiParented = true
        dlog("UI parented to CoreGui (direct)")
    end)
end
if not guiParented then
    screenGui.Parent = PlayerGui
    dlog("UI parented to PlayerGui (fallback)")
end

pcall(function()
    getgenv().KojoHub_UI = screenGui
end)

screenGui.Enabled = false  -- start hidden, show after auto-validate check

-- ═══════════════════════════════════════════════════════════════
-- NOTIFICATION SYSTEM
-- ═══════════════════════════════════════════════════════════════
local notifContainer = Instance.new("Frame")
notifContainer.Name = "NotifContainer"
notifContainer.AnchorPoint = Vector2.new(1, 0)
notifContainer.Position = UDim2.new(1, -20, 0, 20)
notifContainer.BackgroundTransparency = 1
notifContainer.Size = UDim2.fromOffset(340, 600)
notifContainer.Parent = screenGui

local notifLayout = Instance.new("UIListLayout")
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.Padding = UDim.new(0, 8)
notifLayout.VerticalAlignment = Enum.VerticalAlignment.Top
notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifLayout.Parent = notifContainer

local function Notify(title, content, duration, color)
    duration = duration or 5
    color = color or Color3.fromRGB(129, 140, 248)
    dlog("Notification:", title, "|", content)

    local frame = Instance.new("Frame")
    frame.Name = "Notif"
    frame.BackgroundColor3 = Color3.fromRGB(16, 16, 26)
    frame.BackgroundTransparency = 0.06
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.Size = UDim2.fromOffset(320, 0)
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Transparency = 0.7
    stroke.Parent = frame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 16)
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.Parent = frame

    local iconPlate = Instance.new("Frame")
    iconPlate.Size = UDim2.fromOffset(30, 30)
    iconPlate.BackgroundColor3 = Color3.fromRGB(22, 22, 34)
    iconPlate.BorderSizePixel = 0
    iconPlate.Parent = frame

    local iconPlateCorner = Instance.new("UICorner")
    iconPlateCorner.CornerRadius = UDim.new(0, 8)
    iconPlateCorner.Parent = iconPlate

    local iconImage = Instance.new("ImageLabel")
    iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
    iconImage.Position = UDim2.fromScale(0.5, 0.5)
    iconImage.Size = UDim2.fromOffset(18, 18)
    iconImage.BackgroundTransparency = 1
    iconImage.Image = "rbxassetid://129289898938555"
    iconImage.ImageColor3 = color
    iconImage.Parent = iconPlate

    local titleLabel = Instance.new("TextLabel")
    titleLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.fromOffset(42, 0)
    titleLabel.Size = UDim2.new(1, -42, 0, 18)
    titleLabel.Parent = frame

    local contentLabel = Instance.new("TextLabel")
    contentLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json")
    contentLabel.Text = content
    contentLabel.TextColor3 = Color3.fromRGB(160, 160, 175)
    contentLabel.TextSize = 12
    contentLabel.TextXAlignment = Enum.TextXAlignment.Left
    contentLabel.TextYAlignment = Enum.TextYAlignment.Top
    contentLabel.TextWrapped = true
    contentLabel.AutomaticSize = Enum.AutomaticSize.Y
    contentLabel.BackgroundTransparency = 1
    contentLabel.Size = UDim2.new(1, -42, 0, 0)
    contentLabel.Position = UDim2.fromOffset(42, 22)
    contentLabel.Parent = frame

    local progressBg = Instance.new("Frame")
    progressBg.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    progressBg.BorderSizePixel = 0
    progressBg.Size = UDim2.new(1, 0, 0, 4)
    progressBg.Position = UDim2.new(0, 0, 1, 6)
    progressBg.Parent = frame

    local progressCorner = Instance.new("UICorner")
    progressCorner.CornerRadius = UDim.new(0, 2)
    progressCorner.Parent = progressBg

    local progressFill = Instance.new("Frame")
    progressFill.BackgroundColor3 = color
    progressFill.BorderSizePixel = 0
    progressFill.Size = UDim2.fromScale(1, 1)
    progressFill.Parent = progressBg

    local progressFillCorner = Instance.new("UICorner")
    progressFillCorner.CornerRadius = UDim.new(0, 2)
    progressFillCorner.Parent = progressFill

    frame.Parent = notifContainer

    TweenService:Create(progressFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
        Size = UDim2.new(0, 0, 1, 0)
    }):Play()

    task.delay(duration, function()
        pcall(function()
            TweenService:Create(frame, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
            task.wait(0.35)
            frame:Destroy()
        end)
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- ERROR MESSAGES (from server codes)
-- ═══════════════════════════════════════════════════════════════
local ERROR_MESSAGES = {
    KEY_EXPIRED     = "Key has expired! Get a new one.",
    KEY_BANNED      = "Key has been blacklisted. Contact support.",
    KEY_HWID_LOCKED = "This key is active on another device. Reset the device link from Discord support.",
    KEY_INCORRECT   = "Key is incorrect or does not exist.",
    KEY_INVALID     = "Invalid key format.",
    RATE_LIMITED    = "Too many requests. Wait 60 seconds.",
    NETWORK_ERROR   = "Connection failed. Check your internet.",
    PARSE_ERROR     = "Server returned invalid data.",
    EXECUTOR_UNSUPPORTED = "Your executor must support secure HTTP POST requests to use Kojo.",
    SECURITY_ERROR  = "Security error. Contact support.",
    UNKNOWN_ERROR   = "Unknown error. Contact support.",
}

local ERROR_TITLES = {
    KEY_EXPIRED = "Key expired",
    KEY_BANNED = "Access blocked",
    KEY_HWID_LOCKED = "Device verification",
    KEY_INCORRECT = "Authentication failed",
    KEY_INVALID = "Invalid key",
    RATE_LIMITED = "Rate limited",
    NETWORK_ERROR = "Connection issue",
    PARSE_ERROR = "Service issue",
    EXECUTOR_UNSUPPORTED = "Executor unsupported",
    SECURITY_ERROR = "Security check",
    UNKNOWN_ERROR = "Authentication issue",
}

local function GetErrorTitle(code)
    return ERROR_TITLES[code] or "Authentication issue"
end

local SetStatus
local redeemBtn

-- ═══════════════════════════════════════════════════════════════
-- UTILITY: Format remaining time
-- ═══════════════════════════════════════════════════════════════
local function FormatTime(seconds)
    if seconds <= 0 then return "Expired" end
    if seconds >= 999999000 then return "Lifetime" end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if days > 0 then
        return string.format("%dd %02dh %02dm", days, hours, minutes)
    else
        return string.format("%02dh %02dm %02ds", hours, minutes, secs)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- UTILITY: Delete file safely
-- ═══════════════════════════════════════════════════════════════
local function SafeDeleteFile(path)
    pcall(function()
        if isfile and isfile(path) then
            delfile(path)
            dlog("Deleted file:", path)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- UTILITY: Clipboard
-- ═══════════════════════════════════════════════════════════════
local fSetClipboard = setclipboard or toclipboard or set_clipboard or (Clipboard and Clipboard.set)

-- ═══════════════════════════════════════════════════════════════
-- UTILITY: Dragging
-- ═══════════════════════════════════════════════════════════════
local function MakeDraggable(frame, handle)
    local dragging = false
    local relative = nil
    local offset = Vector2.zero

    pcall(function()
        local sg = frame:FindFirstAncestorWhichIsA("ScreenGui")
        if sg and sg.IgnoreGuiInset then
            offset = game:GetService("GuiService"):GetGuiInset()
        end
    end)

    handle.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            relative = frame.AbsolutePosition + frame.AbsoluteSize * frame.AnchorPoint - UserInputService:GetMouseLocation()
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
        end
    end)

    RunService.RenderStepped:Connect(function()
        if dragging then
            local pos = UserInputService:GetMouseLocation() + relative + offset
            TweenService:Create(frame, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.fromOffset(pos.X, pos.Y)
            }):Play()
        end
    end)

    frame.Destroying:Connect(function()
        dragging = false
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- CORE KEY VALIDATION FUNCTION
-- ═══════════════════════════════════════════════════════════════
local FILE_DIR = SERVER_CONFIG.file_directory or "kojohub/key.txt"

local SocialBridge = {
    api = api,
    profile = nil,
    profile_token = "",
}

function SocialBridge.refreshProfile()
    local profile, err = api.get_profile()
    if profile then
        SocialBridge.profile = profile
        return profile
    end
    return nil, err
end

function SocialBridge.updateProfile(changes)
    local profile, err = api.update_profile(changes)
    if profile then
        SocialBridge.profile = profile
        return profile
    end
    return nil, err
end

function SocialBridge.listPresence(filters)
    return api.list_presence(filters)
end

function SocialBridge.listRoomMessages(room, limit)
    return api.list_chat_messages(room, limit)
end

function SocialBridge.sendRoomMessage(room, message)
    return api.send_chat_message(room, message)
end

function SocialBridge.listDirectMessages(targetProfileId, limit)
    return api.list_direct_messages(targetProfileId, limit)
end

function SocialBridge.sendDirectMessage(targetProfileId, message)
    return api.send_direct_message(targetProfileId, message)
end

function SocialBridge.translate(text, targetLanguage, sourceLanguage, provider)
    return api.translate_text(text, targetLanguage, sourceLanguage, provider)
end

function SocialBridge.ask(prompt, history, provider, systemPrompt)
    return api.ask_assistant(prompt, history, provider, systemPrompt)
end

local function PublishSocialState(profile)
    profile = profile or {}
    SocialBridge.profile = profile
    SocialBridge.profile_token = api._profile_token or ""

    local env = _G
    pcall(function()
        if getgenv then
            env = getgenv()
        end
    end)

    env.KOJO_ProfileId = profile.profile_id or ""
    env.KOJO_ProfileName = profile.display_name or ""
    env.KOJO_ProfileAvatar = profile.script_avatar_url or profile.avatar_url or ""
    env.KOJO_ProfileVisible = profile.visible ~= false
    env.KOJO_ProfileToken = api._profile_token or ""
    env.KOJO_DiscordTag = profile.discord_username or env.KOJO_DiscordTag or ""
    env.KOJO_SOCIAL = SocialBridge
end

local function PublishRuntimeState(statusData, keyValue)
    statusData = statusData or {}

    local env = _G
    pcall(function()
        if getgenv then
            env = getgenv()
        end
    end)

    local profile = type(statusData.profile) == "table" and statusData.profile or {}
    local expiresAt = tonumber(statusData.auth_expire or 0)
    local placeName = tostring(
        statusData.place_name
        or statusData.game_name
        or (SERVER_CONFIG and SERVER_CONFIG.matched_service and SERVER_CONFIG.matched_service.name)
        or env.KOJO_PlaceName
        or ""
    )
    local discordTag = tostring(
        profile.discord_username
        or statusData.discord_username
        or statusData.discord_tag
        or env.KOJO_DiscordTag
        or ""
    )

    env.KOJO_LicenseKey = tostring(keyValue or env.KOJO_LicenseKey or "")
    env.KOJO_UserTier = tostring(statusData.tier or env.KOJO_UserTier or "Freemium")
    env.KOJO_ExecutionCount = tonumber(statusData.total_executions or statusData.executions or env.KOJO_ExecutionCount or 0) or 0
    env.KOJO_DiscordTag = discordTag
    env.KOJO_PlaceName = placeName

    if expiresAt and expiresAt > 0 then
        env.KOJO_ExpireAt = expiresAt
        env.KOJO_SecondsLeft = math.max(0, expiresAt - os.time())
    else
        env.KOJO_ExpireAt = nil
        env.KOJO_SecondsLeft = nil
    end
end

local function PublishUiRoot()
    local env = _G
    pcall(function()
        if getgenv then
            env = getgenv()
        end
    end)

    local root = tostring(rawget(env, "KojoObsidianRoot") or rawget(env, "KOJO_UI_ROOT") or "obsidian_kojo")
    env.KojoObsidianRoot = root
    env.KOJO_UI_ROOT = root
end

local function TryLoadLocalPreviewUI()
    if not (PREVIEW_UI_ONLY and readfile and loadstring and isfile) then
        return false
    end

    local env = _G
    pcall(function()
        if getgenv then
            env = getgenv()
        end
    end)

    local root = tostring(rawget(env, "KojoObsidianRoot") or rawget(env, "KOJO_UI_ROOT") or "obsidian_kojo")
    local candidates = {
        root .. "\\LocalExample.lua",
        "obsidian_kojo\\LocalExample.lua",
        root .. "/LocalExample.lua",
        "obsidian_kojo/LocalExample.lua",
    }

    for _, candidate in ipairs(candidates) do
        local okExists, exists = pcall(function()
            return isfile(candidate)
        end)
        if okExists and exists then
            local okSource, source = pcall(function()
                return readfile(candidate)
            end)
            if okSource and type(source) == "string" and source ~= "" then
                local okChunk, chunk = pcall(loadstring, source)
                if okChunk and type(chunk) == "function" then
                    env.KojoObsidianRoot = root
                    local execOk = pcall(chunk)
                    if execOk then
                        dlog("Local preview UI opened from:", candidate)
                        return true
                    end
                end
            end
        end
    end

    dlog("Local preview UI not available")
    return false
end

local function ValidateAndExecute(key, onSuccess, onFail)
    dlog("ValidateAndExecute called with key:", key:sub(1, 15) .. "...")

    if not key or key == "" then
        dlog("Empty key, aborting")
        if onFail then onFail("KEY_INVALID") end
        return
    end

    -- Clean whitespace
    local cleanKey = key:gsub("%s", "")
    if cleanKey ~= key then
        dlog("Whitespace detected in key, cleaned")
        Notify("Info", "Spaces detected in key. Using cleaned version.", 3, Color3.fromRGB(129, 140, 248))
    end

    -- Check key against server
    local checkOk, status = pcall(function()
        return api.check_key(cleanKey)
    end)

    if not checkOk then
        dlog("check_key pcall failed:", tostring(status))
        Notify("Error", "Failed to validate key. Try again.", 5, Color3.fromRGB(248, 113, 113))
        if onFail then onFail("NETWORK_ERROR") end
        return
    end

    if status.code == "KEY_VALID" then
        dlog("KEY_VALID! Tier:", status.data.tier)
        PublishRuntimeState(status.data, cleanKey)
        PublishSocialState(status.data.profile)
        PublishUiRoot()

        -- Save key to file
        pcall(function()
            if writefile then
                -- Ensure directory exists
                pcall(function()
                    if not isfolder("kojohub") then
                        makefolder("kojohub")
                    end
                end)
                writefile(FILE_DIR, cleanKey)
                dlog("Key saved to:", FILE_DIR)
            end
        end)

        -- Show info notifications
        if status.data.auth_expire and status.data.auth_expire > 0 then
            local timeLeft = status.data.auth_expire - os.time()
            Notify("✅ Key Valid", "Expires in: " .. FormatTime(timeLeft), 5, Color3.fromRGB(52, 211, 153))
        else
            Notify("✅ Key Valid", "Lifetime key active!", 5, Color3.fromRGB(52, 211, 153))
        end

        if status.data.total_executions then
            Notify("Info", "Total executions: " .. tostring(status.data.total_executions), 3, Color3.fromRGB(129, 140, 248))
        end

        if status.data.profile and status.data.profile.display_name and status.data.profile.display_name ~= "" then
            Notify("Profile", "Signed in as " .. tostring(status.data.profile.display_name), 3, Color3.fromRGB(129, 140, 248))
        end

        -- Set up queue_on_teleport for persistence
        pcall(function()
            if queue_on_teleport then
                queue_on_teleport([[
                    loadstring(game:HttpGet("]] .. BASE_URL .. [[/api/v1/loader/key_ui.lua"))()
                ]])
                dlog("queue_on_teleport set")
            end
        end)

        if ALLOW_UNSUPPORTED_UI and not _gameSupported then
            dlog("Preview auth mode active, skipping script load")
            status.preview_only = true
            if onSuccess then onSuccess(status) end
            return
        end

        -- Load the actual script
        dlog("Loading script via api.load_script()...")
        task.wait(0.5)
        PublishUiRoot()
        local loadOk, loadResult, loadErr = pcall(function()
            return api.load_script()
        end)
        if not loadOk then
            dlog("load_script pcall failed:", tostring(loadResult))
            Notify("Error", "Script load failed: " .. tostring(loadResult), 6, Color3.fromRGB(248, 113, 113))
            SetStatus("X", "Script load failed.", Color3.fromRGB(248, 113, 113))
            redeemBtn.Text = "Redeem Key"
            redeemBtn.BackgroundColor3 = Color3.fromRGB(129, 140, 248)
            if onFail then onFail("UNKNOWN_ERROR") end
            return
        end
        if loadResult == false then
            dlog("load_script returned failure:", tostring(loadErr))
            Notify("Error", tostring(loadErr or "Script load failed."), 6, Color3.fromRGB(248, 113, 113))
            SetStatus("X", "Script load failed.", Color3.fromRGB(248, 113, 113))
            redeemBtn.Text = "Redeem Key"
            redeemBtn.BackgroundColor3 = Color3.fromRGB(129, 140, 248)
            if onFail then onFail("UNKNOWN_ERROR") end
            return
        end

        if onSuccess then onSuccess(status) end
        return
    end

    -- Handle error codes
    local errorMsg = ERROR_MESSAGES[status.code] or status.message or "Unknown error"
    dlog("Key rejected:", status.code, "|", errorMsg)
    SafeDeleteFile(FILE_DIR)
    Notify(GetErrorTitle(status.code), errorMsg, 6, Color3.fromRGB(248, 113, 113))

    -- Kick for critical errors
    if status.code == "SECURITY_ERROR" or status.code == "KEY_BANNED" then
        task.wait(2)
        LP:Kick("[Kojo] " .. errorMsg)
    end

    if onFail then onFail(status.code) end
end

-- ═══════════════════════════════════════════════════════════════
-- BUILD MAIN UI
-- ═══════════════════════════════════════════════════════════════
dlog("Building UI...")

local function OffsetUDim2(source, dx, dy)
    return UDim2.new(source.X.Scale, source.X.Offset + dx, source.Y.Scale, source.Y.Offset + dy)
end

local viewportSize = Vector2.new(1280, 720)
pcall(function()
    if workspace.CurrentCamera then
        viewportSize = workspace.CurrentCamera.ViewportSize
    end
end)

local BASE_SHELL_WIDTH = 848
local BASE_SHELL_HEIGHT = 468
local shellScale = math.clamp(math.min(
    (viewportSize.X - 36) / BASE_SHELL_WIDTH,
    (viewportSize.Y - 44) / BASE_SHELL_HEIGHT,
    1
), 0.72, 1)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "Main"
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Position = UDim2.fromScale(0.5, 0.5)
MainFrame.Size = UDim2.fromOffset(BASE_SHELL_WIDTH, BASE_SHELL_HEIGHT)
MainFrame.BackgroundColor3 = Color3.fromRGB(8, 9, 16)
MainFrame.BackgroundTransparency = 0.02
MainFrame.BorderSizePixel = 0
MainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 22)
mainCorner.Parent = MainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(58, 63, 92)
mainStroke.Transparency = 0.35
mainStroke.Thickness = 1.2
mainStroke.Parent = MainFrame

local LoaderScale = Instance.new("UIScale")
LoaderScale.Scale = shellScale
LoaderScale.Parent = MainFrame

local shellGradient = Instance.new("UIGradient")
shellGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 16, 28)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 9, 16)),
})
shellGradient.Rotation = 90
shellGradient.Parent = MainFrame

local shellPadding = Instance.new("UIPadding")
shellPadding.PaddingTop = UDim.new(0, 10)
shellPadding.PaddingBottom = UDim.new(0, 10)
shellPadding.PaddingLeft = UDim.new(0, 10)
shellPadding.PaddingRight = UDim.new(0, 10)
shellPadding.Parent = MainFrame

local DragBar = Instance.new("Frame")
DragBar.Name = "DragBar"
DragBar.Size = UDim2.new(1, 0, 0, 56)
DragBar.BackgroundTransparency = 1
DragBar.Parent = MainFrame

MakeDraggable(MainFrame, DragBar)

local HeroPanel = Instance.new("Frame")
HeroPanel.Name = "HeroPanel"
HeroPanel.Size = UDim2.fromOffset(372, 452)
HeroPanel.Position = UDim2.fromOffset(6, 8)
HeroPanel.BackgroundColor3 = Color3.fromRGB(92, 106, 242)
HeroPanel.BorderSizePixel = 0
HeroPanel.ClipsDescendants = true
HeroPanel.Parent = MainFrame

local heroCorner = Instance.new("UICorner")
heroCorner.CornerRadius = UDim.new(0, 18)
heroCorner.Parent = HeroPanel

local heroGradient = Instance.new("UIGradient")
heroGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(112, 132, 255)),
    ColorSequenceKeypoint.new(0.52, Color3.fromRGB(88, 101, 242)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 60, 156)),
})
heroGradient.Rotation = 18
heroGradient.Parent = HeroPanel

local heroShade = Instance.new("Frame")
heroShade.Size = UDim2.new(1, 0, 1, 0)
heroShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
heroShade.BackgroundTransparency = 0.9
heroShade.BorderSizePixel = 0
heroShade.Parent = HeroPanel

local heroShadeGradient = Instance.new("UIGradient")
heroShadeGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 188, 255)),
})
heroShadeGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.92),
    NumberSequenceKeypoint.new(0.56, 0.68),
    NumberSequenceKeypoint.new(1, 0.32),
})
heroShadeGradient.Rotation = 90
heroShadeGradient.Parent = heroShade

local heroPattern = Instance.new("ImageLabel")
heroPattern.Name = "Pattern"
heroPattern.BackgroundTransparency = 1
heroPattern.Size = UDim2.new(1.38, 0, 1.38, 0)
heroPattern.Position = UDim2.fromScale(-0.16, -0.18)
heroPattern.Image = "rbxassetid://129289898938555"
heroPattern.ImageColor3 = Color3.fromRGB(235, 239, 255)
heroPattern.ImageTransparency = 0.955
heroPattern.ScaleType = Enum.ScaleType.Fit
heroPattern.Rotation = -10
heroPattern.Parent = HeroPanel

local heroLogoGlow = Instance.new("ImageLabel")
heroLogoGlow.BackgroundTransparency = 1
heroLogoGlow.Size = UDim2.fromOffset(160, 160)
heroLogoGlow.Position = UDim2.new(0.5, -80, 0.5, -96)
heroLogoGlow.Image = "rbxassetid://129289898938555"
heroLogoGlow.ImageColor3 = Color3.fromRGB(255, 255, 255)
heroLogoGlow.ImageTransparency = 0.7
heroLogoGlow.ScaleType = Enum.ScaleType.Fit
heroLogoGlow.Parent = HeroPanel

local heroLogo = Instance.new("ImageLabel")
heroLogo.BackgroundTransparency = 1
heroLogo.Size = UDim2.fromOffset(122, 122)
heroLogo.Position = UDim2.new(0.5, -61, 0.5, -77)
heroLogo.Image = "rbxassetid://129289898938555"
heroLogo.ImageColor3 = Color3.fromRGB(255, 255, 255)
heroLogo.ScaleType = Enum.ScaleType.Fit
heroLogo.Parent = HeroPanel

local heroFooterFade = Instance.new("Frame")
heroFooterFade.AnchorPoint = Vector2.new(0.5, 1)
heroFooterFade.Position = UDim2.new(0.5, 0, 1, 0)
heroFooterFade.Size = UDim2.new(1, 0, 0, 92)
heroFooterFade.BackgroundColor3 = Color3.fromRGB(26, 30, 86)
heroFooterFade.BackgroundTransparency = 0.2
heroFooterFade.BorderSizePixel = 0
heroFooterFade.Parent = HeroPanel

local heroFooterGradient = Instance.new("UIGradient")
heroFooterGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.2, 0.9),
    NumberSequenceKeypoint.new(1, 0.15),
})
heroFooterGradient.Rotation = 90
heroFooterGradient.Parent = heroFooterFade

local heroBrand = Instance.new("TextLabel")
heroBrand.Size = UDim2.new(1, -40, 0, 26)
heroBrand.Position = UDim2.new(0, 20, 1, -34)
heroBrand.BackgroundTransparency = 1
heroBrand.Text = "kojohub.pro"
heroBrand.TextColor3 = Color3.fromRGB(247, 248, 255)
heroBrand.TextTransparency = 0.08
heroBrand.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
heroBrand.TextSize = 16
heroBrand.TextXAlignment = Enum.TextXAlignment.Left
heroBrand.Parent = HeroPanel

local HeroEdge = Instance.new("Frame")
HeroEdge.Size = UDim2.fromOffset(1, 452)
HeroEdge.Position = UDim2.fromOffset(390, 8)
HeroEdge.BackgroundColor3 = Color3.fromRGB(33, 37, 58)
HeroEdge.BackgroundTransparency = 0.1
HeroEdge.BorderSizePixel = 0
HeroEdge.Parent = MainFrame

local AuthPanel = Instance.new("Frame")
AuthPanel.Name = "AuthPanel"
AuthPanel.Size = UDim2.fromOffset(404, 452)
AuthPanel.Position = UDim2.fromOffset(408, 8)
AuthPanel.BackgroundTransparency = 1
AuthPanel.Parent = MainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -66, 0, 46)
titleLabel.Position = UDim2.fromOffset(16, 16)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = SERVER_CONFIG.display_name or "Kojo Hub"
titleLabel.TextColor3 = Color3.fromRGB(245, 246, 255)
titleLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
titleLabel.TextSize = 27
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = AuthPanel

local versionLabel = Instance.new("TextLabel")
versionLabel.Size = UDim2.new(1, -66, 0, 22)
versionLabel.Position = UDim2.fromOffset(16, 52)
versionLabel.BackgroundTransparency = 1
versionLabel.Text = "Authenticate to continue"
versionLabel.TextColor3 = Color3.fromRGB(133, 141, 172)
versionLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json")
versionLabel.TextSize = 14
versionLabel.TextXAlignment = Enum.TextXAlignment.Left
versionLabel.Parent = AuthPanel

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(34, 34)
closeBtn.Position = UDim2.new(1, -50, 0, 12)
closeBtn.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
closeBtn.BackgroundTransparency = 0.08
closeBtn.Text = "x"
closeBtn.TextColor3 = Color3.fromRGB(180, 184, 204)
closeBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
closeBtn.TextSize = 16
closeBtn.BorderSizePixel = 0
closeBtn.Parent = AuthPanel

local closeBtnCorner = Instance.new("UICorner")
closeBtnCorner.CornerRadius = UDim.new(0, 10)
closeBtnCorner.Parent = closeBtn

local closeBtnStroke = Instance.new("UIStroke")
closeBtnStroke.Color = Color3.fromRGB(58, 63, 92)
closeBtnStroke.Transparency = 0.45
closeBtnStroke.Parent = closeBtn

local statusBar = Instance.new("Frame")
statusBar.Size = UDim2.new(1, -32, 0, 22)
statusBar.Position = UDim2.fromOffset(16, 84)
statusBar.BackgroundTransparency = 1
statusBar.BorderSizePixel = 0
statusBar.Parent = AuthPanel

local statusIcon = Instance.new("Frame")
statusIcon.Size = UDim2.fromOffset(8, 8)
statusIcon.Position = UDim2.fromOffset(0, 7)
statusIcon.BackgroundTransparency = 1
statusIcon.BackgroundColor3 = Color3.fromRGB(196, 202, 234)
statusIcon.BorderSizePixel = 0
statusIcon.Parent = statusBar

local statusIconCorner = Instance.new("UICorner")
statusIconCorner.CornerRadius = UDim.new(1, 0)
statusIconCorner.Parent = statusIcon

local statusText = Instance.new("TextLabel")
statusText.Size = UDim2.new(1, -18, 1, 0)
statusText.Position = UDim2.fromOffset(18, 0)
statusText.BackgroundTransparency = 1
statusText.Text = "Enter your key to continue"
statusText.TextColor3 = Color3.fromRGB(168, 175, 202)
statusText.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
statusText.TextSize = 13
statusText.TextXAlignment = Enum.TextXAlignment.Left
statusText.Parent = statusBar

local statusLine = Instance.new("Frame")
statusLine.Size = UDim2.new(1, 0, 0, 1)
statusLine.Position = UDim2.new(0, 0, 1, 3)
statusLine.BackgroundColor3 = Color3.fromRGB(42, 46, 70)
statusLine.BackgroundTransparency = 0.2
statusLine.BorderSizePixel = 0
statusLine.Parent = statusBar

local statusGlow = Instance.new("Frame")
statusGlow.Size = UDim2.new(0, 0, 0, 2)
statusGlow.Position = UDim2.new(0, 0, 1, 2)
statusGlow.BackgroundColor3 = Color3.fromRGB(168, 175, 202)
statusGlow.BackgroundTransparency = 0.38
statusGlow.BorderSizePixel = 0
statusGlow.Parent = statusBar

SetStatus = function(icon, text, color)
    statusIcon.BackgroundColor3 = color or Color3.fromRGB(196, 202, 234)
    statusText.Text = text
    statusText.TextColor3 = color or Color3.fromRGB(168, 175, 202)
    TweenService:Create(statusGlow, TweenInfo.new(0.18), {
        BackgroundColor3 = color or Color3.fromRGB(120, 126, 156),
        BackgroundTransparency = color and 0.18 or 0.38,
        Size = UDim2.new(text and text ~= "" and 1 or 0.35, 0, 0, 2),
    }):Play()
    dlog("Status:", icon, text)
end

local gameNameOk, gameName = pcall(function()
    return MarketplaceService:GetProductInfo(game.PlaceId).Name
end)

local gameLabel = Instance.new("TextLabel")
gameLabel.Size = UDim2.new(1, -32, 0, 18)
gameLabel.Position = UDim2.fromOffset(16, 120)
gameLabel.BackgroundTransparency = 1
gameLabel.Text = "Game: " .. (gameNameOk and gameName or "Unknown")
gameLabel.TextColor3 = Color3.fromRGB(112, 118, 147)
gameLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json")
gameLabel.TextSize = 12
gameLabel.TextXAlignment = Enum.TextXAlignment.Left
gameLabel.Parent = AuthPanel

local inputFrame = Instance.new("Frame")
inputFrame.Size = UDim2.new(1, -32, 0, 62)
inputFrame.Position = UDim2.fromOffset(16, 142)
inputFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 36)
inputFrame.BackgroundTransparency = 0.02
inputFrame.BorderSizePixel = 0
inputFrame.Parent = AuthPanel

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 16)
inputCorner.Parent = inputFrame

local inputStroke = Instance.new("UIStroke")
inputStroke.Color = Color3.fromRGB(58, 63, 92)
inputStroke.Transparency = 0.18
inputStroke.Thickness = 1.1
inputStroke.Parent = inputFrame

local inputHint = Instance.new("TextLabel")
inputHint.Size = UDim2.new(1, -22, 0, 16)
inputHint.Position = UDim2.fromOffset(14, 9)
inputHint.BackgroundTransparency = 1
inputHint.Text = "KEY"
inputHint.TextColor3 = Color3.fromRGB(112, 118, 147)
inputHint.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
inputHint.TextSize = 11
inputHint.TextXAlignment = Enum.TextXAlignment.Left
inputHint.Parent = inputFrame

local keyTextbox = Instance.new("TextBox")
keyTextbox.Size = UDim2.new(1, -28, 0, 28)
keyTextbox.Position = UDim2.fromOffset(14, 26)
keyTextbox.BackgroundTransparency = 1
keyTextbox.Text = ""
keyTextbox.PlaceholderText = "kojo-xxxxxxxx-xxxxxxxx-xxxxxxxx"
keyTextbox.PlaceholderColor3 = Color3.fromRGB(82, 87, 114)
keyTextbox.TextColor3 = Color3.fromRGB(236, 238, 255)
keyTextbox.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
keyTextbox.TextSize = 15
keyTextbox.ClearTextOnFocus = false
keyTextbox.TextXAlignment = Enum.TextXAlignment.Left
keyTextbox.Parent = inputFrame

keyTextbox.Focused:Connect(function()
    TweenService:Create(inputStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(176, 182, 255), Transparency = 0}):Play()
    TweenService:Create(inputFrame, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(24, 27, 42)}):Play()
end)
keyTextbox.FocusLost:Connect(function()
    TweenService:Create(inputStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(58, 63, 92), Transparency = 0.18}):Play()
    TweenService:Create(inputFrame, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(20, 22, 36)}):Play()
end)

redeemBtn = Instance.new("TextButton")
redeemBtn.Size = UDim2.new(1, -32, 0, 54)
redeemBtn.Position = UDim2.fromOffset(16, 230)
redeemBtn.BackgroundColor3 = Color3.fromRGB(132, 140, 246)
redeemBtn.Text = "Redeem Key"
redeemBtn.TextColor3 = Color3.fromRGB(248, 249, 255)
redeemBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
redeemBtn.TextSize = 18
redeemBtn.BorderSizePixel = 0
redeemBtn.Parent = AuthPanel

local redeemCorner = Instance.new("UICorner")
redeemCorner.CornerRadius = UDim.new(0, 18)
redeemCorner.Parent = redeemBtn

local redeemGradient = Instance.new("UIGradient")
redeemGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(148, 156, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(117, 124, 232)),
})
redeemGradient.Rotation = 0
redeemGradient.Parent = redeemBtn

local redeemStroke = Instance.new("UIStroke")
redeemStroke.Color = Color3.fromRGB(213, 217, 255)
redeemStroke.Transparency = 0.72
redeemStroke.Parent = redeemBtn

local redeemScale = Instance.new("UIScale")
redeemScale.Scale = 1
redeemScale.Parent = redeemBtn

redeemBtn.MouseEnter:Connect(function()
    TweenService:Create(redeemScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.015}):Play()
    TweenService:Create(redeemBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(150, 159, 255)}):Play()
end)
redeemBtn.MouseLeave:Connect(function()
    TweenService:Create(redeemScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
    TweenService:Create(redeemBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(132, 140, 246)}):Play()
end)

local function MakeActionButton(name, labelText, pos, accentColor)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.fromOffset(180, 48)
    btn.Position = pos
    btn.BackgroundColor3 = Color3.fromRGB(18, 20, 33)
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = AuthPanel

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 16)
    btnCorner.Parent = btn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = accentColor
    btnStroke.Transparency = 0.58
    btnStroke.Parent = btn

    local btnGlow = Instance.new("Frame")
    btnGlow.Size = UDim2.new(1, 0, 1, 0)
    btnGlow.BackgroundColor3 = accentColor
    btnGlow.BackgroundTransparency = 0.94
    btnGlow.BorderSizePixel = 0
    btnGlow.ZIndex = 0
    btnGlow.Parent = btn

    local btnGlowCorner = Instance.new("UICorner")
    btnGlowCorner.CornerRadius = UDim.new(0, 16)
    btnGlowCorner.Parent = btnGlow

    local btnLabel = Instance.new("TextLabel")
    btnLabel.Name = "Label"
    btnLabel.Size = UDim2.new(1, -24, 1, 0)
    btnLabel.Position = UDim2.fromOffset(12, 0)
    btnLabel.BackgroundTransparency = 1
    btnLabel.Text = labelText
    btnLabel.TextColor3 = Color3.fromRGB(234, 237, 255)
    btnLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    btnLabel.TextSize = 15
    btnLabel.Parent = btn

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(24, 27, 42)}):Play()
        TweenService:Create(btnGlow, TweenInfo.new(0.15), {BackgroundTransparency = 0.88}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(18, 20, 33)}):Play()
        TweenService:Create(btnGlow, TweenInfo.new(0.15), {BackgroundTransparency = 0.94}):Play()
    end)

    return btn
end

local getKeyBtn = MakeActionButton("GetKey", "Get Key", UDim2.fromOffset(16, 302), Color3.fromRGB(129, 140, 248))
local discordBtn = MakeActionButton("Discord", "Discord", UDim2.fromOffset(208, 302), Color3.fromRGB(88, 101, 242))

local purchaseHint = Instance.new("TextLabel")
purchaseHint.Size = UDim2.new(1, -32, 0, 18)
purchaseHint.Position = UDim2.fromOffset(16, 358)
purchaseHint.BackgroundTransparency = 1
purchaseHint.Text = "OR"
purchaseHint.TextColor3 = Color3.fromRGB(84, 90, 118)
purchaseHint.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
purchaseHint.TextSize = 12
purchaseHint.Parent = AuthPanel

local purchaseBtn = Instance.new("TextButton")
purchaseBtn.Size = UDim2.new(1, -32, 0, 36)
purchaseBtn.Position = UDim2.fromOffset(16, 376)
purchaseBtn.BackgroundTransparency = 1
purchaseBtn.Text = "Purchase a subscription"
purchaseBtn.TextColor3 = Color3.fromRGB(191, 197, 230)
purchaseBtn.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
purchaseBtn.TextSize = 13
purchaseBtn.BorderSizePixel = 0
purchaseBtn.Parent = AuthPanel

local purchaseUnderline = Instance.new("Frame")
purchaseUnderline.Size = UDim2.new(0, 152, 0, 1)
purchaseUnderline.AnchorPoint = Vector2.new(0.5, 0)
purchaseUnderline.Position = UDim2.new(0.5, 0, 1, -3)
purchaseUnderline.BackgroundColor3 = Color3.fromRGB(82, 88, 116)
purchaseUnderline.BackgroundTransparency = 0.25
purchaseUnderline.BorderSizePixel = 0
purchaseUnderline.Parent = purchaseBtn

purchaseBtn.MouseEnter:Connect(function()
    TweenService:Create(purchaseBtn, TweenInfo.new(0.15), {TextColor3 = Color3.fromRGB(232, 236, 255)}):Play()
    TweenService:Create(purchaseUnderline, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(129, 140, 248)}):Play()
end)
purchaseBtn.MouseLeave:Connect(function()
    TweenService:Create(purchaseBtn, TweenInfo.new(0.15), {TextColor3 = Color3.fromRGB(191, 197, 230)}):Play()
    TweenService:Create(purchaseUnderline, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(82, 88, 116)}):Play()
end)

local authFooter = Instance.new("TextLabel")
authFooter.Size = UDim2.new(1, -32, 0, 22)
authFooter.Position = UDim2.fromOffset(16, 426)
authFooter.BackgroundTransparency = 1
authFooter.Text = "Get access and support from the official Kojo channels"
authFooter.TextColor3 = Color3.fromRGB(92, 98, 126)
authFooter.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json")
authFooter.TextSize = 12
authFooter.TextXAlignment = Enum.TextXAlignment.Left
authFooter.Parent = AuthPanel

local infoFrame = Instance.new("Frame")
infoFrame.Visible = false
infoFrame.Size = UDim2.fromOffset(8, 8)
infoFrame.Position = UDim2.fromOffset(0, 0)
infoFrame.BackgroundTransparency = 1
infoFrame.Parent = MainFrame

local infoLabels = {}
local infoItems = { {"Tier", "-"}, {"Expires", "-"}, {"Executions", "-"} }
for _, item in ipairs(infoItems) do
    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.fromOffset(1, 1)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = item[2]
    valLabel.Visible = false
    valLabel.Parent = infoFrame
    infoLabels[item[1]] = valLabel
end

local footer = Instance.new("TextLabel")
footer.Size = UDim2.new(1, 0, 0, 14)
footer.Position = UDim2.new(0, 0, 1, -14)
footer.BackgroundTransparency = 1
footer.Text = ""
footer.Parent = MainFrame

local HeroOpenPosition = HeroPanel.Position
local AuthOpenPosition = AuthPanel.Position
local HeroEdgeOpenPosition = HeroEdge.Position
HeroPanel.Position = OffsetUDim2(HeroOpenPosition, -32, 0)
AuthPanel.Position = OffsetUDim2(AuthOpenPosition, 32, 0)
HeroEdge.Position = OffsetUDim2(HeroEdgeOpenPosition, -8, 0)
heroLogoGlow.ImageTransparency = 1
HeroPanel.BackgroundTransparency = 0.18

local function DismissLoaderUI()
    TweenService:Create(LoaderScale, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Scale = 0.88,
    }):Play()
    TweenService:Create(MainFrame, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = UDim2.new(0.5, 0, 0.5, 20),
    }):Play()
    TweenService:Create(mainStroke, TweenInfo.new(0.2), {Transparency = 1}):Play()
    task.wait(0.28)
    pcall(function()
        screenGui:Destroy()
    end)
end

local function ShowLoaderUI()
    dlog("Showing key UI...")
    screenGui.Enabled = true
    MainFrame.Position = UDim2.new(0.5, 0, 0.5, -18)
    MainFrame.BackgroundTransparency = 0.35
    LoaderScale.Scale = 0.9
    mainStroke.Transparency = 1
    HeroPanel.Position = OffsetUDim2(HeroOpenPosition, -32, 0)
    AuthPanel.Position = OffsetUDim2(AuthOpenPosition, 32, 0)
    HeroEdge.Position = OffsetUDim2(HeroEdgeOpenPosition, -8, 0)
    heroLogoGlow.ImageTransparency = 1
    task.wait(0.03)
    TweenService:Create(MainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.fromScale(0.5, 0.5),
        BackgroundTransparency = 0.02,
    }):Play()
    TweenService:Create(LoaderScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Scale = 1,
    }):Play()
    TweenService:Create(mainStroke, TweenInfo.new(0.35), {Transparency = 0.35}):Play()
    TweenService:Create(HeroPanel, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = HeroOpenPosition,
    }):Play()
    TweenService:Create(AuthPanel, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = AuthOpenPosition,
    }):Play()
    TweenService:Create(HeroEdge, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = HeroEdgeOpenPosition,
    }):Play()
    TweenService:Create(heroLogoGlow, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        ImageTransparency = 0.56,
    }):Play()
end

closeBtn.MouseButton1Click:Connect(function()
    dlog("Close button clicked, destroying UI")
    DismissLoaderUI()
end)

-- BUTTON HANDLERS
-- ═══════════════════════════════════════════════════════════════

-- Redeem button click
local isValidating = false
redeemBtn.MouseButton1Click:Connect(function()
    if isValidating then return end
    isValidating = true
    dlog("Redeem button clicked")

    local key = keyTextbox.Text:gsub("%s+", "")
    if key == "" then
        SetStatus("!", "Please enter a key first.", Color3.fromRGB(248, 113, 113))
        isValidating = false
        return
    end

    SetStatus("...", "Validating key...", Color3.fromRGB(129, 140, 248))
    redeemBtn.Text = "Validating..."

    task.spawn(function()
        ValidateAndExecute(key,
            function(status) -- onSuccess
                local previewOnly = status and status.preview_only == true
                local openedPreview = false
                if previewOnly then
                    openedPreview = TryLoadLocalPreviewUI()
                end

                SetStatus("OK", previewOnly and (openedPreview and "Key valid. Opening preview UI..." or "Key valid. Preview mode ready.") or "Key valid! Script loaded.", Color3.fromRGB(52, 211, 153))
                redeemBtn.Text = previewOnly and (openedPreview and "Opening Preview" or "Preview Ready") or "Success"
                redeemBtn.BackgroundColor3 = Color3.fromRGB(52, 211, 153)

                -- Roblox native notification for auth success
                pcall(function()
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title = "✅ Kojo Hub",
                        Text = "Authentication successful! Script loaded.",
                        Duration = 5,
                    })
                end)
                Notify("Authenticated", previewOnly and (openedPreview and "Key accepted. Preview UI opened." or "Key accepted. Preview mode active.") or "Key accepted. Script loading...", 4, Color3.fromRGB(52, 211, 153))

                -- Update info panel
                if status.data then
                    infoLabels["Tier"].Text = status.data.tier or "—"
                    if status.data.auth_expire and status.data.auth_expire > 0 then
                        infoLabels["Expires"].Text = FormatTime(status.data.auth_expire - os.time())
                    else
                        infoLabels["Expires"].Text = "Lifetime"
                    end
                    infoLabels["Executions"].Text = tostring(status.data.total_executions or 0)
                end

                if previewOnly then
                    if openedPreview then
                        task.wait(0.8)
                        DismissLoaderUI()
                    end
                    return
                end

                -- Close UI after a delay
                task.wait(2)
                dlog("Success - closing UI")
                DismissLoaderUI()
            end,
            function(errorCode) -- onFail
                SetStatus("X", ERROR_MESSAGES[errorCode] or "Validation failed", Color3.fromRGB(248, 113, 113))
                redeemBtn.Text = "Redeem Key"
                redeemBtn.BackgroundColor3 = Color3.fromRGB(129, 140, 248)

                -- Flash input red
                TweenService:Create(inputFrame, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(60, 22, 22)}):Play()
                task.wait(0.5)
                TweenService:Create(inputFrame, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(22, 22, 38)}):Play()
            end
        )
        isValidating = false
    end)
end)

-- Enter key to submit
keyTextbox.FocusLost:Connect(function(enterPressed)
    if enterPressed and not isValidating then
        dlog("Enter pressed in textbox, triggering redeem")
        redeemBtn.MouseButton1Click:Fire()
    end
end)

-- Get Key button → copy key page link
getKeyBtn.MouseButton1Click:Connect(function()
    local keyPage = SERVER_CONFIG.key_page or (BASE_URL .. "/checkpoint.html")
    dlog("Get Key clicked, copying:", keyPage)
    pcall(function()
        if fSetClipboard then
            fSetClipboard(keyPage)
            Notify("📋 Copied", "Key page link copied to clipboard!", 3, Color3.fromRGB(129, 140, 248))
        end
    end)
end)

-- Discord button → copy discord invite
discordBtn.MouseButton1Click:Connect(function()
    local discord = SERVER_CONFIG.discord or ""
    dlog("Discord clicked, copying:", discord)
    pcall(function()
        if fSetClipboard and discord ~= "" then
            fSetClipboard(discord)
            Notify("📋 Copied", "Discord invite copied to clipboard!", 3, Color3.fromRGB(88, 101, 242))
        end
    end)
end)

purchaseBtn.MouseButton1Click:Connect(function()
    local purchaseUrl = SERVER_CONFIG.key_page or (BASE_URL .. "/checkpoint.html")
    dlog("Purchase clicked, copying:", purchaseUrl)
    pcall(function()
        if fSetClipboard and purchaseUrl ~= "" then
            fSetClipboard(purchaseUrl)
            Notify("📋 Copied", "Purchase link copied to clipboard!", 3, Color3.fromRGB(129, 140, 248))
        end
    end)
end)



-- ═══════════════════════════════════════════════════════════════
-- AUTO-VALIDATE FROM SAVED KEY (runs before showing UI)
-- ═══════════════════════════════════════════════════════════════
dlog("Checking for saved key in:", FILE_DIR)

task.spawn(function()
    local savedKey = nil
    pcall(function()
        if getgenv and getgenv().KojoKey then
            savedKey = getgenv().KojoKey
            dlog("Found getgenv().KojoKey")
        elseif isfile and isfile(FILE_DIR) then
            savedKey = readfile(FILE_DIR)
            dlog("Found saved key:", savedKey:sub(1, 15) .. "...")
        end
    end)

    if PREVIEW_UI_ONLY then
        if savedKey and savedKey ~= "" then
            keyTextbox.Text = savedKey
            dlog("Preview mode active: saved key prefilled, auto-validate skipped")
        else
            dlog("Preview mode active: auto-validate skipped")
        end
        ShowLoaderUI()
        Notify("Kojo Hub", "Preview mode active. Enter your key manually.", 5, Color3.fromRGB(129, 140, 248))
        return
    end

    if savedKey and savedKey ~= "" then
        dlog("Auto-validating saved key...")
        Notify("Info", "Found saved key. Validating...", 3, Color3.fromRGB(129, 140, 248))

        local autoOk, autoStatus = pcall(function()
            return api.check_key(savedKey)
        end)

        if autoOk and autoStatus and autoStatus.code == "KEY_VALID" then
            dlog("Auto-validate SUCCESS! Loading script...")
            PublishRuntimeState(autoStatus.data, savedKey)
            PublishSocialState(autoStatus.data and autoStatus.data.profile or nil)
            SetStatus("OK", "Key valid! Loading script...", Color3.fromRGB(52, 211, 153))

            -- Update info panel
            if autoStatus.data then
                infoLabels["Tier"].Text = autoStatus.data.tier or "—"
                if autoStatus.data.auth_expire and autoStatus.data.auth_expire > 0 then
                    infoLabels["Expires"].Text = FormatTime(autoStatus.data.auth_expire - os.time())
                else
                    infoLabels["Expires"].Text = "Lifetime"
                end
                infoLabels["Executions"].Text = tostring(autoStatus.data.total_executions or 0)
            end

            if autoStatus.data and autoStatus.data.auth_expire and autoStatus.data.auth_expire > 0 then
                Notify("✅ Auto-Validated", "Expires in: " .. FormatTime(autoStatus.data.auth_expire - os.time()), 4, Color3.fromRGB(52, 211, 153))
            else
                Notify("✅ Auto-Validated", "Lifetime key active!", 4, Color3.fromRGB(52, 211, 153))
            end

            -- Set up queue_on_teleport
            pcall(function()
                if queue_on_teleport then
                    queue_on_teleport([[
                        loadstring(game:HttpGet("]] .. BASE_URL .. [[/api/v1/loader/key_ui.lua"))()
                    ]])
                end
            end)

            -- Load script — no UI needed!
            task.wait(0.5)
            local loadOk, loadResult, loadErr = pcall(function()
                return api.load_script()
            end)
            if not loadOk or loadResult == false then
                local reason = loadOk and loadErr or loadResult
                dlog("Auto-load failed:", tostring(reason))
                Notify("Auto-Load Failed", tostring(reason or "Script load failed. Please redeem manually."), 6, Color3.fromRGB(248, 113, 113))
                ShowLoaderUI()
                return
            end

            dlog("Script loaded from saved key. UI not shown.")
            -- Don't show UI at all — script is running!
            return
        else
            -- Saved key is invalid — delete it and show UI
            local reason = autoStatus and autoStatus.code or "UNKNOWN"
            dlog("Auto-validate FAILED:", reason)
            SafeDeleteFile(FILE_DIR)
            Notify("Saved key needs attention", ERROR_MESSAGES[reason] or "Please enter a new key.", 5, Color3.fromRGB(248, 113, 113))
        end
    else
        dlog("No saved key found")
    end

    -- Show the UI (with entrance animation)
    ShowLoaderUI()
    Notify("Kojo Hub", "Enter your key to get started!", 5, Color3.fromRGB(129, 140, 248))
end)

rconsoleprint("Loaded KOJO crack by rustygooners.\n")
