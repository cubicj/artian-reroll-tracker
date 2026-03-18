local Sdk, State
local _M = {}

local filterFont

function _M.init(sdk, state, font)
    Sdk = sdk
    State = state
    filterFont = font
end

function _M.collect_results()
    local LW = State.LotteryWindow
    local RT = State.RerollTracker

    local allWeapons = {}
    for _, w in ipairs(RT.weapons) do table.insert(allWeapons, w) end
    if RT.currentSession then table.insert(allWeapons, RT.currentSession) end

    local weaponSet = {}
    local weaponList = {}
    local groupSet = {}
    local groupList = {}
    local seriesSet = {}
    local seriesList = {}
    local NONE_LABEL = "(None)"

    for _, weapon in ipairs(allWeapons) do
        if weapon.mode == "lottery" and weapon.nickname then
            local nick = weapon.nickname
            if not weaponSet[nick] then
                weaponSet[nick] = true
                table.insert(weaponList, nick)
            end
            if weapon.attempts then
                for _, attempt in ipairs(weapon.attempts) do
                    if attempt.skills then
                        local g = attempt.skills.group or ""
                        local s = attempt.skills.series or ""
                        local gLabel = g ~= "" and g or NONE_LABEL
                        local sLabel = s ~= "" and s or NONE_LABEL
                        if not groupSet[gLabel] then
                            groupSet[gLabel] = true
                            table.insert(groupList, gLabel)
                        end
                        if not seriesSet[sLabel] then
                            seriesSet[sLabel] = true
                            table.insert(seriesList, sLabel)
                        end
                    end
                end
            end
        end
    end
    table.sort(weaponList)
    table.sort(groupList)
    table.sort(seriesList)

    local weaponCombo = {"All"}
    for _, name in ipairs(weaponList) do table.insert(weaponCombo, name) end
    LW.weaponComboItems = weaponCombo
    if LW.weaponComboIdx > #weaponCombo then LW.weaponComboIdx = 1 end

    LW.groupItems = groupList
    LW.seriesItems = seriesList

    local selectedWeapon = nil
    if LW.weaponComboIdx > 1 then
        selectedWeapon = weaponCombo[LW.weaponComboIdx]
    end
    local hasGroupFilter = false
    for _ in pairs(LW.groupSelected) do hasGroupFilter = true; break end
    local hasSeriesFilter = false
    for _ in pairs(LW.seriesSelected) do hasSeriesFilter = true; break end

    local results = {}
    local total = 0

    for _, weapon in ipairs(allWeapons) do
        if weapon.mode == "lottery" and weapon.attempts then
            local nick = weapon.nickname or "Unknown"
            local weaponMatch = (selectedWeapon == nil) or (nick == selectedWeapon)
            for _, attempt in ipairs(weapon.attempts) do
                total = total + 1
                if weaponMatch and attempt.skills then
                    local g = attempt.skills.group or ""
                    local s = attempt.skills.series or ""
                    local gLabel = g ~= "" and g or NONE_LABEL
                    local sLabel = s ~= "" and s or NONE_LABEL
                    local groupMatch = not hasGroupFilter or LW.groupSelected[gLabel]
                    local seriesMatch = not hasSeriesFilter or LW.seriesSelected[sLabel]
                    if groupMatch and seriesMatch then
                        table.insert(results, {
                            attemptNum = attempt.attemptNum,
                            weapon = nick,
                            group = gLabel,
                            series = sLabel,
                        })
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.attemptNum < b.attemptNum end)
    LW.results = results
    LW.totalAttempts = total
    LW.currentPage = 1
    LW.dirty = false
end

