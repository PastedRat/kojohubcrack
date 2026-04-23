-- [[ KojoHub Rewritten Key UI - Auto-Pass ]]
local KeyUI = {}

KeyUI.WindowName = "KojoHub Loader"

function KeyUI:CreateMenu()
    print("KojoHub UI: Skipping key entry...")
    
    -- If the script uses a callback for when the key is right, we trigger it now
    if self.OnSuccess then
        task.spawn(function()
            task.wait(0.5) -- Small delay for 'realism'
            self.OnSuccess()
        end)
    end
    
    return true
end

function KeyUI:Visible(state)
    print("KojoHub UI: Visibility toggled to " .. tostring(state))
end

function KeyUI:Destroy()
    print("KojoHub UI: Cleaning up.")
end

print("KojoHub Key UI Loaded [BYPASS MODE]")
return KeyUI
