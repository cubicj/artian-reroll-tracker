local _M = {}

local Sdk

_M.on_save = function() end

_M.FilterWindow = {
    open = false,
    dirty = true,
    filters = {},
    categories = {},
    results = {},
    totalAttempts = 0,
    currentPage = 1,
    pageSize = 50,
    weaponNames = {},
    weaponComboItems = {"All"},
    weaponComboIdx = 1,
    selected = {},
    hideUnchecked = false,
}

_M.LotteryWindow = {
    open = false,
    dirty = true,
    results = {},
    totalAttempts = 0,
    currentPage = 1,
    pageSize = 50,
    weaponComboItems = {"All"},
    weaponComboIdx = 1,
    groupItems = {},
    groupSelected = {},
    seriesItems = {},
    seriesSelected = {},
    selected = {},
    hideUnchecked = false,
}

_M.RerollTracker = {
    enabled = false,
    currentSession = nil,
    weapons = {},
    attemptCount = 0,
    dataFilePath = "reroll_sessions.json",
    trackingMode = 1,
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
    local typeName = Sdk.get_weapon_type_name(weaponType)
    session.weaponType = weaponType
    session.weaponTypeName = typeName
    session.attribute = attribute
    session.nickname = (attribute ~= "" and attribute .. " " or "") .. typeName
end

local function find_existing_session(weaponType, attribute, mode)
    for i, weapon in ipairs(_M.RerollTracker.weapons) do
        if weapon.weaponType == weaponType and weapon.attribute == attribute and weapon.mode == mode then
            return i
        end
    end
    return nil
end

local function save_current_session_to_weapons()
    if not _M.RerollTracker.currentSession then return end
    if #_M.RerollTracker.currentSession.attempts == 0 then return end
    local existingIndex = find_existing_session(
        _M.RerollTracker.currentSession.weaponType,
        _M.RerollTracker.currentSession.attribute,
        _M.RerollTracker.currentSession.mode
    )
    if existingIndex then
        _M.RerollTracker.weapons[existingIndex] = _M.RerollTracker.currentSession
    else
        table.insert(_M.RerollTracker.weapons, _M.RerollTracker.currentSession)
    end
end

local function finish_current_session()
    if not _M.RerollTracker.currentSession then return end
    if #_M.RerollTracker.currentSession.attempts == 0 then
        _M.RerollTracker.currentSession = nil
        _M.RerollTracker.attemptCount = 0
        return
    end
    _M.RerollTracker.currentSession.endTime = os.date("%Y-%m-%d %H:%M:%S")
    _M.RerollTracker.currentSession.totalAttempts = #_M.RerollTracker.currentSession.attempts
    save_current_session_to_weapons()
    _M.RerollTracker.currentSession = nil
    _M.RerollTracker.attemptCount = 0
end

function _M.start_new_session()
    if _M.RerollTracker.currentSession then
        finish_current_session()
    end
    local modeName = _M.RerollTracker.trackingMode == Sdk.MODE_GRINDING and "grinding" or "lottery"
    _M.RerollTracker.currentSession = create_session_template(modeName)
    _M.RerollTracker.attemptCount = 0
end

function _M.reset_all_captured()
    _M.RerollTracker._lastCapturedWeaponType = nil
    _M.RerollTracker._lastCapturedAttribute = nil
    _M.RerollTracker._lotterySkillEquipWork = nil
    _M.RerollTracker._grindingEquipWork = nil
end

function _M.ensure_session_mode(targetMode)
    if not _M.RerollTracker.currentSession then
        _M.RerollTracker.trackingMode = targetMode
        _M.start_new_session()
    elseif _M.RerollTracker.currentSession.mode ~= (targetMode == Sdk.MODE_GRINDING and "grinding" or "lottery") then
        finish_current_session()
        _M.RerollTracker.trackingMode = targetMode
        _M.start_new_session()
    end
end

function _M.check_and_update_session_weapon(capturedType, capturedAttribute)
    if not _M.RerollTracker.currentSession then return end
    local session = _M.RerollTracker.currentSession

    if session.weaponType == -1 then
        apply_weapon_info(session, capturedType, capturedAttribute)
        local existingIndex = find_existing_session(capturedType, capturedAttribute, session.mode)
        if existingIndex then
            _M.RerollTracker.currentSession = _M.RerollTracker.weapons[existingIndex]
            _M.RerollTracker.attemptCount = #_M.RerollTracker.currentSession.attempts
            table.remove(_M.RerollTracker.weapons, existingIndex)
        end
        return
    end

    local typeChanged = capturedType and capturedType ~= session.weaponType
    local attrChanged = capturedAttribute ~= "" and session.attribute ~= "" and capturedAttribute ~= session.attribute
    if not typeChanged and not attrChanged then return end

    save_current_session_to_weapons()
    local existingIndex = find_existing_session(capturedType, capturedAttribute, session.mode)
    if existingIndex then
        _M.RerollTracker.currentSession = _M.RerollTracker.weapons[existingIndex]
        _M.RerollTracker.attemptCount = #_M.RerollTracker.currentSession.attempts
        table.remove(_M.RerollTracker.weapons, existingIndex)
    else
        local modeName = _M.RerollTracker.trackingMode == Sdk.MODE_GRINDING and "grinding" or "lottery"
        _M.RerollTracker.currentSession = create_session_template(modeName)
        _M.RerollTracker.attemptCount = 0
    end
    apply_weapon_info(_M.RerollTracker.currentSession, capturedType, capturedAttribute)
    _M.on_save()
end

function _M.record_attempt(bonusIds)
    if not _M.RerollTracker.enabled or not _M.RerollTracker.currentSession then return end
    if #bonusIds == 0 then return end
    _M.check_and_update_session_weapon(
        _M.RerollTracker._lastCapturedWeaponType,
        _M.RerollTracker._lastCapturedAttribute or ""
    )
    _M.RerollTracker.attemptCount = _M.RerollTracker.attemptCount + 1
    local bonusNames = {}
    for _, id in ipairs(bonusIds) do
        table.insert(bonusNames, Sdk.get_bonus_name(id))
    end
    table.insert(_M.RerollTracker.currentSession.attempts, {
        attemptNum = _M.RerollTracker.attemptCount,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        bonuses = bonusNames
    })
    _M.on_save()
    _M.FilterWindow.dirty = true
end

function _M.record_skill_attempt(seriesSkill, groupSkill)
    if not _M.RerollTracker.enabled or not _M.RerollTracker.currentSession then return end
    if not seriesSkill or seriesSkill == "" then return end
    _M.check_and_update_session_weapon(
        _M.RerollTracker._lastCapturedWeaponType,
        _M.RerollTracker._lastCapturedAttribute or ""
    )
    _M.RerollTracker.attemptCount = _M.RerollTracker.attemptCount + 1
    table.insert(_M.RerollTracker.currentSession.attempts, {
        attemptNum = _M.RerollTracker.attemptCount,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        skills = {
            series = seriesSkill,
            group = groupSkill or ""
        }
    })
    _M.on_save()
    _M.LotteryWindow.dirty = true
end

function _M.clear_history()
    _M.RerollTracker.weapons = {}
    _M.RerollTracker.currentSession = nil
    _M.RerollTracker.attemptCount = 0
    _M.reset_all_captured()
    _M.on_save()
    _M.FilterWindow.dirty = true
    if _M.RerollTracker.enabled then
        _M.start_new_session()
    end
end

function _M.init(sdk)
    Sdk = sdk
end

return _M
