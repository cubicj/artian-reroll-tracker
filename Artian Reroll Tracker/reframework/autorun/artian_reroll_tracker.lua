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

local TD_ArtianUtil = sdk.find_type_definition("app.ArtianUtil")
local TD_Em0078ArtianUtil = sdk.find_type_definition("app.Em0078_ArtianUtil")
local TD_GuiMessage = sdk.find_type_definition("via.gui.message")
local TD_GUI080000ArtianStatus = sdk.find_type_definition("app.GUI080000ArtianStatus")
local TD_LoopGaugeChangeRequirePoint = sdk.find_type_definition("app.cGUILoopGaugeChangeRequirePoint")
local TD_NotifyWindow = sdk.find_type_definition("app.cGUISystemModuleNotifyWindowApp")
local TD_NotifyWindowDef = sdk.find_type_definition("app.GUINotifyWindowDef.ID")
local TD_WeaponUtil = sdk.find_type_definition("app.WeaponUtil")

local FN_GetBonusName = TD_ArtianUtil and TD_ArtianUtil:get_method("Name(app.ArtianDef.BONUS_ID)")
local FN_GetLocalizedMsg = TD_GuiMessage and TD_GuiMessage:get_method("get(System.Guid)")
local FN_LotterySkill = TD_Em0078ArtianUtil and TD_Em0078ArtianUtil:get_method("lotterySkill(app.savedata.cEquipWork)")
local FN_GetWeaponTypeName = TD_WeaponUtil and TD_WeaponUtil:get_method("getWeaponTypeName(app.WeaponDef.TYPE)")

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

local notifyWindowName2ID, notifyWindowID2Name = getEnumTables(TD_NotifyWindowDef)

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
    if not success then
        log.error("[RerollTracker] init_artian_skill_data error: " .. tostring(err))
    end
end

local TD_MessageUtil = sdk.find_type_definition("app.MessageUtil")
local FN_GetSkillName = TD_MessageUtil and TD_MessageUtil:get_method("getHunterSkillName(app.HunterDef.Skill)")

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
    if sessionType == -1 or RerollTracker.currentSession.weaponTypeName == "Unknown" then
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
    if not success then
        log.error("[RerollTracker] JSON save failed: " .. tostring(err))
    end
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
    sdk.hook(FN_LotterySkill,
        function(args)
            if not RerollTracker.enabled then return end
            RerollTracker._lotterySkillEquipWork = args[2]
        end,
        function(retval)
            if not RerollTracker.enabled then return retval end
            local success, err = pcall(function()
                local equipWork = sdk.to_managed_object(RerollTracker._lotterySkillEquipWork)
                if equipWork then
                    local bonusByCreating = equipWork:get_field("BonusByCreating")
                    if bonusByCreating and bonusByCreating > 0 then
                        local aSkillType = decode_artian_skill_type(bonusByCreating)
                        if aSkillType and aSkillType > 0 then
                            RerollTracker._lastCapturedSkillType = aSkillType
                        end
                    end
                end
            end)
            if not success then
                log.error("[RerollTracker] lotterySkill post-hook error: " .. tostring(err))
            end
            return retval
        end
    )
end

