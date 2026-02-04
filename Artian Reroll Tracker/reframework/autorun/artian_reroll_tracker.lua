local log = log
local sdk = sdk
local json = json
local imgui = imgui
local re = re
local os = os

local RerollTracker = {}

local TD_SaveDataManager = sdk.find_type_definition("app.SaveDataManager")
local TD_ArtianUtil = sdk.find_type_definition("app.ArtianUtil")
local TD_GuiMessage = sdk.find_type_definition("via.gui.message")
local TD_EquipWork = sdk.find_type_definition("app.savedata.cEquipWork")
local TD_VariousDataManager = sdk.find_type_definition("app.VariousDataManager")
local TD_MessageUtil = sdk.find_type_definition("app.MessageUtil")

local FN_GetCurrentUserSaveData = TD_SaveDataManager:get_method("getCurrentUserSaveData()")
local FN_GetBonusIdList = TD_ArtianUtil:get_method("getBonusIdList(app.savedata.cEquipWork)")
local FN_GetBonusName = TD_ArtianUtil:get_method("Name(app.ArtianDef.BONUS_ID)")
local FN_GetLocalizedMsg = TD_GuiMessage:get_method("get(System.Guid)")
local FN_GetPerformanceType = TD_ArtianUtil:get_method("getPerformanceType(app.savedata.cEquipWork)")
local FN_GetSkillName = TD_MessageUtil and TD_MessageUtil:get_method("getHunterSkillName(app.HunterDef.Skill)") or nil

RerollTracker.SaveData = nil
RerollTracker.EquipBox = nil

RerollTracker.isMonitoring = false
RerollTracker.currentSession = nil
RerollTracker.weapons = {}

RerollTracker.dataFilePath = "reroll_sessions.json"
RerollTracker.enableAutoSkip = false

RerollTracker.trackingMode = 1
RerollTracker.MODE_GRINDING = 1
RerollTracker.MODE_LOTTERY = 2
RerollTracker.modeNames = {"Artian Grinding (거극 복원 강화)", "Skill Lottery (스킬 재부여)"}

RerollTracker.skillDataInitialized = false
RerollTracker.aSkillTypeToSkillData = {}

RerollTracker.pendingRecords = {}
RerollTracker.trackedWeaponIndex = nil

RerollTracker.elementList = {"화속", "수속", "얼음", "번개", "용속", "폭파", "마비"}
RerollTracker.weaponTypeList = {"대검", "태도", "손검", "쌍검", "해머", "피리", "랜스", "건랜", "슬액", "차액", "충곤", "라보", "헤보", "활"}
RerollTracker.selectedElement = 1
RerollTracker.selectedWeaponType = 1
local TD_GUI080000ArtianStatus = sdk.find_type_definition("app.GUI080000ArtianStatus")
local TD_LoopGaugeChangeRequirePoint = sdk.find_type_definition("app.cGUILoopGaugeChangeRequirePoint")
local TD_NotifyWindow = sdk.find_type_definition("app.cGUISystemModuleNotifyWindowApp")
local TD_NotifyWindowDef = sdk.find_type_definition("app.GUINotifyWindowDef.ID")

local function getEnumTables(typeDef)
    local byName, byValue = {}, {}
    if not typeDef then return byName, byValue end

    local fields = typeDef:get_fields()
    for i, field in ipairs(fields) do
        if field:is_static() then
            local name, value = field:get_name(), field:get_data()
            byName[name] = value
            byValue[value] = name
        end
    end
    return byName, byValue
end

local notifyWindowName2ID, notifyWindowID2Name = getEnumTables(TD_NotifyWindowDef)

