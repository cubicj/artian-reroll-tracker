local Sdk, State
local _M = {}

local filterFont

function _M.init(sdk, state, font)
    Sdk = sdk
    State = state
    filterFont = font
end

local function matches_filters(bonusNames, filters)
    local counts = Sdk.classify_bonuses(bonusNames)
    for category, minCount in pairs(filters) do
        if minCount > 0 then
            if not counts[category] or counts[category] < minCount then
                return false
            end
        end
    end
    return true
end

local function draw_filter_row(label, currentValue)
    imgui.text(label)
    imgui.same_line()
    local newValue = currentValue
    for _, opt in ipairs(Sdk.FILTER_OPTIONS) do
        local isSelected = (currentValue == opt.value)
        if isSelected then
            imgui.push_style_color(21, 0xFFCC8844)
        end
        if imgui.button(opt.label .. "##" .. label, Sdk.FILTER_BTN_SIZE) then
            newValue = opt.value
        end
        if isSelected then
            imgui.pop_style_color(1)
        end
        imgui.same_line()
    end
    imgui.new_line()
    return newValue
end

function _M.collect_results()
    local FW = State.FilterWindow
    local RT = State.RerollTracker

    local baseNames = Sdk.extract_base_names_from_weapons(RT.weapons, RT.currentSession)

    local sortedCategories = {}
    table.insert(sortedCategories, "EX")
    local others = {}
    for name in pairs(baseNames) do
        table.insert(others, name)
    end
    table.sort(others)
    for _, name in ipairs(others) do
        table.insert(sortedCategories, name)
    end
    FW.categories = sortedCategories

    for _, cat in ipairs(sortedCategories) do
        if FW.filters[cat] == nil then
            FW.filters[cat] = 0
        end
    end

    local allWeapons = {}
    for _, w in ipairs(RT.weapons) do table.insert(allWeapons, w) end
    if RT.currentSession then table.insert(allWeapons, RT.currentSession) end

    local weaponSet = {}
    local weaponList = {}
    for _, weapon in ipairs(allWeapons) do
        if weapon.mode == "grinding" and weapon.nickname then
            local nick = weapon.nickname
            if not weaponSet[nick] then
                weaponSet[nick] = true
                table.insert(weaponList, nick)
            end
        end
    end
    table.sort(weaponList)
    FW.weaponNames = weaponList

    local comboItems = {"All"}
    for _, name in ipairs(weaponList) do
        table.insert(comboItems, name)
    end
    FW.weaponComboItems = comboItems

    if FW.weaponComboIdx > #comboItems then
        FW.weaponComboIdx = 1
    end

    local selectedWeapon = nil
    if FW.weaponComboIdx > 1 then
        selectedWeapon = comboItems[FW.weaponComboIdx]
    end

    local results = {}
    local total = 0

    for _, weapon in ipairs(allWeapons) do
        if weapon.mode == "grinding" and weapon.attempts then
            local nick = weapon.nickname or "Unknown"
            local weaponMatch = (selectedWeapon == nil) or (nick == selectedWeapon)
            for _, attempt in ipairs(weapon.attempts) do
                total = total + 1
                if weaponMatch and attempt.bonuses and matches_filters(attempt.bonuses, FW.filters) then
                    table.insert(results, {
                        attemptNum = attempt.attemptNum,
                        weapon = nick,
                        bonuses = attempt.bonuses,
                    })
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.attemptNum < b.attemptNum end)
    FW.results = results
    FW.totalAttempts = total
    FW.currentPage = 1
    FW.dirty = false
end

