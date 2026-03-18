-- ============================================================================
-- [1] Constants & Type Definitions
-- ============================================================================

local TAG = "[RerollTracker]"

local MODE_GRINDING = 1
local MODE_LOTTERY = 2

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
local TD_MessageUtil = sdk.find_type_definition("app.MessageUtil")

local TD_BonusId = sdk.find_type_definition("app.ArtianDef.BONUS_ID")
local TD_BonusIdFixed = sdk.find_type_definition("app.ArtianDef.BONUS_ID_Fixed")
local FN_GetBonusName = TD_ArtianUtil and TD_ArtianUtil:get_method("Name(app.ArtianDef.BONUS_ID)")
local FN_GetLocalizedMsg = TD_GuiMessage and TD_GuiMessage:get_method("get(System.Guid)")
local FN_LotterySkill = TD_Em0078ArtianUtil and TD_Em0078ArtianUtil:get_method("lotterySkill(app.savedata.cEquipWork)")
local FN_LotteryCreateBonus = TD_Em0078ArtianUtil and TD_Em0078ArtianUtil:get_method("lotteryCreateBonus(app.user_data.WeaponData.cData, app.savedata.cEquipWork, System.Boolean)")
local FN_GetWeaponTypeName = TD_WeaponUtil and TD_WeaponUtil:get_method("getWeaponTypeName(app.WeaponDef.TYPE)")
local FN_GetSkillName = TD_MessageUtil and TD_MessageUtil:get_method("getHunterSkillName(app.HunterDef.Skill)")

-- ============================================================================
-- [2] Enum Tables & Conversion Maps
-- ============================================================================

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
local fixedToBonusIdMap = {}

do
    local weaponByName = getEnumTables(TD_WeaponDefType)
    local fixedByName = getEnumTables(TD_WeaponDefTypeFixed)
    for name, fixedValue in pairs(fixedByName) do
        if name ~= "INVALID" and name ~= "MAX" and weaponByName[name] ~= nil then
            fixedToTypeMap[fixedValue] = weaponByName[name]
        end
    end

    local bonusByName = getEnumTables(TD_BonusId)
    local bonusFixedByName = getEnumTables(TD_BonusIdFixed)
    for name, fixedValue in pairs(bonusFixedByName) do
        if name ~= "INVALID" and name ~= "MAX" and bonusByName[name] ~= nil then
            fixedToBonusIdMap[fixedValue] = bonusByName[name]
        end
    end
end

local CATEGORY_KEYWORDS = nil
local CATEGORY_BONUS_IDS = {}

local CATEGORY_PATTERNS = {
    ATTACK = "ATTACK",
    AFFINITY = "CRITICAL",
    SHARPNESS = "SHARP",
    ELEMENT = "ELEMENT",
}

do
    local bonusByName = getEnumTables(TD_BonusId)
    for category, pattern in pairs(CATEGORY_PATTERNS) do
        for name, value in pairs(bonusByName) do
            if name:find(pattern) and not CATEGORY_BONUS_IDS[category] then
                CATEGORY_BONUS_IDS[category] = value
            end
        end
    end
end

local function resolve_category_keywords()
    if CATEGORY_KEYWORDS then return true end
    local keywords = {}
    local resolved = 0
    for category, bonusId in pairs(CATEGORY_BONUS_IDS) do
        local fullName = get_bonus_name(bonusId)
        if fullName and fullName ~= "" and not fullName:find("Bonus_") then
            local baseName = fullName:gsub("[ⅠⅡⅢ]+$", ""):gsub("EX$", ""):gsub("%s+$", "")
            keywords[category] = baseName
            resolved = resolved + 1
        end
    end
    local expected = 0
    for _ in pairs(CATEGORY_BONUS_IDS) do expected = expected + 1 end
    if resolved == expected and resolved > 0 then
        CATEGORY_KEYWORDS = keywords
        return true
    end
    return false
end

local function classify_bonuses(bonusNames)
    if not resolve_category_keywords() then return nil end
    local counts = { EX = 0, ATTACK = 0, AFFINITY = 0, SHARPNESS = 0, ELEMENT = 0 }
    for _, name in ipairs(bonusNames) do
        if name:find("EX") then
            counts.EX = counts.EX + 1
        end
        for category, keyword in pairs(CATEGORY_KEYWORDS) do
            if name:find(keyword, 1, true) then
                counts[category] = counts[category] + 1
                break
            end
        end
    end
    return counts
end

-- ============================================================================
-- [3] Utility Functions
-- ============================================================================

