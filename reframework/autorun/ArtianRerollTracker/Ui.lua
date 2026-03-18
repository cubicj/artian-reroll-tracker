local State
local _M = {}

function _M.init(state)
    State = state
end

function _M.register()
    re.on_draw_ui(function()
        if imgui.tree_node("Artian Reroll Tracker") then
            if imgui.button("Open Grinding Result") then
                State.FilterWindow.open = true
                State.FilterWindow.dirty = true
            end
            imgui.same_line()
            if imgui.button("Open Lottery Result") then
                State.LotteryWindow.open = true
                State.LotteryWindow.dirty = true
            end

            imgui.spacing()

            local changed, newValue = imgui.checkbox("Enable Tracker", State.RerollTracker.enabled)
            if changed then
                State.RerollTracker.enabled = newValue
                if newValue and not State.RerollTracker.currentSession then
                    State.start_new_session()
                elseif not newValue then
                    State.reset_all_captured()
                end
            end

            imgui.spacing()

            if State.RerollTracker.enabled then
                imgui.text_colored("Status: ACTIVE", 0xFF00FF00)
                local s = State.RerollTracker.currentSession
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

            if State.RerollTracker.currentSession and State.RerollTracker.currentSession.nickname then
                imgui.text("Current:")
                imgui.text(string.format("  %s", State.RerollTracker.currentSession.nickname))
            else
                imgui.text_colored("Weapon: (Auto-detected on first action)", 0xFF888888)
            end

            imgui.spacing()
            imgui.separator()

            if imgui.button("Clear History") then
                State.clear_history()
            end

            imgui.spacing()
            imgui.text(string.format("JSON: reframework/data/%s", State.RerollTracker.dataFilePath))
            local totalWeapons = #State.RerollTracker.weapons
                + (State.RerollTracker.currentSession and #State.RerollTracker.currentSession.attempts > 0 and 1 or 0)
            imgui.text(string.format("Total weapons recorded: %d", totalWeapons))

            imgui.tree_pop()
        end
    end)
end

return _M