function _M.register_ui()
    re.on_frame(function()
        local LW = State.LotteryWindow
        if not LW.open then return end

        local ok, err = pcall(function()
            if filterFont then imgui.push_font(filterFont) end

            LW.open = imgui.begin_window("Artian Lottery Filter", LW.open, 0)

            if LW.dirty then _M.collect_results() end

            imgui.spacing()

            local wChanged, wIdx = imgui.combo("Weapon##lot", LW.weaponComboIdx, LW.weaponComboItems)
            if wChanged then
                LW.weaponComboIdx = wIdx
                if wIdx == 1 then
                    LW.groupSelected = {}
                    LW.seriesSelected = {}
                end
                LW.dirty = true
                _M.collect_results()
            end

            if LW.weaponComboIdx > 1 then
                imgui.set_next_item_open(false, 2)
                if imgui.tree_node("Group") then
                    for idx, name in ipairs(LW.groupItems) do
                        local active = LW.groupSelected[name] or false
                        if active then imgui.push_style_color(21, 0xFF557744) end
                        if imgui.button(name .. "##grp") then
                            if active then
                                LW.groupSelected[name] = nil
                            else
                                LW.groupSelected[name] = true
                            end
                            LW.dirty = true
                            _M.collect_results()
                        end
                        if active then imgui.pop_style_color(1) end
                        if idx % 4 ~= 0 and idx ~= #LW.groupItems then imgui.same_line() end
                    end
                    imgui.tree_pop()
                end

                imgui.set_next_item_open(false, 2)
                if imgui.tree_node("Series") then
                    for idx, name in ipairs(LW.seriesItems) do
                        local active = LW.seriesSelected[name] or false
                        if active then imgui.push_style_color(21, 0xFF557744) end
                        if imgui.button(name .. "##ser") then
                            if active then
                                LW.seriesSelected[name] = nil
                            else
                                LW.seriesSelected[name] = true
                            end
                            LW.dirty = true
                            _M.collect_results()
                        end
                        if active then imgui.pop_style_color(1) end
                        if idx % 4 ~= 0 and idx ~= #LW.seriesItems then imgui.same_line() end
                    end
                    imgui.tree_pop()
                end
            end

            imgui.spacing()
            imgui.separator()
            imgui.spacing()

            local results = LW.results

            if LW.hideUnchecked then
                imgui.push_style_color(21, 0xFF557744)
            end
            if imgui.button(LW.hideUnchecked and "Show All##lot" or "Checked Only##lot") then
                LW.hideUnchecked = not LW.hideUnchecked
            end
            if LW.hideUnchecked then
                imgui.pop_style_color(1)
            end
            imgui.spacing()
            imgui.text(string.format("Results: %d / %d attempts", #results, LW.totalAttempts))

            imgui.spacing()

            if #results == 0 then
                if LW.totalAttempts == 0 then
                    imgui.text_colored("No lottery data recorded yet.", 0xFF888888)
                else
                    imgui.text_colored("No results match current filters.", 0xFF888888)
                end
            else
                local displayResults = results
                if LW.hideUnchecked then
                    displayResults = {}
                    for _, r in ipairs(results) do
                        local key = r.weapon .. "_" .. tostring(r.attemptNum)
                        if LW.selected[key] then
                            table.insert(displayResults, r)
                        end
                    end
                end

                local totalPages = math.max(1, math.ceil(#displayResults / LW.pageSize))
                if LW.currentPage > totalPages then LW.currentPage = totalPages end
                local startIdx = (LW.currentPage - 1) * LW.pageSize + 1
                local endIdx = math.min(LW.currentPage * LW.pageSize, #displayResults)

                if imgui.begin_table("LotteryResults", 5, imgui.TableFlags.RowBg) then
                    imgui.table_setup_column("", imgui.ColumnFlags.WidthFixed, 30)
                    imgui.table_setup_column("#", imgui.ColumnFlags.WidthFixed, 40)
                    imgui.table_setup_column("Weapon", imgui.ColumnFlags.WidthStretch, 2.0)
                    imgui.table_setup_column("Group", imgui.ColumnFlags.WidthStretch, 2.0)
                    imgui.table_setup_column("Series", imgui.ColumnFlags.WidthStretch, 2.0)
                    imgui.table_headers_row()

                    local DIM = 0xFF666666

                    for i = startIdx, endIdx do
                        local r = displayResults[i]
                        local key = r.weapon .. "_" .. tostring(r.attemptNum)
                        local checked = LW.selected[key] or false
                        local btnId = "##lsel" .. tostring(i)

                        imgui.table_next_row()
                        imgui.table_next_column()
                        if checked then
                            imgui.push_style_color(21, 0xFF557744)
                        end
                        if imgui.button(checked and "v" .. btnId or btnId, {20, 20}) then
                            LW.selected[key] = not checked
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
                        if checked then
                            imgui.text(r.group)
                        else
                            imgui.text_colored(r.group, DIM)
                        end
                        imgui.table_next_column()
                        if checked then
                            imgui.text(r.series)
                        else
                            imgui.text_colored(r.series, DIM)
                        end
                    end

                    imgui.end_table()
                end

                imgui.spacing()
                if LW.currentPage > 1 then
                    if imgui.button("< Prev##lot") then
                        LW.currentPage = LW.currentPage - 1
                    end
                    imgui.same_line()
                end
                imgui.text(string.format("Page %d / %d", LW.currentPage, totalPages))
                if LW.currentPage < totalPages then
                    imgui.same_line()
                    if imgui.button("Next >##lot") then
                        LW.currentPage = LW.currentPage + 1
                    end
                end
            end

            imgui.end_window()
            if filterFont then imgui.pop_font() end
        end)

        if not ok then
            log.error(Sdk.TAG .. " [LotteryUI] " .. tostring(err))
            pcall(function()
                if filterFont then imgui.pop_font() end
            end)
            LW.open = false
        end
    end)
end

return _M