if TD_GUI080000ArtianStatus then
    local bonusColorMethod = TD_GUI080000ArtianStatus:get_method("getEm0078_ArtianBonusColor")
    if bonusColorMethod then
        sdk.hook(bonusColorMethod, function(args)
            if not RerollTracker.enabled then return end
            local success, err = pcall(function()
                local newBonusList = sdk.to_managed_object(args[3])
                if newBonusList then
                    local count = newBonusList:call("get_Count")
                    if count and count > 0 then
                        local bonusIds = {}
                        for i = 0, count - 1 do
                            local bonusId = newBonusList:call("get_Item", i)
                            if bonusId and bonusId > 0 then
                                table.insert(bonusIds, bonusId)
                            end
                        end
                        if #bonusIds > 0 then
                            RerollTracker._lastCapturedBonusIds = bonusIds
                        end
                    end
                end
                local weaponTypeArg = args[7]
                if weaponTypeArg then
                    local weaponType = sdk.to_int64(weaponTypeArg) & 0xFFFFFFFF
                    if weaponType and weaponType >= 0 and weaponType <= 15 then
                        RerollTracker._lastCapturedWeaponType = weaponType
                    end
                end
            end)
            if not success then
                log.error("[RerollTracker] getEm0078_ArtianBonusColor hook error: " .. tostring(err))
            end
        end, nil)
    end

    local setWeaponDataCoreMethod = TD_GUI080000ArtianStatus:get_method("setWeaponDataCore(app.EquipDef.EquipSet)")
    if setWeaponDataCoreMethod then
        sdk.hook(setWeaponDataCoreMethod, function(args)
            if not RerollTracker.enabled then return end
            local success, err = pcall(function()
                local this = sdk.to_managed_object(args[2])
                if this then
                    local perfText = this:get_field("_PerformanceText")
                    if perfText then
                        local perfName = perfText:call("get_Message")
                        if perfName and perfName ~= "" then
                            RerollTracker._lastCapturedAttribute = perfName
                        end
                    end
                end
                local equipSet = sdk.to_managed_object(args[3])
                if equipSet then
                    local weaponData = equipSet:get_field("<WeaponData>k__BackingField")
                    if weaponData then
                        local weaponTypeMapping = {
                            {name = "_LongSword", type = 3},
                            {name = "_ShortSword", type = 1},
                            {name = "_TwinSword", type = 2},
                            {name = "_Tachi", type = 4},
                            {name = "_Hammer", type = 5},
                            {name = "_Whistle", type = 6},
                            {name = "_Lance", type = 7},
                            {name = "_GunLance", type = 8},
                            {name = "_SlashAxe", type = 9},
                            {name = "_ChargeAxe", type = 11},
                            {name = "_Rod", type = 10},
                            {name = "_Bow", type = 12},
                            {name = "_HeavyBowgun", type = 14},
                            {name = "_LightBowgun", type = 13}
                        }
                        for _, mapping in ipairs(weaponTypeMapping) do
                            local value = weaponData:get_field(mapping.name)
                            if value and value > 0 then
                                RerollTracker._lastCapturedWeaponType = mapping.type
                                break
                            end
                        end
                    end
                end
            end)
            if not success then
                log.error("[RerollTracker] setWeaponDataCore hook error: " .. tostring(err))
            end
        end, nil)
    end

    local grindingMethod = TD_GUI080000ArtianStatus:get_method("startArtianGrindingAnim(System.Action)")
    if grindingMethod then
        sdk.hook(grindingMethod, function(args)
            if not RerollTracker.enabled then
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            local success, err = pcall(function()
                local action = sdk.to_managed_object(args[3])
                if action then
                    action:Invoke()
                end
                if RerollTracker.currentSession and RerollTracker.currentSession.mode ~= "grinding" then
                    finish_current_session()
                    RerollTracker.trackingMode = RerollTracker.MODE_GRINDING
                    start_new_session()
                end
                if RerollTracker._lastCapturedBonusIds and #RerollTracker._lastCapturedBonusIds > 0 then
                    record_attempt(RerollTracker._lastCapturedBonusIds)
                    RerollTracker._lastCapturedBonusIds = nil
                end
            end)
            if not success then
                log.error("[RerollTracker] startArtianGrindingAnim hook error: " .. tostring(err))
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, nil)
    end

    local lotteryMethod = TD_GUI080000ArtianStatus:get_method("startSkillLotteryAnim(System.Action)")
    if lotteryMethod then
        sdk.hook(lotteryMethod, function(args)
            if not RerollTracker.enabled then
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            local success, err = pcall(function()
                local action = sdk.to_managed_object(args[3])
                if action then
                    action:Invoke()
                end
                if RerollTracker.currentSession and RerollTracker.currentSession.mode ~= "lottery" then
                    finish_current_session()
                    RerollTracker.trackingMode = RerollTracker.MODE_LOTTERY
                    start_new_session()
                end
                if RerollTracker._lastCapturedSkillType and RerollTracker._lastCapturedSkillType > 0 then
                    local seriesSkill, groupSkill = get_skill_names_from_artian_type(RerollTracker._lastCapturedSkillType)
                    record_skill_attempt(seriesSkill, groupSkill)
                    RerollTracker._lastCapturedSkillType = nil
                end
            end)
            if not success then
                log.error("[RerollTracker] startSkillLotteryAnim hook error: " .. tostring(err))
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, nil)
    end
end

if TD_LoopGaugeChangeRequirePoint then
    local method = TD_LoopGaugeChangeRequirePoint:get_method("startUpGrade(System.UInt32, System.Action)")
    if method then
        sdk.hook(method, function(args)
            if not RerollTracker.enabled then
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            local success, err = pcall(function()
                local action = sdk.to_managed_object(args[4])
                if action then
                    action:Invoke()
                end
            end)
            if not success then
                log.error("[RerollTracker] startUpGrade hook error: " .. tostring(err))
                return sdk.PreHookResult.CALL_ORIGINAL
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, nil)
    end
end

if TD_NotifyWindow then
    local method = TD_NotifyWindow:get_method("requestNotifyWindow")
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
                    notifyWindowInfo:set_SelectedIndex(selectedIndex)
                    local updateAction = notifyWindowInfo:get_UpdateAction()
                    if updateAction and updateAction:get_HasEvent() then
                        updateAction:execute()
                    end
                    notifyWindowInfo:executeWindowEndFunc()
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end)
            if not success then
                log.error("[RerollTracker] Dialog hook error: " .. tostring(result))
            end
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
            if RerollTracker.currentSession then
                local modeText = RerollTracker.currentSession.mode == "grinding" and "Grinding" or "Lottery"
                imgui.same_line()
                imgui.text(string.format("| %s | %s | Attempts: %d",
                    modeText,
                    RerollTracker.currentSession.nickname,
                    #RerollTracker.currentSession.attempts))
            end
        else
            imgui.text_colored("Status: INACTIVE", 0xFF888888)
        end

        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        if RerollTracker.currentSession then
            imgui.text("Current:")
            imgui.text(string.format("  %s", RerollTracker.currentSession.nickname))
        else
            imgui.text_colored("Weapon: (Auto-detected on first action)", 0xFF888888)
        end

        imgui.spacing()
        imgui.separator()

        if imgui.button("Clear History") then
            RerollTracker.clear_history()
        end

        imgui.spacing()
        imgui.text(string.format("JSON: reframework/data/%s", RerollTracker.dataFilePath))
        imgui.text(string.format("Total weapons recorded: %d", #RerollTracker.weapons))

        imgui.tree_pop()
    end
end)