local function get_bonus_name(bonusId)
    if not FN_GetBonusName or not FN_GetLocalizedMsg then
        return string.format("Bonus_%d", bonusId)
    end
    local success, result = pcall(function()
        local guidObj = FN_GetBonusName:call(nil, bonusId)
        if not guidObj then return nil end
        local text = FN_GetLocalizedMsg:call(nil, guidObj)
        if text and text ~= "" then return text end
        return nil
    end)
    if success and result then return result end
    return string.format("Bonus_%d", bonusId)
end

local function get_weapon_type_name(weaponType)
    if not FN_GetWeaponTypeName or not FN_GetLocalizedMsg then
        return string.format("Type_%d", weaponType)
    end
    local success, result = pcall(function()
        local guidObj = FN_GetWeaponTypeName:call(nil, weaponType)
        if not guidObj then return nil end
        local text = FN_GetLocalizedMsg:call(nil, guidObj)
        if text and text ~= "" then return text end
        return nil
    end)
    if success and result then return result end
    return string.format("Type_%d", weaponType)
end

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
        return nil
    end)
    if success and result then return result end
    return string.format("Skill_%d", skillId)
end

local ArtianSkillData = nil
local ArtianSkillDataInited = false

local function init_artian_skill_data()
    if ArtianSkillDataInited then return end
    local success = pcall(function()
        local mgr = sdk.get_managed_singleton("app.VariousDataManager")
        if not mgr then return end
        local skillGroup = mgr._Setting._EquipDatas._ArtianDataSetting._ArtianSkillGroup._Values
        if not skillGroup then return end
        ArtianSkillData = {}
        local count = skillGroup:call("get_Count")
        for i = 0, count - 1 do
            local data = skillGroup:call("get_Item", i)
            if data then
                ArtianSkillData[data:call("get_ArtianSkillType")] = {
                    seriesId = data:call("get_SeriesSkillId"),
                    groupId = data:call("get_GroupSkillId")
                }
            end
        end
        ArtianSkillDataInited = true
    end)
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

local function decode_grinding_bonuses(bonusByGrinding)
    if not bonusByGrinding or bonusByGrinding <= 0 then return {} end
    local bonusIds = {}
    local remaining = bonusByGrinding
    for _ = 1, 5 do
        local rawId = remaining % 1000
        if rawId > 0 then
            local bonusId = fixedToBonusIdMap[rawId] or rawId
            table.insert(bonusIds, bonusId)
        end
        remaining = math.floor(remaining / 1000)
    end
    return bonusIds
end

local function get_skill_names_from_artian_type(aSkillType)
    init_artian_skill_data()
    if not ArtianSkillData or not ArtianSkillData[aSkillType] then
        return string.format("ArtianSkill_%d", aSkillType), ""
    end
    local data = ArtianSkillData[aSkillType]
    return get_skill_name(data.seriesId), get_skill_name(data.groupId)
end

-- ============================================================================
-- [4] State & Session Management
-- ============================================================================

local RerollTracker = {
    enabled = false,
    currentSession = nil,
    weapons = {},
    attemptCount = 0,
    dataFilePath = "reroll_sessions.json",
    trackingMode = MODE_GRINDING,
    _lastCapturedWeaponType = nil,
    _lastCapturedAttribute = nil,
    _lotterySkillEquipWork = nil,
    _grindingEquipWork = nil,
}

local function create_session_template(modeName)
    return {
        nickname = "Unknown",
        weaponType = -1,
        weaponTypeName = "Unknown",
        attribute = "",
        mode = modeName,
        startTime = os.date("%Y-%m-%d %H:%M:%S"),
        attempts = {}
    }
end

local function apply_weapon_info(session, weaponType, attribute)
    if not weaponType then return end
    local typeName = get_weapon_type_name(weaponType)
    session.weaponType = weaponType
    session.weaponTypeName = typeName
    session.attribute = attribute
    session.nickname = (attribute ~= "" and attribute .. " " or "") .. typeName
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
    if not RerollTracker.currentSession then return end
    if #RerollTracker.currentSession.attempts == 0 then
        RerollTracker.currentSession = nil
        RerollTracker.attemptCount = 0
        return
    end
    RerollTracker.currentSession.endTime = os.date("%Y-%m-%d %H:%M:%S")
    RerollTracker.currentSession.totalAttempts = #RerollTracker.currentSession.attempts
    save_current_session_to_weapons()
    RerollTracker.currentSession = nil
    RerollTracker.attemptCount = 0
end

local function start_new_session()
    if RerollTracker.currentSession then
        finish_current_session()
    end
    local modeName = RerollTracker.trackingMode == MODE_GRINDING and "grinding" or "lottery"
    RerollTracker.currentSession = create_session_template(modeName)
    RerollTracker.attemptCount = 0
