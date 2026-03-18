local TAG = "[RerollTracker]"

local load_errors = {}
local function try_require(name)
    local ok, result = pcall(require, name)
    if ok then return result end
    table.insert(load_errors, name .. ": " .. tostring(result))
    return nil
end

local Sdk = try_require("ArtianRerollTracker.Sdk")
local State = try_require("ArtianRerollTracker.State")
local Persistence = try_require("ArtianRerollTracker.Persistence")
local Hooks = try_require("ArtianRerollTracker.Hooks")
local Ui = try_require("ArtianRerollTracker.Ui")
local GrindingFilter = try_require("ArtianRerollTracker.GrindingFilter")
local LotteryFilter = try_require("ArtianRerollTracker.LotteryFilter")

if #load_errors > 0 then
    for _, err in ipairs(load_errors) do
        log.error(TAG .. " Failed to load: " .. err)
    end
    re.on_draw_ui(function()
        if imgui.tree_node("Artian Reroll Tracker [ERROR]") then
            imgui.text_colored("Module load errors:", 0xFF0000FF)
            for _, err in ipairs(load_errors) do
                imgui.text(err)
            end
            imgui.tree_pop()
        end
    end)
    return
end

local FilterFont = nil
if imgui.load_font then
    pcall(function() FilterFont = imgui.load_font(nil, 18) end)
end

State.init(Sdk)
Persistence.init(State)
Hooks.init(Sdk, State)
GrindingFilter.init(Sdk, State, FilterFont)
LotteryFilter.init(Sdk, State, FilterFont)
Ui.init(State)

State.on_save = Persistence.save_to_json

Persistence.load_from_json()
Hooks.register()
Ui.register()
GrindingFilter.register_ui()
LotteryFilter.register_ui()
