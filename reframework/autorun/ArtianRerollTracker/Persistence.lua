local TAG = "[RerollTracker]"
local State
local _M = {}

function _M.init(state)
    State = state
end

function _M.save_to_json()
    pcall(function()
        local RT = State.RerollTracker
        local weaponsToSave = {}
        for _, weapon in ipairs(RT.weapons) do
            local copy = {}
            for k, v in pairs(weapon) do copy[k] = v end
            table.insert(weaponsToSave, copy)
        end
        if RT.currentSession and #RT.currentSession.attempts > 0 then
            local copy = {}
            for k, v in pairs(RT.currentSession) do copy[k] = v end
            copy.isCurrent = true
            table.insert(weaponsToSave, copy)
        end
        json.dump_file(RT.dataFilePath, {
            lastUpdated = os.date("%Y-%m-%d %H:%M:%S"),
            totalWeapons = #weaponsToSave,
            weapons = weaponsToSave
        })
    end)
end

function _M.load_from_json()
    local RT = State.RerollTracker
    local success, data = pcall(function()
        return json.load_file(RT.dataFilePath)
    end)
    if not success or not data then return end
    if type(data.weapons) ~= "table" then return end
    RT.weapons = {}
    for _, weapon in ipairs(data.weapons) do
        if type(weapon) ~= "table" or type(weapon.attempts) ~= "table" then
            log.error(TAG .. " Skipped invalid session entry in " .. RT.dataFilePath)
        elseif weapon.isCurrent then
            weapon.isCurrent = nil
            RT.currentSession = weapon
            RT.attemptCount = #weapon.attempts
        else
            table.insert(RT.weapons, weapon)
        end
    end
end

return _M