end

local function reset_all_captured()
    RerollTracker._lastCapturedWeaponType = nil
    RerollTracker._lastCapturedAttribute = nil
    RerollTracker._lotterySkillEquipWork = nil
    RerollTracker._grindingEquipWork = nil
end

local function ensure_session_mode(targetMode)
    if not RerollTracker.currentSession then
        RerollTracker.trackingMode = targetMode
        start_new_session()
    elseif RerollTracker.currentSession.mode ~= (targetMode == MODE_GRINDING and "grinding" or "lottery") then
        finish_current_session()
        RerollTracker.trackingMode = targetMode
        start_new_session()
    end
end

local function check_and_update_session_weapon(capturedType, capturedAttribute)
    if not RerollTracker.currentSession then return end
    local session = RerollTracker.currentSession

    if session.weaponType == -1 then
        apply_weapon_info(session, capturedType, capturedAttribute)
        return
    end

    local typeChanged = capturedType and capturedType ~= session.weaponType
    local attrChanged = capturedAttribute ~= "" and session.attribute ~= "" and capturedAttribute ~= session.attribute
    if not typeChanged and not attrChanged then return end

    save_current_session_to_weapons()
    local existingIndex = find_existing_session(capturedType, capturedAttribute)
    if existingIndex then
        RerollTracker.currentSession = RerollTracker.weapons[existingIndex]
        RerollTracker.attemptCount = #RerollTracker.currentSession.attempts
        table.remove(RerollTracker.weapons, existingIndex)
    else
        local modeName = RerollTracker.trackingMode == MODE_GRINDING and "grinding" or "lottery"
        RerollTracker.currentSession = create_session_template(modeName)
        RerollTracker.attemptCount = 0
    end
    apply_weapon_info(RerollTracker.currentSession, capturedType, capturedAttribute)
    RerollTracker.save_to_json()
end

local function record_attempt(bonusIds)
    if not RerollTracker.enabled or not RerollTracker.currentSession then return end
    if #bonusIds == 0 then return end
    check_and_update_session_weapon(
        RerollTracker._lastCapturedWeaponType,
        RerollTracker._lastCapturedAttribute or ""
    )
    RerollTracker.attemptCount = RerollTracker.attemptCount + 1
    local bonusNames = {}
    for _, id in ipairs(bonusIds) do
        table.insert(bonusNames, get_bonus_name(id))
    end
    table.insert(RerollTracker.currentSession.attempts, {
        attemptNum = RerollTracker.attemptCount,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        bonuses = bonusNames
    })
    RerollTracker.save_to_json()
end

local function record_skill_attempt(seriesSkill, groupSkill)
    if not RerollTracker.enabled or not RerollTracker.currentSession then return end
    if not seriesSkill or seriesSkill == "" then return end
    check_and_update_session_weapon(
        RerollTracker._lastCapturedWeaponType,
        RerollTracker._lastCapturedAttribute or ""
    )
    RerollTracker.attemptCount = RerollTracker.attemptCount + 1
    table.insert(RerollTracker.currentSession.attempts, {
        attemptNum = RerollTracker.attemptCount,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        skills = {
            series = seriesSkill,
            group = groupSkill or ""
        }
    })
    RerollTracker.save_to_json()
end

-- ============================================================================
-- [5] Persistence
-- ============================================================================

function RerollTracker.save_to_json()
    pcall(function()
        local weaponsToSave = {}
        for _, weapon in ipairs(RerollTracker.weapons) do
            local copy = {}
            for k, v in pairs(weapon) do copy[k] = v end
            table.insert(weaponsToSave, copy)
        end
        if RerollTracker.currentSession and #RerollTracker.currentSession.attempts > 0 then
            local copy = {}
            for k, v in pairs(RerollTracker.currentSession) do copy[k] = v end
            copy.isCurrent = true
            table.insert(weaponsToSave, copy)
        end
        json.dump_file(RerollTracker.dataFilePath, {
            lastUpdated = os.date("%Y-%m-%d %H:%M:%S"),
            totalWeapons = #weaponsToSave,
            weapons = weaponsToSave
        })
    end)
end

local function load_from_json()
    local success, data = pcall(function()
        return json.load_file(RerollTracker.dataFilePath)
    end)
    if not success or not data then return end
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

local function clear_history()
    RerollTracker.weapons = {}
    RerollTracker.currentSession = nil
    RerollTracker.attemptCount = 0
    reset_all_captured()
    RerollTracker.save_to_json()
    if RerollTracker.enabled then
        start_new_session()
    end
end

