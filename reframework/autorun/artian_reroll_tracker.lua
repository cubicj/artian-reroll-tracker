local RerollTracker = {}

RerollTracker.enabled = false
RerollTracker.currentSession = nil
RerollTracker.weapons = {}
RerollTracker.attemptCount = 0
RerollTracker.dataFilePath = "reroll_sessions.json"

RerollTracker.trackingMode = 1
RerollTracker.MODE_GRINDING = 1
RerollTracker.MODE_LOTTERY = 2

RerollTracker._lastCapturedBonusIds = nil
RerollTracker._lastCapturedSkillType = nil
RerollTracker._lastCapturedWeaponType = nil
RerollTracker._lastCapturedAttribute = nil

local TAG = "[RerollTracker]"

local TD_ArtianUtil = sdk.find_type_definition("app.ArtianUtil")
local TD_Em0078ArtianUtil = sdk.find_type_definition("app.Em0078_ArtianUtil")
local TD_GuiMessage = sdk.find_type_definition("via.gui.message")
local TD_GUI080000ArtianStatus = sdk.find_type_definition("app.GUI080000ArtianStatus")
local TD_LoopGaugeChangeRequirePoint = sdk.find_type_definition("app.cGUILoopGaugeChangeRequirePoint")
local TD_NotifyWindow = sdk.find_type_definition("app.cGUISystemModuleNotifyWindowApp")
local TD_NotifyWindowDef = sdk.find_type_definition("app.GUINotifyWindowDef.ID")
local TD_WeaponUtil = sdk.find_type_definition("app.WeaponUtil")
local TD_WeaponDef = sdk.find_type_definition("app.WeaponDef")
local TD_WeaponDefType = sdk.find_type_definition("app.WeaponDef.TYPE")
local TD_WeaponDefTypeFixed = sdk.find_type_definition("app.WeaponDef.TYPE_Fixed")

log.info(TAG .. " [INIT] TypeDefs: " ..
    "ArtianUtil=" .. tostring(TD_ArtianUtil ~= nil) ..
    " Em0078ArtianUtil=" .. tostring(TD_Em0078ArtianUtil ~= nil) ..
    " GuiMessage=" .. tostring(TD_GuiMessage ~= nil) ..
    " GUI080000ArtianStatus=" .. tostring(TD_GUI080000ArtianStatus ~= nil) ..
    " LoopGauge=" .. tostring(TD_LoopGaugeChangeRequirePoint ~= nil) ..
    " NotifyWindow=" .. tostring(TD_NotifyWindow ~= nil) ..
    " NotifyWindowDef=" .. tostring(TD_NotifyWindowDef ~= nil) ..
    " WeaponUtil=" .. tostring(TD_WeaponUtil ~= nil))

local FN_GetBonusName = TD_ArtianUtil and TD_ArtianUtil:get_method("Name(app.ArtianDef.BONUS_ID)")
local FN_GetLocalizedMsg = TD_GuiMessage and TD_GuiMessage:get_method("get(System.Guid)")
local FN_LotterySkill = TD_Em0078ArtianUtil and TD_Em0078ArtianUtil:get_method("lotterySkill(app.savedata.cEquipWork)")
local FN_GetWeaponTypeName = TD_WeaponUtil and TD_WeaponUtil:get_method("getWeaponTypeName(app.WeaponDef.TYPE)")
local FN_GetTYPEFromFixed = TD_WeaponDef and TD_WeaponDef:get_method("getTYPEFromFixed(app.WeaponDef.TYPE_Fixed, app.WeaponDef.TYPE)")

log.info(TAG .. " [INIT] Methods: " ..
    "GetBonusName=" .. tostring(FN_GetBonusName ~= nil) ..
    " GetLocalizedMsg=" .. tostring(FN_GetLocalizedMsg ~= nil) ..
    " LotterySkill=" .. tostring(FN_LotterySkill ~= nil) ..
    " GetWeaponTypeName=" .. tostring(FN_GetWeaponTypeName ~= nil) ..
    " GetTYPEFromFixed=" .. tostring(FN_GetTYPEFromFixed ~= nil))

