-- [[ KojoHub Rewritten Library - Always Valid ]]
local Library = {}

-- Hardcoded properties to mimic a "Premium" user
Library.IsVerified = true
Library.KeyStatus = "Valid"
Library.UserRank = "Premium"
Library.LicenseType = "Lifetime"

-- This function replaces the API call
function Library:Validate(key)
    print("KojoHub API: Manual override detected.")
    print("Key '" .. tostring(key) .. "' has been authenticated.")
    return true
end

-- Mocking the data fetch
function Library:GetUserData()
    return {
        ["username"] = "BypassedUser",
        ["expiry"] = "Never",
        ["status"] = "Active"
    }
end

print("KojoHub Library Loaded [BYPASS MODE]")
return Library