function _M.register_ui()
    re.on_frame(function()
        local FW = State.FilterWindow
        if not FW.open then return end

        local ok, err = pcall(function()
            if filterFont then imgui.push_font(filterFont) end

            FW.open = imgui.begin_window("Artian Grinding Filter", FW.open, 0)

            if FW.dirty then _M.collect_results() end

            imgui.spacing()

            local comboChanged, newIdx = imgui.combo("Weapon", FW.weaponComboIdx, FW.weaponComboItems)
            if comboChanged then
                FW.weaponComboIdx = newIdx
                FW.dirty = true
                _M.collect_results()
            end

            imgui.spacing()
            imgui.separator()
            imgui.spacing()

            local changed = false
            for _, category in ipairs(FW.categories) do
                local v = draw_filter_row(category .. ":", FW.filters[category] or 0)
                if v ~= (FW.filters[category] or 0) then
                    FW.filters[category] = v
                    changed = true
                end
            end

            if changed then
                FW.dirty = true
                _M.collect_results()
            end

            imgui.spacing()
            imgui.separator()
            imgui.spacing()

            local results = FW.results

            if FW.hideUnchecked then
                imgui.push_style_color(21, 0xFF557744)
            end
            if imgui.button(FW.hideUnchecked and "Show All" or "Checked Only") then
                FW.hideUnchecked = not FW.hideUnchecked
            end
            if FW.hideUnchecked then
                imgui.pop_style_color(1)
            end
            imgui.same_line()
            if imgui.button("Reset##gf") then
                FW.weaponComboIdx = 1
                FW.filters = {}
                FW.selected = {}
                FW.hideUnchecked = false
                FW.dirty = true
                _M.collect_results()
            end
            imgui.spacing()
            imgui.text(string.format("Results: %d / %d attempts", #results, FW.totalAttempts))

            imgui.spacing()

            if #results == 0 then
                if FW.totalAttempts == 0 then
                    imgui.text_colored("No grinding data recorded yet.", 0xFF888888)
                else
                    imgui.text_colored("No results match current filters.", 0xFF888888)
                end
            else
                local displayResults = results
                if FW.hideUnchecked then
                    displayResults = {}
                    for _, r in ipairs(results) do
                        local key = r.weapon .. "_" .. tostring(r.attemptNum)
                        if FW.selected[key] then
                            table.insert(displayResults, r)
                        end
                    end
                end

                local totalPages = math.max(1, math.ceil(#displayResults / FW.pageSize))
                if FW.currentPage > totalPages then FW.currentPage = totalPages end
                local startIdx = (FW.currentPage - 1) * FW.pageSize + 1
                local endIdx = math.min(FW.currentPage * FW.pageSize, #displayResults)

                if imgui.begin_table("FilterResults", 4, imgui.TableFlags.RowBg) then
                    imgui.table_setup_column("", imgui.ColumnFlags.WidthFixed, 30)
                    imgui.table_setup_column("#", imgui.ColumnFlags.WidthFixed, 40)
                    imgui.table_setup_column("Weapon", imgui.ColumnFlags.WidthStretch, 2.0)
                    imgui.table_setup_column("Bonuses", imgui.ColumnFlags.WidthStretch, 5.0)
                    imgui.table_headers_row()

                    local DIM = 0xFF666666

                    for i = startIdx, endIdx do
                        local r = displayResults[i]
                        local key = r.weapon .. "_" .. tostring(r.attemptNum)
                        local checked = FW.selected[key] or false
                        local btnId = "##sel" .. tostring(i)

                        imgui.table_next_row()
                        imgui.table_next_column()
                        if checked then
                            imgui.push_style_color(21, 0xFF557744)
                        end
                        if imgui.button(checked and "v" .. btnId or btnId, {20, 20}) then
                            FW.selected[key] = not checked
                        end
                        if checked then
                            imgui.pop_style_color(1)
                        end

                        imgui.table_next_column()
                        if checked then
                            imgui.text(tostring(r.attemptNum))
                        else
                            imgui.text_colored(tostring(r.attemptNum), DIM)
                        end
                        imgui.table_next_column()
                        if checked then
                            imgui.text(r.weapon)
                        else
                            imgui.text_colored(r.weapon, DIM)
                        end
                        imgui.table_next_column()
                        local bonusText = table.concat(r.bonuses, ", ")
                        if checked then
                            imgui.text(bonusText)
                        else
                            imgui.text_colored(bonusText, DIM)
                        end
                    end

                    imgui.end_table()
                end

                imgui.spacing()
                if FW.currentPage > 1 then
                    if imgui.button("< Prev") then
                        FW.currentPage = FW.currentPage - 1
                    end
                    imgui.same_line()
                end
                imgui.text(string.format("Page %d / %d", FW.currentPage, totalPages))
                if FW.currentPage < totalPages then
                    imgui.same_line()
                    if imgui.button("Next >") then
                        FW.currentPage = FW.currentPage + 1
                    end
                end
            end

            imgui.end_window()
            if filterFont then imgui.pop_font() end
        end)

        if not ok then
            log.error(Sdk.TAG .. " [FilterUI] " .. tostring(err))
            pcall(function()
                if filterFont then imgui.pop_font() end
            end)
            FW.open = false
        end
    end)
end

return _M