-- ============================================================================
-- [6] Hook Handlers
-- ============================================================================

local function on_lottery_skill_pre(args)
    if not RerollTracker.enabled then return end
    RerollTracker._lotterySkillEquipWork = args[2]
end

local function on_lottery_skill_post(retval)
    if not RerollTracker.enabled then return retval end
    local ok, err = pcall(function()
        local equipWork = sdk.to_managed_object(RerollTracker._lotterySkillEquipWork)
        if not equipWork then return end
        local bonusByCreating = equipWork:get_field("BonusByCreating")
        if not bonusByCreating or bonusByCreating <= 0 then return end
        local aSkillType = decode_artian_skill_type(bonusByCreating)
        if not aSkillType or aSkillType <= 0 then return end
        ensure_session_mode(MODE_LOTTERY)
        local seriesSkill, groupSkill = get_skill_names_from_artian_type(aSkillType)
        record_skill_attempt(seriesSkill, groupSkill)
    end)
    if not ok then log.error(TAG .. " lotterySkill error: " .. tostring(err)) end
    RerollTracker._lotterySkillEquipWork = nil
    return retval
end

local function on_lottery_create_bonus_pre(args)
    if not RerollTracker.enabled then return end
    RerollTracker._grindingEquipWork = args[3]
end

local function on_lottery_create_bonus_post(retval)
    if not RerollTracker.enabled then return retval end
    local ok, err = pcall(function()
        local equipWork = sdk.to_managed_object(RerollTracker._grindingEquipWork)
        if not equipWork then return end
        local bonusByGrinding = equipWork:get_field("BonusByGrinding")
        local bonusIds = decode_grinding_bonuses(bonusByGrinding)
        if #bonusIds == 0 then return end
        ensure_session_mode(MODE_GRINDING)
        record_attempt(bonusIds)
    end)
    if not ok then log.error(TAG .. " lotteryCreateBonus error: " .. tostring(err)) end
    RerollTracker._grindingEquipWork = nil
    return retval
end

local function on_set_weapon_data_core_pre(args)
    if not RerollTracker.enabled then return end
    local ok, err = pcall(function()
        local equipSet = sdk.to_managed_object(args[3])
        if not equipSet then return end
        local weaponData = equipSet:get_field("<WeaponData>k__BackingField")
        if not weaponData then return end
        local rawType = weaponData:get_field("_Type")
        local weaponType = rawType
        if rawType and fixedToTypeMap[rawType] ~= nil then
            weaponType = fixedToTypeMap[rawType]
        end
        if weaponType and weaponType >= 0 and weaponType <= 13 then
            RerollTracker._lastCapturedWeaponType = weaponType
        end
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
    end)
    if not ok then log.error(TAG .. " setWeaponDataCore error: " .. tostring(err)) end
end

local function on_grinding_anim_pre(args)
    if not RerollTracker.enabled then
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    local ok, err = pcall(function()
        local action = sdk.to_managed_object(args[3])
        if action then action:Invoke() end
    end)
    if not ok then
        log.error(TAG .. " grinding error: " .. tostring(err))
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    return sdk.PreHookResult.SKIP_ORIGINAL
end

local function on_lottery_anim_pre(args)
    if not RerollTracker.enabled then
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    local ok, err = pcall(function()
        local action = sdk.to_managed_object(args[3])
        if action then action:Invoke() end
    end)
    if not ok then
        log.error(TAG .. " lottery error: " .. tostring(err))
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    return sdk.PreHookResult.SKIP_ORIGINAL
end

local function on_start_upgrade_pre(args)
    if not RerollTracker.enabled then
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    local ok, err = pcall(function()
        local action = sdk.to_managed_object(args[4])
        if action then action:Invoke() end
    end)
    if not ok then
        log.error(TAG .. " startUpGrade error: " .. tostring(err))
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    return sdk.PreHookResult.SKIP_ORIGINAL
end

local TARGET_DIALOGS = {
    ["EQUIP_000"] = 0,
    ["EQUIPMENT_0008_15"] = 0,
    ["GUI080301_0005_DLG"] = 0,
    ["GUI080301_0009_DLG"] = 1,
    ["GUI080301_0010_DLG"] = 1,
}

