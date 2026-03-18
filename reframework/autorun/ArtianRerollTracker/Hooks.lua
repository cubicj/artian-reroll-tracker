local Sdk, State
local _M = {}

function _M.init(sdk, state)
    Sdk = sdk
    State = state
end

local function on_lottery_skill_pre(args)
    if not State.RerollTracker.enabled then return end
    State.RerollTracker._lotterySkillEquipWork = args[2]
end

local function on_lottery_skill_post(retval)
    if not State.RerollTracker.enabled then return retval end
    local ok, err = pcall(function()
        local equipWork = sdk.to_managed_object(State.RerollTracker._lotterySkillEquipWork)
        if not equipWork then return end
        local bonusByCreating = equipWork:get_field("BonusByCreating")
        if not bonusByCreating or bonusByCreating <= 0 then return end
        local aSkillType = Sdk.decode_artian_skill_type(bonusByCreating)
        if not aSkillType or aSkillType <= 0 then return end
        State.ensure_session_mode(Sdk.MODE_LOTTERY)
        local seriesSkill, groupSkill = Sdk.get_skill_names_from_artian_type(aSkillType)
        State.record_skill_attempt(seriesSkill, groupSkill)
    end)
    if not ok then log.error(Sdk.TAG .. " lotterySkill error: " .. tostring(err)) end
    State.RerollTracker._lotterySkillEquipWork = nil
    return retval
end

local function on_lottery_create_bonus_pre(args)
    if not State.RerollTracker.enabled then return end
    State.RerollTracker._grindingEquipWork = args[3]
end

local function on_lottery_create_bonus_post(retval)
    if not State.RerollTracker.enabled then return retval end
    local ok, err = pcall(function()
        local equipWork = sdk.to_managed_object(State.RerollTracker._grindingEquipWork)
        if not equipWork then return end
        local bonusByGrinding = equipWork:get_field("BonusByGrinding")
        local bonusIds = Sdk.decode_grinding_bonuses(bonusByGrinding)
        if #bonusIds == 0 then return end
        State.ensure_session_mode(Sdk.MODE_GRINDING)
        State.record_attempt(bonusIds)
    end)
    if not ok then log.error(Sdk.TAG .. " lotteryCreateBonus error: " .. tostring(err)) end
    State.RerollTracker._grindingEquipWork = nil
    return retval
end

local function on_set_weapon_data_core_pre(args)
    if not State.RerollTracker.enabled then return end
    local ok, err = pcall(function()
        local equipSet = sdk.to_managed_object(args[3])
        if not equipSet then return end
        local weaponData = equipSet:get_field("<WeaponData>k__BackingField")
        if not weaponData then return end
        local rawType = weaponData:get_field("_Type")
        local weaponType = rawType
        if rawType and Sdk.fixedToTypeMap[rawType] ~= nil then
            weaponType = Sdk.fixedToTypeMap[rawType]
        end
        if weaponType and weaponType >= 0 and weaponType <= 13 then
            State.RerollTracker._lastCapturedWeaponType = weaponType
        end
        local this = sdk.to_managed_object(args[2])
        if this then
            local perfText = this:get_field("_PerformanceText")
            if perfText then
                local perfName = perfText:call("get_Message")
                if perfName and perfName ~= "" then
                    State.RerollTracker._lastCapturedAttribute = perfName
                end
            end
        end
    end)
    if not ok then log.error(Sdk.TAG .. " setWeaponDataCore error: " .. tostring(err)) end
end

local function on_grinding_anim_pre(args)
    if not State.RerollTracker.enabled then
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    local ok, err = pcall(function()
        local action = sdk.to_managed_object(args[3])
        if action then action:Invoke() end
    end)
    if not ok then
        log.error(Sdk.TAG .. " grinding error: " .. tostring(err))
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    return sdk.PreHookResult.SKIP_ORIGINAL
end

local function on_lottery_anim_pre(args)
    if not State.RerollTracker.enabled then
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    local ok, err = pcall(function()
        local action = sdk.to_managed_object(args[3])
        if action then action:Invoke() end
    end)
    if not ok then
        log.error(Sdk.TAG .. " lottery error: " .. tostring(err))
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    return sdk.PreHookResult.SKIP_ORIGINAL
end

local function on_start_upgrade_pre(args)
    if not State.RerollTracker.enabled then
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    local ok, err = pcall(function()
        local action = sdk.to_managed_object(args[4])
        if action then action:Invoke() end
    end)
    if not ok then
        log.error(Sdk.TAG .. " startUpGrade error: " .. tostring(err))
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    return sdk.PreHookResult.SKIP_ORIGINAL
end

local function on_notify_window_pre(args)
    local ok, result = pcall(function()
        local notifyWindowInfo = sdk.to_managed_object(args[3])
        if not notifyWindowInfo then return nil end
        local textInfo = notifyWindowInfo:get_TextInfo()
        if not textInfo then return nil end
        local windowId = notifyWindowInfo:get_NotifyWindowId()
        if not windowId then return nil end
        local windowIdName = Sdk.notifyWindowID2Name[windowId]
        if not windowIdName then return nil end
        if not State.RerollTracker.enabled then return nil end
        local selectedIndex = Sdk.TARGET_DIALOGS[windowIdName]
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
        log.error(Sdk.TAG .. " notifyWindow error: " .. tostring(result))
        return sdk.PreHookResult.CALL_ORIGINAL
    end
    if result then return result end
    return sdk.PreHookResult.CALL_ORIGINAL
end

function _M.register()
    local function try_hook(label, typeDef, methodName, preFn, postFn)
        if not typeDef then
            log.error(Sdk.TAG .. " HOOK FAIL [" .. label .. "] typeDef is nil")
            return
        end
        local method = typeDef:get_method(methodName)
        if not method then
            log.error(Sdk.TAG .. " HOOK FAIL [" .. label .. "] method not found: " .. methodName)
            return
        end
        sdk.hook(method, preFn, postFn)
    end

    if Sdk.FN_LotterySkill then
        sdk.hook(Sdk.FN_LotterySkill, on_lottery_skill_pre, on_lottery_skill_post)
    else
        log.error(Sdk.TAG .. " HOOK FAIL [lotterySkill] FN_LotterySkill is nil")
    end

    if Sdk.FN_LotteryCreateBonus then
        sdk.hook(Sdk.FN_LotteryCreateBonus, on_lottery_create_bonus_pre, on_lottery_create_bonus_post)
    else
        log.error(Sdk.TAG .. " HOOK FAIL [lotteryCreateBonus] FN_LotteryCreateBonus is nil")
    end

    try_hook("setWeaponDataCore", Sdk.TD_GUI080000ArtianStatus, "setWeaponDataCore(app.EquipDef.EquipSet)", on_set_weapon_data_core_pre, nil)
    try_hook("grindingAnim", Sdk.TD_GUI080000ArtianStatus, "startArtianGrindingAnim(System.Action)", on_grinding_anim_pre, nil)
    try_hook("lotteryAnim", Sdk.TD_GUI080000ArtianStatus, "startSkillLotteryAnim(System.Action)", on_lottery_anim_pre, nil)
    try_hook("startUpGrade", Sdk.TD_LoopGaugeChangeRequirePoint, "startUpGrade(System.UInt32, System.Action)", on_start_upgrade_pre, nil)
    try_hook("notifyWindow", Sdk.TD_NotifyWindow, "requestNotifyWindow", on_notify_window_pre, nil)
end

return _M