local function getEnumTables(typeDef)
    local byName, byValue = {}, {}
    if not typeDef then return byName, byValue end
    local fields = typeDef:get_fields()
    for _, field in ipairs(fields) do
        if field:is_static() then
            local name, value = field:get_name(), field:get_data()
            byName[name] = value
            byValue[value] = name
        end
    end
    return byName, byValue
end

local _, notifyWindowID2Name = getEnumTables(TD_NotifyWindowDef)

local fixedToTypeMap = {}

do
    local weaponByName, _ = getEnumTables(TD_WeaponDefType)
    local entries = {}
    for name, value in pairs(weaponByName) do
        table.insert(entries, name .. "=" .. tostring(value))
    end
    table.sort(entries)
    log.info(TAG .. " [INIT] WeaponDef.TYPE enum (" .. #entries .. " entries): " .. table.concat(entries, ", "))

    local fixedByName, _ = getEnumTables(TD_WeaponDefTypeFixed)
    entries = {}
    for name, value in pairs(fixedByName) do
        table.insert(entries, name .. "=" .. tostring(value))
    end
    table.sort(entries)
    log.info(TAG .. " [INIT] WeaponDef.TYPE_Fixed enum (" .. #entries .. " entries): " .. table.concat(entries, ", "))

    local mapCount = 0
    for name, fixedValue in pairs(fixedByName) do
        if name ~= "INVALID" and name ~= "MAX" and weaponByName[name] ~= nil then
            fixedToTypeMap[fixedValue] = weaponByName[name]
            mapCount = mapCount + 1
            log.info(TAG .. " [INIT] Fixed→TYPE: " .. name .. " fixed=" .. tostring(fixedValue) .. " → type=" .. tostring(weaponByName[name]))
        end
    end
    log.info(TAG .. " [INIT] fixedToTypeMap built with " .. tostring(mapCount) .. " entries")
end

local function get_bonus_name(bonusId)
    if not FN_GetBonusName or not FN_GetLocalizedMsg then
        return string.format("Bonus_%d", bonusId)
    end
    local success, result = pcall(function()
        local guidObj = FN_GetBonusName:call(nil, bonusId)
        if not guidObj then return string.format("Bonus_%d", bonusId) end
        local text = FN_GetLocalizedMsg:call(nil, guidObj)
        if text and text ~= "" then return text end
        return string.format("Bonus_%d", bonusId)
    end)
    if success then return result end
    return string.format("Bonus_%d", bonusId)
end

local function get_weapon_type_name(weaponType)
    if not FN_GetWeaponTypeName or not FN_GetLocalizedMsg then
        return string.format("Type_%d", weaponType)
    end
    local success, result = pcall(function()
        local guidObj = FN_GetWeaponTypeName:call(nil, weaponType)
        if not guidObj then return string.format("Type_%d", weaponType) end
        local text = FN_GetLocalizedMsg:call(nil, guidObj)
        if text and text ~= "" then return text end
        return string.format("Type_%d", weaponType)
    end)
    if success then return result end
    return string.format("Type_%d", weaponType)
end

local ArtianSkillData = nil
local ArtianSkillDataInited = false

local function init_artian_skill_data()
    if ArtianSkillDataInited then return end
    local success, err = pcall(function()
        local mgr = sdk.get_managed_singleton("app.VariousDataManager")
        if not mgr then return end
        local skillGroup = mgr._Setting._EquipDatas._ArtianDataSetting._ArtianSkillGroup._Values
        if not skillGroup then return end
        ArtianSkillData = {}
        local count = skillGroup:call("get_Count")
        for i = 0, count - 1 do
            local data = skillGroup:call("get_Item", i)
            if data then
                local aSkillType = data:call("get_ArtianSkillType")
                local seriesId = data:call("get_SeriesSkillId")
                local groupId = data:call("get_GroupSkillId")
                ArtianSkillData[aSkillType] = {
                    seriesId = seriesId,
                    groupId = groupId
                }
            end
        end
        ArtianSkillDataInited = true
    end)
end

local TD_MessageUtil = sdk.find_type_definition("app.MessageUtil")
local FN_GetSkillName = TD_MessageUtil and TD_MessageUtil:get_method("getHunterSkillName(app.HunterDef.Skill)")

log.info(TAG .. " [INIT] MessageUtil=" .. tostring(TD_MessageUtil ~= nil) ..
    " GetSkillName=" .. tostring(FN_GetSkillName ~= nil))

local function get_skill_name(skillId)
    if not skillId or skillId <= 0 then return "" end
    local success, result = pcall(function()
        if FN_GetSkillName and FN_GetLocalizedMsg then
            local guidObj = FN_GetSkillName:call(nil, skillId)
            if guidObj then
                local name = FN_GetLocalizedMsg:call(nil, guidObj)
                if name and name ~= "" then return name end
            end
        end
        return string.format("Skill_%d", skillId)
    end)
    if success then return result end
    return string.format("Skill_%d", skillId)
end

local function decode_artian_skill_type(bonusByCreating)
    local first = bonusByCreating % 1000
    local second = math.floor(bonusByCreating / 1000) % 1000
    local third = math.floor(bonusByCreating / 1000000) % 1000
    local asFirst = math.floor(first / 10) % 10
    local asSecond = math.floor(second / 10) % 10
    local asThird = math.floor(third / 10) % 10
    return asThird * 100 + asSecond * 10 + asFirst
end

local function get_skill_names_from_artian_type(aSkillType)
    init_artian_skill_data()
    if not ArtianSkillData or not ArtianSkillData[aSkillType] then
        return string.format("ArtianSkill_%d", aSkillType), ""
    end
    local data = ArtianSkillData[aSkillType]
    local seriesName = get_skill_name(data.seriesId)
    local groupName = get_skill_name(data.groupId)
    return seriesName, groupName
end

local function find_existing_session(weaponType, attribute)
    for i, weapon in ipairs(RerollTracker.weapons) do
        if weapon.weaponType == weaponType and weapon.attribute == attribute then
            return i
        end
    end
    return nil
end

local function save_current_session_to_weapons()
    if not RerollTracker.currentSession then return end
    if #RerollTracker.currentSession.attempts == 0 then return end
    local existingIndex = find_existing_session(
        RerollTracker.currentSession.weaponType,
        RerollTracker.currentSession.attribute
    )
    if existingIndex then
        RerollTracker.weapons[existingIndex] = RerollTracker.currentSession
    else
        table.insert(RerollTracker.weapons, RerollTracker.currentSession)
    end
end

local function finish_current_session()
    if not RerollTracker.currentSession then return nil, 0 end
    local totalAttempts = #RerollTracker.currentSession.attempts
    if totalAttempts == 0 then
        RerollTracker.currentSession = nil
        RerollTracker.attemptCount = 0
        return nil, 0
    end
    RerollTracker.currentSession.endTime = os.date("%Y-%m-%d %H:%M:%S")
    RerollTracker.currentSession.totalAttempts = totalAttempts
    table.insert(RerollTracker.weapons, RerollTracker.currentSession)
    local nickname = RerollTracker.currentSession.nickname
    local total = RerollTracker.currentSession.totalAttempts
    RerollTracker.currentSession = nil
    RerollTracker.attemptCount = 0
    RerollTracker.save_to_json()
    return nickname, total
end

local function start_new_session()
    if RerollTracker.currentSession then
        finish_current_session()
    end
    local modeName = RerollTracker.trackingMode == RerollTracker.MODE_GRINDING and "grinding" or "lottery"
    RerollTracker.currentSession = {
        nickname = "Unknown",
        weaponType = -1,
        weaponTypeName = "Unknown",
        attribute = "",
        mode = modeName,
        startTime = os.date("%Y-%m-%d %H:%M:%S"),
        attempts = {}
    }
    RerollTracker.attemptCount = 0
end

local function check_and_update_session_weapon()
    if not RerollTracker.currentSession then return end
    local capturedType = RerollTracker._lastCapturedWeaponType
    local capturedAttribute = RerollTracker._lastCapturedAttribute or ""
    local sessionType = RerollTracker.currentSession.weaponType
    local sessionAttribute = RerollTracker.currentSession.attribute or ""
    log.info(TAG .. " [SESSION] check: captured(" .. tostring(capturedType) .. "/" .. capturedAttribute ..
        ") vs session(" .. tostring(sessionType) .. "/" .. sessionAttribute .. ")")
    if sessionType == -1 or RerollTracker.currentSession.weaponTypeName == "Unknown" then
        log.info(TAG .. " [SESSION] first detection: weaponType=" .. tostring(capturedType))
        if capturedType then
            local newTypeName = get_weapon_type_name(capturedType)
            RerollTracker.currentSession.weaponType = capturedType
            RerollTracker.currentSession.weaponTypeName = newTypeName
            RerollTracker.currentSession.attribute = capturedAttribute
            local nickname = newTypeName
            if capturedAttribute ~= "" then
                nickname = capturedAttribute .. " " .. nickname
            end
            RerollTracker.currentSession.nickname = nickname
        end
        return
    end
    local typeChanged = capturedType and capturedType ~= sessionType
    local attrChanged = capturedAttribute ~= "" and sessionAttribute ~= "" and capturedAttribute ~= sessionAttribute
    if typeChanged or attrChanged then
        log.info(TAG .. " [SESSION] SPLIT: typeChanged=" .. tostring(typeChanged) .. " attrChanged=" .. tostring(attrChanged))
        save_current_session_to_weapons()
        local existingIndex = find_existing_session(capturedType, capturedAttribute)
        if existingIndex then
            RerollTracker.currentSession = RerollTracker.weapons[existingIndex]
            RerollTracker.attemptCount = #RerollTracker.currentSession.attempts
            table.remove(RerollTracker.weapons, existingIndex)
        else
            local modeName = RerollTracker.trackingMode == RerollTracker.MODE_GRINDING and "grinding" or "lottery"
            RerollTracker.currentSession = {
                nickname = "Unknown",
                weaponType = -1,
                weaponTypeName = "Unknown",
                attribute = "",
                mode = modeName,
                startTime = os.date("%Y-%m-%d %H:%M:%S"),
                attempts = {}
            }
            RerollTracker.attemptCount = 0
        end
        if capturedType then
            local newTypeName = get_weapon_type_name(capturedType)
            RerollTracker.currentSession.weaponType = capturedType
            RerollTracker.currentSession.weaponTypeName = newTypeName
            RerollTracker.currentSession.attribute = capturedAttribute
            local nickname = newTypeName
            if capturedAttribute ~= "" then
                nickname = capturedAttribute .. " " .. nickname
            end
            RerollTracker.currentSession.nickname = nickname
        end
        RerollTracker.save_to_json()
    end
end

local function record_attempt(bonusIds)
    if not RerollTracker.enabled or not RerollTracker.currentSession then return end
    if #bonusIds == 0 then return end
    check_and_update_session_weapon()
    RerollTracker.attemptCount = RerollTracker.attemptCount + 1
    local bonusNames = {}
    for _, id in ipairs(bonusIds) do
        table.insert(bonusNames, get_bonus_name(id))
    end
    local attempt = {
        attemptNum = RerollTracker.attemptCount,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        bonuses = bonusNames
    }
    table.insert(RerollTracker.currentSession.attempts, attempt)
    RerollTracker.save_to_json()
end

local function record_skill_attempt(seriesSkill, groupSkill)
    if not RerollTracker.enabled or not RerollTracker.currentSession then return end
    if not seriesSkill or seriesSkill == "" then return end
    check_and_update_session_weapon()
    RerollTracker.attemptCount = RerollTracker.attemptCount + 1
    local attempt = {
        attemptNum = RerollTracker.attemptCount,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        skills = {
            series = seriesSkill,
            group = groupSkill or ""
        }
    }
    table.insert(RerollTracker.currentSession.attempts, attempt)
    RerollTracker.save_to_json()
end

function RerollTracker.save_to_json()
    local success, err = pcall(function()
        local weaponsToSave = {}
        for _, weapon in ipairs(RerollTracker.weapons) do
            local tempWeapon = {}
            for k, v in pairs(weapon) do
                tempWeapon[k] = v
            end
            table.insert(weaponsToSave, tempWeapon)
        end
        if RerollTracker.currentSession and #RerollTracker.currentSession.attempts > 0 then
            local tempSession = {}
            for k, v in pairs(RerollTracker.currentSession) do
                tempSession[k] = v
            end
            tempSession.isCurrent = true
            table.insert(weaponsToSave, tempSession)
        end
        local data = {
            lastUpdated = os.date("%Y-%m-%d %H:%M:%S"),
            totalWeapons = #RerollTracker.weapons,
            weapons = weaponsToSave
        }
        json.dump_file(RerollTracker.dataFilePath, data)
    end)
end

function RerollTracker.load_from_json()
    local success, data = pcall(function()
        return json.load_file(RerollTracker.dataFilePath)
    end)
    if success and data then
        RerollTracker.weapons = {}
        for _, weapon in ipairs(data.weapons or {}) do
            if weapon.isCurrent then
                weapon.isCurrent = nil
                RerollTracker.currentSession = weapon
                RerollTracker.attemptCount = #weapon.attempts
            else
                table.insert(RerollTracker.weapons, weapon)
            end
        end
    end
end

function RerollTracker.clear_history()
    RerollTracker.weapons = {}
    RerollTracker.currentSession = nil
    RerollTracker.attemptCount = 0
    RerollTracker._lastCapturedBonusIds = nil
    RerollTracker._lastCapturedSkillType = nil
    RerollTracker._lastCapturedWeaponType = nil
    RerollTracker._lastCapturedAttribute = nil
    RerollTracker.save_to_json()
    if RerollTracker.enabled then
        start_new_session()
    end
end

if FN_LotterySkill then
    log.info(TAG .. " [INIT] Hooking lotterySkill")
    sdk.hook(FN_LotterySkill,
        function(args)
            if not RerollTracker.enabled then return end
            RerollTracker._lotterySkillEquipWork = args[2]
        end,
        function(retval)
            if not RerollTracker.enabled then return retval end
            local success, err = pcall(function()
                local equipWork = sdk.to_managed_object(RerollTracker._lotterySkillEquipWork)
                log.info(TAG .. " [HOOK] lotterySkill POST: equipWork=" .. tostring(equipWork ~= nil))
                if equipWork then
                    local bonusByCreating = equipWork:get_field("BonusByCreating")
                    log.info(TAG .. " [HOOK] lotterySkill: BonusByCreating=" .. tostring(bonusByCreating))
                    if bonusByCreating and bonusByCreating > 0 then
                        local aSkillType = decode_artian_skill_type(bonusByCreating)
                        log.info(TAG .. " [HOOK] lotterySkill: decoded aSkillType=" .. tostring(aSkillType))
                        if aSkillType and aSkillType > 0 then
                            RerollTracker._lastCapturedSkillType = aSkillType
                        end
                    end
                end
            end)
            if not success then log.error(TAG .. " [HOOK] lotterySkill error: " .. tostring(err)) end
            return retval
        end
    )
end

if TD_GUI080000ArtianStatus then
    local bonusColorMethod = TD_GUI080000ArtianStatus:get_method("getEm0078_ArtianBonusColor")
    log.info(TAG .. " [INIT] bonusColorMethod=" .. tostring(bonusColorMethod ~= nil))
    if bonusColorMethod then
        sdk.hook(bonusColorMethod, function(args)
            if not RerollTracker.enabled then return end
            local success, err = pcall(function()
                local newBonusList = sdk.to_managed_object(args[3])
                log.info(TAG .. " [HOOK] bonusColor PRE: bonusList=" .. tostring(newBonusList ~= nil))
                if newBonusList then
                    local count = newBonusList:call("get_Count")
                    log.info(TAG .. " [HOOK] bonusColor: count=" .. tostring(count))
                    if count and count > 0 then
                        local bonusIds = {}
                        for i = 0, count - 1 do
                            local bonusId = newBonusList:call("get_Item", i)
                            if bonusId and bonusId > 0 then
                                table.insert(bonusIds, bonusId)
                            end
                        end
                        if #bonusIds > 0 then
                            log.info(TAG .. " [HOOK] bonusColor: captured " .. #bonusIds .. " bonusIds: " .. table.concat(bonusIds, ","))
                            RerollTracker._lastCapturedBonusIds = bonusIds
                        end
                    end
                end
            end)
            if not success then log.error(TAG .. " [HOOK] bonusColor error: " .. tostring(err)) end
        end, nil)
    end

    local setWeaponDataCoreMethod = TD_GUI080000ArtianStatus:get_method("setWeaponDataCore(app.EquipDef.EquipSet)")
    log.info(TAG .. " [INIT] setWeaponDataCoreMethod=" .. tostring(setWeaponDataCoreMethod ~= nil))
    if setWeaponDataCoreMethod then
        sdk.hook(setWeaponDataCoreMethod, function(args)
            if not RerollTracker.enabled then return end
            local success, err = pcall(function()
                local this = sdk.to_managed_object(args[2])
                log.info(TAG .. " [HOOK] setWeaponDataCore PRE: this=" .. tostring(this ~= nil))
                if this then
                    local perfText = this:get_field("_PerformanceText")
                    log.info(TAG .. " [HOOK] setWeaponDataCore: perfText=" .. tostring(perfText ~= nil))
                    if perfText then
                        local perfName = perfText:call("get_Message")
                        log.info(TAG .. " [HOOK] setWeaponDataCore: attribute=" .. tostring(perfName))
                        if perfName and perfName ~= "" then
                            RerollTracker._lastCapturedAttribute = perfName
                        end
                    end
                end
                local equipSet = sdk.to_managed_object(args[3])
                log.info(TAG .. " [HOOK] setWeaponDataCore: equipSet=" .. tostring(equipSet ~= nil))
                if equipSet then
                    local weaponData = equipSet:get_field("<WeaponData>k__BackingField")
                    log.info(TAG .. " [HOOK] setWeaponDataCore: weaponData=" .. tostring(weaponData ~= nil))
                    if weaponData then
                        local rawType = weaponData:get_field("_Type")
                        local weaponType = rawType
                        if rawType and fixedToTypeMap[rawType] ~= nil then
                            weaponType = fixedToTypeMap[rawType]
                        end
                        log.info(TAG .. " [HOOK] setWeaponDataCore: rawType=" .. tostring(rawType) .. " → weaponType=" .. tostring(weaponType))
                        if weaponType and weaponType >= 0 and weaponType <= 13 then
                            RerollTracker._lastCapturedWeaponType = weaponType
                        end
                    end
                end
            end)
            if not success then log.error(TAG .. " [HOOK] setWeaponDataCore error: " .. tostring(err)) end
        end, nil)
    end

    local grindingMethod = TD_GUI080000ArtianStatus:get_method("startArtianGrindingAnim(System.Action)")
    log.info(TAG .. " [INIT] grindingMethod=" .. tostring(grindingMethod ~= nil))
    if grindingMethod then
        sdk.hook(grindingMethod, function(args)
            if not RerollTracker.enabled then
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            local success, err = pcall(function()
                log.info(TAG .. " [HOOK] grinding PRE: capturedWeapon=" .. tostring(RerollTracker._lastCapturedWeaponType) ..
                    " capturedAttr=" .. tostring(RerollTracker._lastCapturedAttribute) ..
                    " capturedBonusIds=" .. tostring(RerollTracker._lastCapturedBonusIds ~= nil and #RerollTracker._lastCapturedBonusIds or "nil") ..
                    " session.weaponType=" .. tostring(RerollTracker.currentSession and RerollTracker.currentSession.weaponType) ..
                    " session.mode=" .. tostring(RerollTracker.currentSession and RerollTracker.currentSession.mode) ..
                    " attemptCount=" .. tostring(RerollTracker.attemptCount))
                local action = sdk.to_managed_object(args[3])
                if action then
                    action:Invoke()
                end
                if RerollTracker.currentSession and RerollTracker.currentSession.mode ~= "grinding" then
                    log.info(TAG .. " [HOOK] grinding: mode switch from " .. tostring(RerollTracker.currentSession.mode) .. " to grinding")
                    finish_current_session()
                    RerollTracker.trackingMode = RerollTracker.MODE_GRINDING
                    start_new_session()
                end
                if RerollTracker._lastCapturedBonusIds and #RerollTracker._lastCapturedBonusIds > 0 then
                    log.info(TAG .. " [HOOK] grinding: recording attempt with " .. #RerollTracker._lastCapturedBonusIds .. " bonuses")
                    record_attempt(RerollTracker._lastCapturedBonusIds)
                    RerollTracker._lastCapturedBonusIds = nil
                else
                    log.info(TAG .. " [HOOK] grinding: NO bonusIds captured, skipping record")
                end
                log.info(TAG .. " [HOOK] grinding POST: session.nickname=" .. tostring(RerollTracker.currentSession and RerollTracker.currentSession.nickname) ..
                    " attemptCount=" .. tostring(RerollTracker.attemptCount))
            end)
            if not success then
                log.error(TAG .. " [HOOK] grinding error: " .. tostring(err))
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, nil)
    end

    local lotteryMethod = TD_GUI080000ArtianStatus:get_method("startSkillLotteryAnim(System.Action)")
    log.info(TAG .. " [INIT] lotteryMethod=" .. tostring(lotteryMethod ~= nil))
    if lotteryMethod then
        sdk.hook(lotteryMethod, function(args)
            if not RerollTracker.enabled then
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            local success, err = pcall(function()
                log.info(TAG .. " [HOOK] lottery PRE: capturedSkillType=" .. tostring(RerollTracker._lastCapturedSkillType) ..
                    " capturedWeapon=" .. tostring(RerollTracker._lastCapturedWeaponType) ..
                    " session.mode=" .. tostring(RerollTracker.currentSession and RerollTracker.currentSession.mode) ..
                    " attemptCount=" .. tostring(RerollTracker.attemptCount))
                local action = sdk.to_managed_object(args[3])
                if action then
                    action:Invoke()
                end
                if RerollTracker.currentSession and RerollTracker.currentSession.mode ~= "lottery" then
                    log.info(TAG .. " [HOOK] lottery: mode switch from " .. tostring(RerollTracker.currentSession.mode) .. " to lottery")
                    finish_current_session()
                    RerollTracker.trackingMode = RerollTracker.MODE_LOTTERY
                    start_new_session()
                end
                if RerollTracker._lastCapturedSkillType and RerollTracker._lastCapturedSkillType > 0 then
                    local seriesSkill, groupSkill = get_skill_names_from_artian_type(RerollTracker._lastCapturedSkillType)
                    log.info(TAG .. " [HOOK] lottery: recording skill attempt: series=" .. tostring(seriesSkill) .. " group=" .. tostring(groupSkill))
                    record_skill_attempt(seriesSkill, groupSkill)
                    RerollTracker._lastCapturedSkillType = nil
                else
                    log.info(TAG .. " [HOOK] lottery: NO skillType captured, skipping record")
                end
                log.info(TAG .. " [HOOK] lottery POST: session.nickname=" .. tostring(RerollTracker.currentSession and RerollTracker.currentSession.nickname) ..
                    " attemptCount=" .. tostring(RerollTracker.attemptCount))
            end)
            if not success then
                log.error(TAG .. " [HOOK] lottery error: " .. tostring(err))
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, nil)
    end
end

if TD_LoopGaugeChangeRequirePoint then
    local method = TD_LoopGaugeChangeRequirePoint:get_method("startUpGrade(System.UInt32, System.Action)")
    log.info(TAG .. " [INIT] startUpGrade=" .. tostring(method ~= nil))
    if method then
        sdk.hook(method, function(args)
            if not RerollTracker.enabled then
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            local success, err = pcall(function()
                log.info(TAG .. " [HOOK] startUpGrade PRE: skipping animation")
                local action = sdk.to_managed_object(args[4])
                if action then
                    action:Invoke()
                end
            end)
            if not success then
                log.error(TAG .. " [HOOK] startUpGrade error: " .. tostring(err))
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, nil)
    end
end

if TD_NotifyWindow then
    local method = TD_NotifyWindow:get_method("requestNotifyWindow")
    log.info(TAG .. " [INIT] requestNotifyWindow=" .. tostring(method ~= nil))
    if method then
        sdk.hook(method, function(args)
            local success, result = pcall(function()
                local notifyWindowInfo = sdk.to_managed_object(args[3])
                if not notifyWindowInfo then return end
                local textInfo = notifyWindowInfo:get_TextInfo()
                if not textInfo then return end
                local windowId = notifyWindowInfo:get_NotifyWindowId()
                if not windowId then return end
                local windowIdName = notifyWindowID2Name[windowId] or string.format("UNKNOWN_%d", windowId)
                log.info(TAG .. " [HOOK] notifyWindow: windowIdName=" .. windowIdName)
                if not RerollTracker.enabled then return end
                local targetDialogs = {
                    ["EQUIP_000"] = 0,
                    ["EQUIPMENT_0008_15"] = 0,
                    ["GUI080301_0005_DLG"] = 0,
                    ["GUI080301_0009_DLG"] = 1,
                    ["GUI080301_0010_DLG"] = 1,
                }
                local selectedIndex = targetDialogs[windowIdName]
                if selectedIndex ~= nil then
                    log.info(TAG .. " [HOOK] notifyWindow: auto-confirming " .. windowIdName .. " with index=" .. tostring(selectedIndex))
                    notifyWindowInfo:set_SelectedIndex(selectedIndex)
                    local updateAction = notifyWindowInfo:get_UpdateAction()
                    if updateAction and updateAction:get_HasEvent() then
                        updateAction:execute()
                    end
                    notifyWindowInfo:executeWindowEndFunc()
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end)
            if not success then log.error(TAG .. " [HOOK] notifyWindow error: " .. tostring(result)) end
            return result
        end, nil)
    end
end

RerollTracker.load_from_json()

re.on_draw_ui(function()
    if imgui.tree_node("Artian Reroll Tracker") then
        local changed, newValue = imgui.checkbox("Enable Tracker", RerollTracker.enabled)
        if changed then
            RerollTracker.enabled = newValue
            if newValue and not RerollTracker.currentSession then
                start_new_session()
            end
        end

        imgui.spacing()

        if RerollTracker.enabled then
            imgui.text_colored("Status: ACTIVE", 0xFF00FF00)
            if RerollTracker.currentSession and RerollTracker.currentSession.nickname and RerollTracker.currentSession.attempts then
                local modeText = RerollTracker.currentSession.mode == "grinding" and "Grinding" or "Lottery"
                imgui.same_line()
                local success, result = pcall(function()
                    return string.format("| %s | %s | Attempts: %d",
                        modeText,
                        RerollTracker.currentSession.nickname or "Unknown",
                        type(RerollTracker.currentSession.attempts) == "table" and #RerollTracker.currentSession.attempts or 0)
                end)
                if success then
                    imgui.text(result)
                end
            end
        else
            imgui.text_colored("Status: INACTIVE", 0xFF888888)
        end

        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        if RerollTracker.currentSession and RerollTracker.currentSession.nickname then
            imgui.text("Current:")
            local success, result = pcall(function()
                return string.format("  %s", RerollTracker.currentSession.nickname or "Unknown")
            end)
            if success then
                imgui.text(result)
            end
        else
            imgui.text_colored("Weapon: (Auto-detected on first action)", 0xFF888888)
        end

        imgui.spacing()
        imgui.separator()

        if imgui.button("Clear History") then
            RerollTracker.clear_history()
        end

        imgui.spacing()
        local success, result = pcall(function()
            return string.format("JSON: reframework/data/%s", RerollTracker.dataFilePath or "unknown")
        end)
        if success then
            imgui.text(result)
        end

        success, result = pcall(function()
            return string.format("Total weapons recorded: %d",
                type(RerollTracker.weapons) == "table" and #RerollTracker.weapons or 0)
        end)
        if success then
            imgui.text(result)
        end

        imgui.tree_pop()
    end
end)
