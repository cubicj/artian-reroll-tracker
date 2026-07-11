local _M = {}

_M.TAG = "[RerollTracker]"

_M.MODE_GRINDING = 1
_M.MODE_LOTTERY = 2

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

_M.TD_ArtianUtil = TD_ArtianUtil
_M.TD_Em0078ArtianUtil = TD_Em0078ArtianUtil
_M.TD_GuiMessage = TD_GuiMessage
_M.TD_GUI080000ArtianStatus = TD_GUI080000ArtianStatus
_M.TD_LoopGaugeChangeRequirePoint = TD_LoopGaugeChangeRequirePoint
_M.TD_NotifyWindow = TD_NotifyWindow
_M.TD_NotifyWindowDef = TD_NotifyWindowDef
_M.TD_WeaponUtil = TD_WeaponUtil
_M.TD_WeaponDef = TD_WeaponDef
_M.TD_WeaponDefType = TD_WeaponDefType
_M.TD_WeaponDefTypeFixed = TD_WeaponDefTypeFixed
_M.TD_MessageUtil = TD_MessageUtil
_M.TD_BonusId = TD_BonusId
_M.TD_BonusIdFixed = TD_BonusIdFixed

local FN_GetBonusName = TD_ArtianUtil and TD_ArtianUtil:get_method("Name(app.ArtianDef.BONUS_ID)")
local FN_GetLocalizedMsg = TD_GuiMessage and TD_GuiMessage:get_method("get(System.Guid)")
local FN_LotterySkill = TD_Em0078ArtianUtil and TD_Em0078ArtianUtil:get_method("lotterySkill(app.savedata.cEquipWork)")
local FN_LotteryCreateBonus = TD_Em0078ArtianUtil and TD_Em0078ArtianUtil:get_method("lotteryCreateBonus(app.user_data.WeaponData.cData, app.savedata.cEquipWork, System.Boolean)")
local FN_GetWeaponTypeName = TD_WeaponUtil and TD_WeaponUtil:get_method("getWeaponTypeName(app.WeaponDef.TYPE)")
local FN_GetSkillName = TD_MessageUtil and TD_MessageUtil:get_method("getHunterSkillName(app.HunterDef.Skill)")

_M.FN_GetBonusName = FN_GetBonusName
_M.FN_GetLocalizedMsg = FN_GetLocalizedMsg
_M.FN_LotterySkill = FN_LotterySkill
_M.FN_LotteryCreateBonus = FN_LotteryCreateBonus
_M.FN_GetWeaponTypeName = FN_GetWeaponTypeName
_M.FN_GetSkillName = FN_GetSkillName

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

_M.notifyWindowID2Name = notifyWindowID2Name
_M.fixedToTypeMap = fixedToTypeMap
_M.fixedToBonusIdMap = fixedToBonusIdMap

local BONUS_TIER_SUFFIXES = {" III", " II", " I", " IV", " V", " EX", "Ⅲ", "Ⅱ", "Ⅰ", "Ⅳ", "Ⅴ", "EX"}

local function strip_bonus_tier(bonusName)
    for _, suffix in ipairs(BONUS_TIER_SUFFIXES) do
        if #bonusName > #suffix and bonusName:sub(-#suffix) == suffix then
            return bonusName:sub(1, #bonusName - #suffix):gsub("%s+$", "")
        end
    end
    return bonusName:gsub("%s+$", "")
end

local function extract_base_names_from_weapons(weapons, currentSession)
    local baseNames = {}
    local allWeapons = {}
    for _, w in ipairs(weapons) do table.insert(allWeapons, w) end
    if currentSession then table.insert(allWeapons, currentSession) end
    for _, weapon in ipairs(allWeapons) do
        if weapon.mode == "grinding" and weapon.attempts then
            for _, attempt in ipairs(weapon.attempts) do
                if attempt.bonuses then
                    for _, name in ipairs(attempt.bonuses) do
                        local base = strip_bonus_tier(name)
                        if base ~= "" then
                            baseNames[base] = true
                        end
                    end
                end
            end
        end
    end
    return baseNames
end

local function classify_bonuses(bonusNames)
    local counts = {}
    local exCount = 0
    for _, name in ipairs(bonusNames) do
        if name:sub(-2) == "EX" then
            exCount = exCount + 1
        end
        local base = strip_bonus_tier(name)
        if base ~= "" then
            counts[base] = (counts[base] or 0) + 1
        end
    end
    counts["EX"] = exCount
    return counts
end

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

_M.strip_bonus_tier = strip_bonus_tier
_M.extract_base_names_from_weapons = extract_base_names_from_weapons
_M.classify_bonuses = classify_bonuses
_M.get_bonus_name = get_bonus_name
_M.get_weapon_type_name = get_weapon_type_name
_M.get_skill_name = get_skill_name
_M.init_artian_skill_data = init_artian_skill_data
_M.decode_artian_skill_type = decode_artian_skill_type
_M.decode_grinding_bonuses = decode_grinding_bonuses
_M.get_skill_names_from_artian_type = get_skill_names_from_artian_type

_M.TARGET_DIALOGS = {
    ["EQUIP_000"] = 0,
    ["EQUIPMENT_0008_15"] = 0,
    ["GUI080301_0005_DLG"] = 0,
    ["GUI080301_0009_DLG"] = 1,
    ["GUI080301_0010_DLG"] = 1,
}

_M.FILTER_OPTIONS = {
    { label = "All", value = 0 },
    { label = "1+",  value = 1 },
    { label = "2+",  value = 2 },
    { label = "3+",  value = 3 },
    { label = "4+",  value = 4 },
    { label = "5",   value = 5 },
}

_M.FILTER_BTN_SIZE = {48, 26}

return _M