local function on_notify_window_pre(args)
    local ok, result = pcall(function()
        local notifyWindowInfo = sdk.to_managed_object(args[3])
        if not notifyWindowInfo then return nil end
        local textInfo = notifyWindowInfo:get_TextInfo()
        if not textInfo then return nil end
        local windowId = notifyWindowInfo:get_NotifyWindowId()
        if not windowId then return nil end
        local windowIdName = notifyWindowID2Name[windowId]
        if not windowIdName then return nil end
        if not RerollTracker.enabled then return nil end
        local selectedIndex = TARGET_DIALOGS[windowIdName]
        if selectedIndex == nil then return nil end
        notifyWindowInfo:set_SelectedIndex(selectedIndex)
        local updateAction = notifyWindowInfo:get_UpdateAction()
        if updateAction and updateAction:get_HasEvent() then
            updateAction:execute()
        end
        notifyWindowInfo:executeWindowEndFunc()
        return sdk.PreHookResult.SKIP_ORIGINAL
    end)
    if not ok then
        log.error(TAG .. " notifyWindow error: " .. tostring(result))
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    if result then return result end
    return sdk.PreHookResult.CALL_ORIGINAL
end

-- ============================================================================
-- [7] Hook Registration
-- ============================================================================

local function register_hooks()
    local function try_hook(label, typeDef, methodName, preFn, postFn)
        if not typeDef then
            log.error(TAG .. " HOOK FAIL [" .. label .. "] typeDef is nil")
            return
        end
        local method = typeDef:get_method(methodName)
        if not method then
            log.error(TAG .. " HOOK FAIL [" .. label .. "] method not found: " .. methodName)
            return
        end
        sdk.hook(method, preFn, postFn)
    end

    if FN_LotterySkill then
        sdk.hook(FN_LotterySkill, on_lottery_skill_pre, on_lottery_skill_post)
    else
        log.error(TAG .. " HOOK FAIL [lotterySkill] FN_LotterySkill is nil")
    end

    if FN_LotteryCreateBonus then
        sdk.hook(FN_LotteryCreateBonus, on_lottery_create_bonus_pre, on_lottery_create_bonus_post)
    else
        log.error(TAG .. " HOOK FAIL [lotteryCreateBonus] FN_LotteryCreateBonus is nil")
    end

    try_hook("setWeaponDataCore", TD_GUI080000ArtianStatus, "setWeaponDataCore(app.EquipDef.EquipSet)", on_set_weapon_data_core_pre, nil)
    try_hook("grindingAnim", TD_GUI080000ArtianStatus, "startArtianGrindingAnim(System.Action)", on_grinding_anim_pre, nil)
    try_hook("lotteryAnim", TD_GUI080000ArtianStatus, "startSkillLotteryAnim(System.Action)", on_lottery_anim_pre, nil)
    try_hook("startUpGrade", TD_LoopGaugeChangeRequirePoint, "startUpGrade(System.UInt32, System.Action)", on_start_upgrade_pre, nil)
    try_hook("notifyWindow", TD_NotifyWindow, "requestNotifyWindow", on_notify_window_pre, nil)
end

-- ============================================================================
-- [8] Initialization & UI
-- ============================================================================

load_from_json()
register_hooks()

re.on_draw_ui(function()
    if imgui.tree_node("Artian Reroll Tracker") then
        local changed, newValue = imgui.checkbox("Enable Tracker", RerollTracker.enabled)
        if changed then
            RerollTracker.enabled = newValue
            if newValue and not RerollTracker.currentSession then
                start_new_session()
            elseif not newValue then
                reset_all_captured()
            end
        end

        imgui.spacing()

        if RerollTracker.enabled then
            imgui.text_colored("Status: ACTIVE", 0xFF00FF00)
            local s = RerollTracker.currentSession
            if s and s.nickname and s.attempts then
                local modeText = s.mode == "grinding" and "Grinding" or "Lottery"
                imgui.same_line()
                imgui.text(string.format("| %s | %s | Attempts: %d",
                    modeText, s.nickname or "Unknown",
                    type(s.attempts) == "table" and #s.attempts or 0))
            end
        else
            imgui.text_colored("Status: INACTIVE", 0xFF888888)
        end

        imgui.spacing()
        imgui.separator()
        imgui.spacing()

        if RerollTracker.currentSession and RerollTracker.currentSession.nickname then
            imgui.text("Current:")
            imgui.text(string.format("  %s", RerollTracker.currentSession.nickname))
        else
            imgui.text_colored("Weapon: (Auto-detected on first action)", 0xFF888888)
        end

        imgui.spacing()
        imgui.separator()

        if imgui.button("Clear History") then
            clear_history()
        end

        imgui.spacing()
        imgui.text(string.format("JSON: reframework/data/%s", RerollTracker.dataFilePath))
        local totalWeapons = #RerollTracker.weapons
            + (RerollTracker.currentSession and #RerollTracker.currentSession.attempts > 0 and 1 or 0)
        imgui.text(string.format("Total weapons recorded: %d", totalWeapons))

        imgui.tree_pop()
    end
end)