function RerollTracker.init_skill_data()
    if RerollTracker.skillDataInitialized then return end

    local success, err = pcall(function()
        local mgr = sdk.get_managed_singleton("app.VariousDataManager")
        if not mgr then
            log.error("[RerollTracker] VariousDataManager not found")
            return
        end

        local skillGroup = mgr._Setting._EquipDatas._ArtianDataSetting._ArtianSkillGroup._Values
        if not skillGroup then
            log.error("[RerollTracker] ArtianSkillGroup not found")
            return
        end

        for i = 0, skillGroup:get_Count() - 1 do
            local data = skillGroup:get_Item(i)
            if data then
                local aSkillType = data:get_ArtianSkillType()
                local seriesId = data:get_SeriesSkillId()
                local groupId = data:get_GroupSkillId()

                RerollTracker.aSkillTypeToSkillData[aSkillType] = {
                    Series = seriesId,
                    Group = groupId
                }
            end
        end

        RerollTracker.skillDataInitialized = true
        log.info(string.format("[RerollTracker] Skill data initialized (%d entries)", table_count(RerollTracker.aSkillTypeToSkillData)))
    end)

    if not success then
        log.error("[RerollTracker] Failed to init skill data: " .. tostring(err))
    end
end

function table_count(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function RerollTracker.decode_bonus_by_creating(bonusValue)
    if bonusValue <= 0 then return 0 end

    local first = bonusValue % 1000
    local second = math.floor(bonusValue / 1000) % 1000
    local third = math.floor(bonusValue / 1000000) % 1000

    local asFirst = math.floor(first / 10) % 10
    local asSecond = math.floor(second / 10) % 10
    local asThird = math.floor(third / 10) % 10

    local aSkillType = asThird * 100 + asSecond * 10 + asFirst

    return aSkillType
end

function RerollTracker.get_skill_name(skillId)
    if not FN_GetSkillName then
        return string.format("Skill_%d", skillId)
    end

    local success, result = pcall(function()
        local guidObj = FN_GetSkillName:call(nil, skillId)
        if not guidObj then
            return string.format("Skill_%d", skillId)
        end

        local localizedText = FN_GetLocalizedMsg:call(nil, guidObj)
        if not localizedText or localizedText == "" then
            return string.format("Skill_%d", skillId)
        end

        return localizedText
    end)

    if success then
        return result
    else
        log.error(string.format("[RerollTracker] get_skill_name error for skill %d: %s", skillId, tostring(result)))
        return string.format("Skill_%d", skillId)
    end
end

function RerollTracker.get_bonus_name(bonusId)
    local success, result = pcall(function()
        local guidObj = FN_GetBonusName:call(nil, bonusId)
        if not guidObj then return "Unknown" end

        local localizedText = FN_GetLocalizedMsg:call(nil, guidObj)
        if localizedText and localizedText ~= "" then
            return localizedText
        end
        return "Unknown"
    end)

    if success then
        return result
    else
        log.error("[RerollTracker] get_bonus_name failed: " .. tostring(result))
        return "Error"
    end
end

function RerollTracker.get_bonus_list_from_equipment(equipItem)
    local success, result = pcall(function()
        if not equipItem then return nil end

        local bonusList = FN_GetBonusIdList:call(nil, equipItem)
        if not bonusList then return nil end

        local ids = {}
        for i = 0, bonusList:get_Count() - 1 do
            ids[i + 1] = bonusList:get_Item(i)
        end
        return ids
    end)

    if success then
        return result
    else
        log.error("[RerollTracker] get_bonus_list_from_equipment failed: " .. tostring(result))
        return nil
    end
end


function RerollTracker.find_target_weapon()
    if not RerollTracker.EquipBox then return nil, nil end

    if RerollTracker.trackedWeaponIndex then
        local equipItem = RerollTracker.EquipBox:get_Item(RerollTracker.trackedWeaponIndex)
        if equipItem then
            return RerollTracker.trackedWeaponIndex, equipItem
        end
    end

    for i = 0, RerollTracker.EquipBox:get_Count() - 1 do
        local equipItem = RerollTracker.EquipBox:get_Item(i)
        if equipItem then
            local category = equipItem:get_Category()
            local bonusByCreating = equipItem.BonusByCreating

            if category == 1 and bonusByCreating > 0 then
                RerollTracker.trackedWeaponIndex = i
                log.info(string.format("[RerollTracker] Found artian weapon at index %d", i))
                return i, equipItem
            end
        end
    end

    log.warn("[RerollTracker] find_target_weapon: No artian weapon found")
    return nil, nil
end

function RerollTracker.queue_record()
    local attemptNum = RerollTracker.dialogSkipCount or 1
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    table.insert(RerollTracker.pendingRecords, {
        attemptNum = attemptNum,
        timestamp = timestamp,
        retryCount = 0,
        delayFrames = 10
    })
    log.info(string.format("[RerollTracker] Queued record #%d (queue size: %d)", attemptNum, #RerollTracker.pendingRecords))
end

function RerollTracker.record_immediate()
    if not RerollTracker.SaveData or not RerollTracker.EquipBox then
        log.warn("[RerollTracker] record_immediate: SaveData not ready")
        return
    end

    local attemptNum = RerollTracker.dialogSkipCount or 1
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")

    local success, err = pcall(function()
        local idx, equipItem = RerollTracker.find_target_weapon()
        if idx and equipItem then
            local recorded = RerollTracker.record_attempt(idx, equipItem, attemptNum, timestamp)
            if recorded then
                log.info(string.format("[RerollTracker] Immediate record #%d SUCCESS", attemptNum))
            else
                log.warn(string.format("[RerollTracker] Immediate record #%d FAILED - queuing", attemptNum))
                table.insert(RerollTracker.pendingRecords, {
                    attemptNum = attemptNum,
                    timestamp = timestamp,
                    retryCount = 0,
                    delayFrames = 5
                })
            end
        else
            log.warn(string.format("[RerollTracker] Immediate record #%d - weapon not found, queuing", attemptNum))
            table.insert(RerollTracker.pendingRecords, {
                attemptNum = attemptNum,
                timestamp = timestamp,
                retryCount = 0,
                delayFrames = 5
            })
        end
    end)

    if not success then
        log.error("[RerollTracker] record_immediate failed: " .. tostring(err))
    end
end

function RerollTracker.process_pending_records()
    if not RerollTracker.SaveData or not RerollTracker.EquipBox then
        return
    end

    if #RerollTracker.pendingRecords == 0 then
        return
    end

    local pending = RerollTracker.pendingRecords[1]

    if pending.delayFrames and pending.delayFrames > 0 then
        pending.delayFrames = pending.delayFrames - 1
        return
    end

    pending.retryCount = pending.retryCount + 1

    local success, err = pcall(function()
        local idx, equipItem = RerollTracker.find_target_weapon()
        if idx and equipItem then
            local recorded = RerollTracker.record_attempt(idx, equipItem, pending.attemptNum, pending.timestamp)
            if recorded then
                log.info(string.format("[RerollTracker] Processed pending #%d (remaining: %d)", pending.attemptNum, #RerollTracker.pendingRecords - 1))
                table.remove(RerollTracker.pendingRecords, 1)
            elseif pending.retryCount > 60 then
                log.warn(string.format("[RerollTracker] Failed to record attempt #%d after 60 retries, skipping", pending.attemptNum))
                table.remove(RerollTracker.pendingRecords, 1)
            end
        elseif pending.retryCount > 60 then
            log.warn(string.format("[RerollTracker] Failed to find weapon for attempt #%d after 60 retries, skipping", pending.attemptNum))
            table.remove(RerollTracker.pendingRecords, 1)
        end
    end)

    if not success then
        log.error("[RerollTracker] process_pending_records failed: " .. tostring(err))
        if pending.retryCount > 60 then
            table.remove(RerollTracker.pendingRecords, 1)
        end
    end
end

function RerollTracker.record_attempt(index, equipItem, attemptNum, timestamp)
    if not RerollTracker.currentSession then
        log.warn(string.format("[RerollTracker] record_attempt #%d FAILED: currentSession is nil", attemptNum))
        return false
    end

    local recorded = false
    local success, err = pcall(function()
        local weaponIndex = index

        local attemptRecord = {
            attemptNum = attemptNum,
            weaponIndex = weaponIndex,
            timestamp = timestamp or os.date("%Y-%m-%d %H:%M:%S")
        }

        if RerollTracker.trackingMode == RerollTracker.MODE_GRINDING then
            local gameUIBonuses = {}

            if RerollTracker.lastGrindingBonusList and #RerollTracker.lastGrindingBonusList > 0 then
                gameUIBonuses = RerollTracker.lastGrindingBonusList
            else
                local bonusIds = RerollTracker.get_bonus_list_from_equipment(equipItem)
                if bonusIds and #bonusIds >= 8 then
                    for i = 4, 8 do
                        local bonusId = bonusIds[i]
                        local bonusName = RerollTracker.get_bonus_name(bonusId)
                        table.insert(gameUIBonuses, bonusName)
                    end
                else
                    for i = 1, 5 do
                        table.insert(gameUIBonuses, "Unknown")
                    end
                    log.warn(string.format("[RerollTracker] Invalid bonus list for attempt #%d, recorded as Unknown", attemptNum))
                end
            end

            attemptRecord.bonuses = gameUIBonuses

            local nickname = RerollTracker.currentSession.nickname or "Unknown"
            log.info(string.format("[RerollTracker] === [%s] GRINDING ATTEMPT #%d ===", nickname, attemptNum))
            log.info(string.format("[RerollTracker] Bonuses: [%s]", table.concat(gameUIBonuses, ", ")))

        elseif RerollTracker.trackingMode == RerollTracker.MODE_LOTTERY then
            if not RerollTracker.skillDataInitialized then
                RerollTracker.init_skill_data()
            end

            local bonusByCreating = equipItem.BonusByCreating
            local aSkillType = RerollTracker.decode_bonus_by_creating(bonusByCreating)
            local skillData = RerollTracker.aSkillTypeToSkillData[aSkillType]

            if skillData then
                local seriesName = RerollTracker.get_skill_name(skillData.Series)
                local groupName = RerollTracker.get_skill_name(skillData.Group)

                attemptRecord.skills = {
                    series = seriesName,
                    group = groupName
                }

                local nickname = RerollTracker.currentSession.nickname or "Unknown"
                log.info(string.format("[RerollTracker] === [%s] LOTTERY ATTEMPT #%d ===", nickname, attemptNum))
                log.info(string.format("[RerollTracker] BonusByCreating: %d → aSkillType: %d", bonusByCreating, aSkillType))
                log.info(string.format("[RerollTracker] Series: %s | Group: %s", seriesName, groupName))
            else
                attemptRecord.skills = {
                    series = string.format("Unknown_%d", aSkillType),
                    group = string.format("Unknown_%d", aSkillType)
                }

                local nickname = RerollTracker.currentSession.nickname or "Unknown"
                log.info(string.format("[RerollTracker] === [%s] LOTTERY ATTEMPT #%d ===", nickname, attemptNum))
                log.info(string.format("[RerollTracker] BonusByCreating: %d → aSkillType: %d (unknown mapping)", bonusByCreating, aSkillType))
            end
        end

        if not RerollTracker.currentSession.weaponIndex then
            RerollTracker.currentSession.weaponIndex = weaponIndex
        end

        table.insert(RerollTracker.currentSession.attempts, attemptRecord)
        RerollTracker.save_session_to_json()
        recorded = true
    end)

    if not success then
        log.error("[RerollTracker] record_attempt failed: " .. tostring(err))
    end

    return recorded
end

local function finish_current_session()
    if not RerollTracker.currentSession then return end

    RerollTracker.currentSession.endTime = os.date("%Y-%m-%d %H:%M:%S")
    RerollTracker.currentSession.totalAttempts = #RerollTracker.currentSession.attempts
    table.insert(RerollTracker.weapons, RerollTracker.currentSession)

    local nickname = RerollTracker.currentSession.nickname or "Unknown"
    local totalAttempts = RerollTracker.currentSession.totalAttempts

    RerollTracker.currentSession = nil
    RerollTracker.save_session_to_json()

    return nickname, totalAttempts
end

function RerollTracker.start_monitoring()
    if RerollTracker.isMonitoring and RerollTracker.currentSession then
        local nickname, attempts = finish_current_session()
        log.info(string.format("[RerollTracker] Previous session saved: %s (%d attempts)", nickname, attempts))
    end

    if not RerollTracker.SaveData or not RerollTracker.EquipBox then
        log.error("[RerollTracker] SaveData not initialized")
        return
    end

    local element = RerollTracker.elementList[RerollTracker.selectedElement]
    local weaponType = RerollTracker.weaponTypeList[RerollTracker.selectedWeaponType]

    if not element or not weaponType then
        log.error("[RerollTracker] Invalid element or weapon type selection")
        return
    end

    RerollTracker.isMonitoring = true
    RerollTracker.dialogSkipCount = 0
    RerollTracker.pendingRecords = {}
    RerollTracker.trackedWeaponIndex = nil

    local modeLabel = RerollTracker.trackingMode == RerollTracker.MODE_GRINDING and "grinding" or "lottery"
    local nickname = element .. " " .. weaponType

    RerollTracker.currentSession = {
        nickname = nickname,
        element = element,
        weaponType = weaponType,
        mode = modeLabel,
        startTime = os.date("%Y-%m-%d %H:%M:%S"),
        attempts = {}
    }

    log.info(string.format("[RerollTracker] Monitoring started for %s [Mode: %s]", nickname, modeLabel))
end

function RerollTracker.stop_monitoring()
    if not RerollTracker.isMonitoring then
        log.info("[RerollTracker] Not monitoring")
        return
    end

    while #RerollTracker.pendingRecords > 0 do
        local pending = RerollTracker.pendingRecords[1]
        pending.retryCount = (pending.retryCount or 0) + 1

        local idx, equipItem = RerollTracker.find_target_weapon()
        if idx and equipItem then
            local recorded = RerollTracker.record_attempt(idx, equipItem, pending.attemptNum, pending.timestamp)
            if recorded then
                table.remove(RerollTracker.pendingRecords, 1)
            elseif pending.retryCount > 10 then
                log.warn(string.format("[RerollTracker] Failed to record attempt #%d on stop, skipping", pending.attemptNum))
                table.remove(RerollTracker.pendingRecords, 1)
            else
                break
            end
        else
            log.warn(string.format("[RerollTracker] Target weapon not found for attempt #%d on stop", pending.attemptNum))
            table.remove(RerollTracker.pendingRecords, 1)
        end
    end

    RerollTracker.isMonitoring = false
    RerollTracker.pendingRecords = {}

    local nickname, attempts = finish_current_session()
    if nickname then
        log.info(string.format("[RerollTracker] Monitoring stopped [%s]. Total attempts: %d", nickname, attempts))
    end
end

function RerollTracker.save_session_to_json()
    local success, err = pcall(function()
        local data = {
            lastUpdated = os.date("%Y-%m-%d %H:%M:%S"),
            totalWeapons = #RerollTracker.weapons,
            weapons = RerollTracker.weapons
        }

        json.dump_file(RerollTracker.dataFilePath, data)
    end)

    if not success then
        log.error("[RerollTracker] Failed to save JSON: " .. tostring(err))
    end
end

function RerollTracker.load_session_from_json()
    local success, data = pcall(function()
        return json.load_file(RerollTracker.dataFilePath)
    end)

    if success and data then
        RerollTracker.weapons = data.weapons or {}
        log.info(string.format("[RerollTracker] Loaded %d weapons from JSON", #RerollTracker.weapons))
    end
end

function RerollTracker.clear_history()
    RerollTracker.weapons = {}
    RerollTracker.currentSession = nil
    RerollTracker.save_session_to_json()
    log.info("[RerollTracker] History cleared")
end

function RerollTracker.show_session_summary()
    if not RerollTracker.currentSession then
        log.info("[RerollTracker] No active session")
        return
    end

    log.info("[RerollTracker] === SESSION SUMMARY ===")
    log.info(string.format("[RerollTracker] Weapon Nickname: %s", RerollTracker.currentSession.nickname or "N/A"))
    log.info(string.format("[RerollTracker] Mode: %s", RerollTracker.currentSession.mode or "N/A"))
    log.info(string.format("[RerollTracker] Start time: %s", RerollTracker.currentSession.startTime))
    log.info(string.format("[RerollTracker] Weapon Index: %s", tostring(RerollTracker.currentSession.weaponIndex or "N/A")))
    log.info(string.format("[RerollTracker] Total attempts: %d", #RerollTracker.currentSession.attempts))
end

local function create_animation_skip_hook(method, actionArgIndex, hookName)
    if not method then return end

    sdk.hook(method, function(args)
        if not RerollTracker.enableAutoSkip then
            return sdk.PreHookResult.CALL_ORIGINAL
        end

        local success, err = pcall(function()
            local action = sdk.to_managed_object(args[actionArgIndex])
            if action then
                action:Invoke()
            end
        end)

        if not success then
            log.error(string.format("[RerollTracker] %s hook failed: %s", hookName, tostring(err)))
            return sdk.PreHookResult.CALL_ORIGINAL
        end

        return sdk.PreHookResult.SKIP_ORIGINAL
    end, nil)

    log.info(string.format("[RerollTracker] %s hook installed", hookName))
end

RerollTracker.lastGrindingBonusList = nil

local function create_grinding_anim_hook()
    local method = TD_GUI080000ArtianStatus:get_method("startArtianGrindingAnim(System.Action)")
    if not method then return end

    sdk.hook(method, function(args)
        if not RerollTracker.enableAutoSkip then
            return sdk.PreHookResult.CALL_ORIGINAL
        end

        local success, err = pcall(function()
            local this = sdk.to_managed_object(args[2])
            local action = sdk.to_managed_object(args[3])

            if action then
                action:Invoke()
            end

            if RerollTracker.isMonitoring and RerollTracker.trackingMode == RerollTracker.MODE_GRINDING then
                RerollTracker.dialogSkipCount = (RerollTracker.dialogSkipCount or 0) + 1
                local attemptNum = RerollTracker.dialogSkipCount

                if not this then
                    log.warn(string.format("[RerollTracker] #%d: this is nil", attemptNum))
                else
                    local grindingList = this:get_field("_ArtianGrindingList")
                    if not grindingList then
                        log.warn(string.format("[RerollTracker] #%d: _ArtianGrindingList is nil", attemptNum))
                    else
                        local itemCount = grindingList:call("get_ItemCount")
                        if itemCount and itemCount > 0 then
                            local bonusNames = {}
                            for i = 0, itemCount - 1 do
                                local item = grindingList:call("getItemByGlobalIndex", i)
                                if item then
                                    local td = item:get_type_definition()
                                    if attemptNum == 1 then
                                        log.info(string.format("[RerollTracker] Item[%d] type: %s", i, td and td:get_full_name() or "nil"))
                                    end
                                    local bonusId = item:get_field("_BonusId_k__BackingField")
                                    if not bonusId then
                                        bonusId = item:call("get_BonusId")
                                    end
                                    if bonusId then
                                        local bonusName = RerollTracker.get_bonus_name(bonusId)
                                        table.insert(bonusNames, bonusName)
                                    end
                                end
                            end
                            if #bonusNames > 0 then
                                RerollTracker.lastGrindingBonusList = bonusNames
                                log.info(string.format("[RerollTracker] [GRINDING] #%d captured: [%s]", attemptNum, table.concat(bonusNames, ", ")))
                            else
                                log.warn(string.format("[RerollTracker] #%d: ItemCount=%d but no bonuses read", attemptNum, itemCount))
                            end
                        else
                            log.warn(string.format("[RerollTracker] #%d: ItemCount=%s", attemptNum, tostring(itemCount)))
                        end
                    end
                end
            end
        end)

        if not success then
            log.error(string.format("[RerollTracker] startArtianGrindingAnim hook failed: %s", tostring(err)))
            return sdk.PreHookResult.CALL_ORIGINAL
        end

        return sdk.PreHookResult.SKIP_ORIGINAL
    end, nil)

    log.info("[RerollTracker] startArtianGrindingAnim hook installed (with recording)")
end

local function create_lottery_anim_hook()
    local method = TD_GUI080000ArtianStatus:get_method("startSkillLotteryAnim(System.Action)")
    if not method then return end

    sdk.hook(method, function(args)
        if not RerollTracker.enableAutoSkip then
            return sdk.PreHookResult.CALL_ORIGINAL
        end

        local success, err = pcall(function()
            local action = sdk.to_managed_object(args[3])
            if action then
                action:Invoke()
            end

        end)

        if not success then
            log.error(string.format("[RerollTracker] startSkillLotteryAnim hook failed: %s", tostring(err)))
            return sdk.PreHookResult.CALL_ORIGINAL
        end

        return sdk.PreHookResult.SKIP_ORIGINAL
    end, nil)

    log.info("[RerollTracker] startSkillLotteryAnim hook installed (with recording)")
end

if TD_GUI080000ArtianStatus then
    create_grinding_anim_hook()
    create_lottery_anim_hook()
end

if TD_LoopGaugeChangeRequirePoint then
    create_animation_skip_hook(
        TD_LoopGaugeChangeRequirePoint:get_method("startUpGrade(System.UInt32, System.Action)"),
        4,
        "startUpGrade"
    )
end

if TD_NotifyWindow then
    local requestNotifyWindowMethod = TD_NotifyWindow:get_method("requestNotifyWindow")

    if requestNotifyWindowMethod then
        sdk.hook(requestNotifyWindowMethod, function(args)
            if not RerollTracker.enableAutoSkip then
                return
            end

            local success, result = pcall(function()
                local notifyWindowInfo = sdk.to_managed_object(args[3])
                if not notifyWindowInfo then return end

                local textInfo = notifyWindowInfo:get_TextInfo()
                if not textInfo then return end

                local windowId = notifyWindowInfo:get_NotifyWindowId()
                if not windowId then return end

                local windowIdName = notifyWindowID2Name[windowId]
                if not windowIdName then return end

                local targetDialogs = {
                    ["EQUIP_000"] = 0,
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

                    if RerollTracker.isMonitoring then
                        if windowIdName == "GUI080301_0009_DLG" and RerollTracker.trackingMode == RerollTracker.MODE_GRINDING then
                            RerollTracker.dialogSkipCount = (RerollTracker.dialogSkipCount or 0) + 1
                            log.info(string.format("[RerollTracker] [GRINDING] Dialog #%d confirmed, recording after executeWindowEndFunc", RerollTracker.dialogSkipCount))
                            RerollTracker.record_immediate()
                        elseif windowIdName == "GUI080301_0010_DLG" and RerollTracker.trackingMode == RerollTracker.MODE_LOTTERY then
                            RerollTracker.dialogSkipCount = (RerollTracker.dialogSkipCount or 0) + 1
                            log.info(string.format("[RerollTracker] [LOTTERY] Dialog #%d confirmed, recording after executeWindowEndFunc", RerollTracker.dialogSkipCount))
                            RerollTracker.record_immediate()
                        end
                    end

                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end)

            if not success then
                log.error("[RerollTracker] Dialog skip hook error: " .. tostring(result))
            end

            return result
        end, nil)
        log.info("[RerollTracker] Dialog skip hook installed successfully")
    end
end



sdk.hook(TD_SaveDataManager:get_method("update()"), function(args)
    if RerollTracker.SaveData ~= nil then return end

    local success, err = pcall(function()
        local mgr = sdk.to_managed_object(args[2])
        if mgr then
            RerollTracker.SaveData = FN_GetCurrentUserSaveData:call(mgr)
            if RerollTracker.SaveData then
                RerollTracker.EquipBox = RerollTracker.SaveData._Equip._EquipBox
                log.info("[RerollTracker] SaveData initialized")

                RerollTracker.load_session_from_json()
            end
        end
    end)

    if not success then
        log.error("[RerollTracker] Hook error: " .. tostring(err))
    end
end)

re.on_frame(function()
    if RerollTracker.isMonitoring and #RerollTracker.pendingRecords > 0 then
        RerollTracker.process_pending_records()
    end
end)

re.on_draw_ui(function()
    if imgui.tree_node("Artian Reroll Tracker") then
        imgui.text("Gogmazios Artian Weapon Refinement Tracker")
        imgui.spacing()

        if not RerollTracker.SaveData then
            imgui.text_colored("SaveData not loaded yet", 0xFFFF0000)
        else
            imgui.text("Tracking Mode:")
            imgui.same_line()
            if imgui.button(RerollTracker.modeNames[RerollTracker.trackingMode]) then
                RerollTracker.trackingMode = RerollTracker.trackingMode == RerollTracker.MODE_GRINDING and RerollTracker.MODE_LOTTERY or RerollTracker.MODE_GRINDING
                log.info(string.format("[RerollTracker] Mode changed to: %s", RerollTracker.modeNames[RerollTracker.trackingMode]))

                if RerollTracker.isMonitoring and RerollTracker.currentSession then
                    RerollTracker.start_monitoring()
                end
            end
            imgui.spacing()
            imgui.separator()
            imgui.spacing()

            imgui.text("Element:")
            imgui.same_line()
            local elementChanged, newElement = imgui.combo("##Element", RerollTracker.selectedElement, RerollTracker.elementList)
            if elementChanged then
                if newElement >= 1 and newElement <= #RerollTracker.elementList then
                    RerollTracker.selectedElement = newElement
                    log.info(string.format("[RerollTracker] Element changed: index=%d, value=%s", newElement, RerollTracker.elementList[newElement]))
                    if RerollTracker.isMonitoring and RerollTracker.currentSession then
                        RerollTracker.start_monitoring()
                    end
                else
                    log.error(string.format("[RerollTracker] Invalid element index: %d (valid: 1-%d)", newElement, #RerollTracker.elementList))
                end
            end

            imgui.text("Weapon Type:")
            imgui.same_line()
            local weaponChanged, newWeapon = imgui.combo("##WeaponType", RerollTracker.selectedWeaponType, RerollTracker.weaponTypeList)
            if weaponChanged then
                if newWeapon >= 1 and newWeapon <= #RerollTracker.weaponTypeList then
                    RerollTracker.selectedWeaponType = newWeapon
                    log.info(string.format("[RerollTracker] Weapon changed: index=%d, value=%s", newWeapon, RerollTracker.weaponTypeList[newWeapon]))
                    if RerollTracker.isMonitoring and RerollTracker.currentSession then
                        RerollTracker.start_monitoring()
                    end
                else
                    log.error(string.format("[RerollTracker] Invalid weapon index: %d (valid: 1-%d)", newWeapon, #RerollTracker.weaponTypeList))
                end
            end

            imgui.spacing()

            local changed, newValue = imgui.checkbox("Enable Reroll Tracker", RerollTracker.isMonitoring)
            if changed then
                if newValue then
                    RerollTracker.start_monitoring()
                    if RerollTracker.isMonitoring then
                        RerollTracker.enableAutoSkip = true
                        log.info("[RerollTracker] Reroll Tracker ENABLED (monitoring + auto skip)")
                    end
                else
                    RerollTracker.stop_monitoring()
                    RerollTracker.enableAutoSkip = false
                    log.info("[RerollTracker] Reroll Tracker DISABLED")
                end
            end

            imgui.spacing()

            if RerollTracker.isMonitoring then
                imgui.text_colored("Status: ACTIVE", 0xFF00FF00)

                if RerollTracker.currentSession then
                    imgui.same_line()
                    local modeLabel = RerollTracker.currentSession.mode or "?"
                    imgui.text(string.format("| [%s] %s | Attempts: %d",
                        RerollTracker.currentSession.nickname or "Unknown",
                        modeLabel:upper(),
                        #RerollTracker.currentSession.attempts))
                end
            else
                imgui.text_colored("Status: INACTIVE", 0xFF888888)
            end

            imgui.spacing()
            imgui.separator()

            if imgui.button("Show Session Summary (Log)") then
                RerollTracker.show_session_summary()
            end

            if imgui.button("Clear History") then
                RerollTracker.clear_history()
            end

            imgui.spacing()
            imgui.separator()
            imgui.text(string.format("JSON: reframework/data/%s", RerollTracker.dataFilePath))
            imgui.text(string.format("Total weapons recorded: %d", #RerollTracker.weapons))
        end

        imgui.tree_pop()
    end
end)

log.info("[RerollTracker] Loaded successfully")
