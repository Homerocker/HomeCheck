HomeCheck = CreateFrame("Frame")

HomeCheck.LibGroupTalents = LibStub("LibGroupTalents-1.0")
HomeCheck.LibSharedMedia = LibStub("LibSharedMedia-3.0")
HomeCheck.LibRangeCheck = LibStub("LibRangeCheck-2.0")

LibStub("AceTimer-3.0"):Embed(HomeCheck)
LibStub("AceComm-3.0"):Embed(HomeCheck)
LibStub("AceSerializer-3.0"):Embed(HomeCheck)

HomeCheck.groups = {}
HomeCheck.localizedSpellNames = {}
HomeCheck.deadUnits = {}
HomeCheck.RebirthTargets = {}
HomeCheck.db_ver = 2

HomeCheck.comms = {
    oRA = "oRA",
    oRA3 = "oRA3",
    BLT = "BLT Raid Cooldowns",
    CTRA = "CTRA",
    RCD2 = "RaidCooldowns",
    FRCD3 = "FatCooldowns",
    FRCD3S = "FatCooldowns (single report)",
    HomeCheck = "HomeCheck",
}

local groups = 10

local date, floor, min, pairs, select, string, strsplit, table, time, tonumber, tostring, type, unpack = date, floor, min, pairs, select, {
    find = string.find,
    gmatch = string.gmatch
}, strsplit, {
    insert = table.insert,
    remove = table.remove,
    wipe = table.wipe
}, time, tonumber, tostring, type, unpack

HomeCheck:RegisterEvent("ADDON_LOADED")

function HomeCheck:LibGroupTalents_Update(...)
    self:refreshPlayerCooldowns((UnitName((select(3, ...)))))
    self:repositionFrames()
end

HomeCheck:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, combatEvent, _, playerName, _, _, targetName, _, spellID, spellName = ...
        if combatEvent == "SPELL_CAST_SUCCESS" or combatEvent == "SPELL_RESURRECT" or combatEvent == "SPELL_AURA_APPLIED" then
            if not UnitInRaid(playerName) and not UnitInParty(playerName) then
                return
            end
            if spellID == 23983 then
                -- Readiness
                self:Readiness(playerName)
                return
            end
            if spellID == 34477 then
                -- Misdirection initial cast
                self:setCooldown(35079, playerName, 60, combatEvent ~= "SPELL_AURA_APPLIED" and targetName or nil)
                return
            elseif spellID == 57934 then
                -- Tricks of the Trade initial cast
                self:setCooldown(59628, playerName, 60, combatEvent ~= "SPELL_AURA_APPLIED" and targetName or nil)
                return
            end

            if not self.spells[spellID] then
                spellID = self.localizedSpellNames[spellName]
            end

            if self.spells[spellID] then
                self:SendCommMessage("HomeCheck", self:Serialize(spellID, playerName, targetName), "RAID")
            end

            self:setCooldown(spellID, playerName, true, combatEvent ~= "SPELL_AURA_APPLIED" and targetName or nil)
        elseif combatEvent == "SPELL_HEAL" and spellID == 48153 and self.db.profile.spells[47788] then
            -- Guardian Spirit proced
            self:GSTriggered(playerName)
        elseif combatEvent == "UNIT_DIED" then
            if UnitInRaid(playerName) or UnitInParty(playerName) then
                self.deadUnits[playerName] = true
            end
        end

        -- UNIT_SPELLCAST events are used to detect double Rebirth only
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, spellName, _, targetName = ...
        local spellID = self.localizedSpellNames[spellName]
        if spellID == 48477 then
            self.RebirthTargets[(UnitName(unit))] = targetName
        end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        local unit, spellName = ...
        local spellID = self.localizedSpellNames[spellName]
        if spellID == 48477 then
            self.RebirthTargets[(UnitName(unit))] = nil
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, spellName = ...
        local spellID = self.localizedSpellNames[spellName]

        if spellID == 48477 then
            local playerName = UnitName(unit)
            local targetName

            if self.RebirthTargets[playerName] then
                targetName = self.RebirthTargets[playerName]
                self.RebirthTargets[playerName] = nil
            end

            if self.spells[spellID] then
                self:SendCommMessage("HomeCheck", self:Serialize(spellID, playerName, targetName), "RAID")
            end

            if self:getCDLeft(playerName, spellID) == 0 then
                self:setCooldown(spellID, playerName, true, targetName)
            end
        end
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        self:removePlayersNotInRaid()
        self:scanRaid()
    elseif event == "PARTY_MEMBER_DISABLE" and not UnitInRaid("player") then
        self:removePlayersNotInRaid()
        self:scanRaid()
    elseif event == "PARTY_MEMBER_ENABLE" and not UnitInRaid("player") then
        self:removePlayersNotInRaid()
        self:scanRaid()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:cacheLocalizedSpellNames()
        self:ScheduleTimer(function()
            self:scanRaid()
        end, 2)
        self:ScheduleTimer(function()
            self:scanRaid()
        end, 10)
        self:ScheduleTimer(function()
            self:scanRaid()
        end, 30)
    elseif event == "ADDON_LOADED" then
        if (...) ~= "HomeCheck" then
            return
        end
        self.db = LibStub("AceDB-3.0"):New("HomeCheck_DB", self.defaults, true)

        if self.db.global.db_ver ~= self.db_ver then
            if self.db.global.db_ver == 1 and self.db_ver == 2 then
                -- upgrading db

                local function tablecopy(t, copyto)
                    for k, v in pairs(t) do
                        if type(v) == "table" then
                            copyto[k] = tablecopy(v, copyto[k])
                        else
                            copyto[k] = v
                        end
                    end
                    return copyto
                end

                for k, v in pairs(self.db.global) do
                    if k ~= "db_ver" and k ~= "CDs" and k ~= "comms" then
                        self.db.profile[k], self.db.global[k] = tablecopy(v, self.db.profile[k]), nil
                    end
                end
            else
                -- unknown db version, resetting db to defaults
                self.db:ResetDB("Default")
            end
            self.db.global.db_ver = self.db_ver
        end

        for playerName, spells in pairs(self.db.global.CDs) do
            for spellID, cd in pairs(spells) do
                if cd.timestamp < time() then
                    table.wipe(self.db.global.CDs[playerName][spellID])
                end
            end
        end

        for i = 1, groups do
            self:getGroup(i)
        end

        self.db.RegisterCallback(self, "OnProfileChanged", "loadProfile")
        self.db.RegisterCallback(self, "OnProfileCopied", "loadProfile")
        self.db.RegisterCallback(self, "OnProfileReset", "loadProfile")

        self:OptionsPanel()

        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self:RegisterEvent("UNIT_SPELLCAST_SENT")
        self:RegisterEvent("UNIT_SPELLCAST_FAILED")
        self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        self:RegisterEvent("RAID_ROSTER_UPDATE")
        self:RegisterEvent("PARTY_MEMBERS_CHANGED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PARTY_MEMBER_ENABLE")
        self:RegisterEvent("PARTY_MEMBER_DISABLE")
        self.LibGroupTalents.RegisterCallback(self, "LibGroupTalents_Update")

        for k, _ in pairs(self.comms) do
            if self.db.global.comms[k] then
                self:RegisterComm(k)
            end
        end

        self:ScheduleRepeatingTimer(function()
            for playerName, _ in pairs(self.deadUnits) do
                if not UnitIsDeadOrGhost(playerName) or (not UnitInRaid(playerName) and not UnitInParty(playerName)) then
                    self.deadUnits[playerName] = nil
                end
            end

            for i = 1, #self.groups do
                for j = 1, #self.groups[i].CooldownFrames do
                    self:setTimerColor(self.groups[i].CooldownFrames[j])
                    self:updateRange(self.groups[i].CooldownFrames[j])
                end
            end
        end, 1)
    end
end)

function HomeCheck:OnCommReceived(...)
    local prefix, message, _, sender = ...

    if sender == (UnitName("player")) then
        return
    end

    local success, messageType, spellID, spellName, playerName, CDLeft, target
    if prefix == "oRA3" then
        success, messageType, spellID, CDLeft, target = self:Deserialize(message)

        if not success then
            return
        end

        if type(messageType) ~= "string" or messageType ~= "Cooldown" then
            return
        end
    elseif prefix == "BLT" then
        if not string.find(message, ":") then
            return
        end

        messageType, message = strsplit(":", message)
        if messageType ~= "CD" then
            return
        end

        if not string.find(message, ";") then
            return
        end

        playerName, spellName, spellID, target = strsplit(";", message)
    elseif prefix == "oRA" or prefix == "CTRA" then
        spellID, CDLeft = select(3, message:find("CD (%d) (%d+)"))
    elseif prefix == "RCD2" then
        spellID, CDLeft = select(3, message:find("(%d+) (%d+)"))
    elseif prefix == "FRCD3S" then
        spellID, playerName, CDLeft, target = select(3, message:find("(%d+)(%a+)(%d+)(%a*)"))
    elseif prefix == "FRCD3" then
        playerName = tostring(sender)
        if not UnitInRaid(playerName) and not UnitInParty(playerName) then
            return
        end

        for w in string.gmatch(message, "([^,]*),") do
            spellID, CDLeft = select(3, w:find("(%d+)-(%d+)"))
            spellID = tonumber(spellID)
            CDLeft = tonumber(CDLeft)

            if not spellID or not CDLeft then
                return
            end

            if not self.spells[spellID] then
                local spellName = GetSpellInfo(spellID)
                if spellName then
                    spellID = self.localizedSpellNames[spellName]
                end
            end

            if spellID and self.db.profile.spells[spellID].enable and self:getCDLeft(playerName, spellID) == 0 then
                self:setCooldown(spellID, playerName, CDLeft)
            end
        end
        return
    elseif prefix == "HomeCheck" then
        success, spellID, playerName, target = self:Deserialize(message)
        if not success then
            return
        end
    end

    if not spellID then
        return
    end

    playerName = playerName and tostring(playerName) or sender

    if not UnitInRaid(playerName) and not UnitInParty(playerName) then
        return
    end

    spellID = tonumber(spellID)

    CDLeft = CDLeft and tonumber(CDLeft)

    if not CDLeft then
        CDLeft = true
    elseif CDLeft <= 0 and not self.db.profile.spells[spellID].alwaysShow then
        return
    end

    if prefix == "oRA" then
        if spellID == 1 then
            spellID = 48477 -- Rebirth
        elseif spellID == 2 then
            spellID = 21169 -- Reincarnation
        elseif spellID == 3 then
            spellID = 47883 -- Soulstone Resurrection
        elseif spellID == 4 then
            spellID = 19752 -- Divine Intervention
        end
    elseif prefix == "BLT" then
        if spellID == 57934 then
            spellID = 59628
        elseif spellID == 34477 then
            spellID = 35079
        end
    end

    if spellID == 23983 then
        -- Readiness
        --self:Readiness(playerName)
        return
    elseif spellID == 34477 then
        -- Misdirection initial cast
        if self.db.profile.spells[35079].enable and self:getCDLeft(playerName, 35079) == 0 then
            self:setCooldown(35079, playerName, 60, target)
        end
        return
    elseif spellID == 57934 then
        -- Tricks of the Trade initial cast
        if self.db.profile.spells[59628].enable and self:getCDLeft(playerName, 59628) == 0 then
            self:setCooldown(59628, playerName, 60, target)
        end
        return
    end

    if not self.spells[spellID] then
        if not spellName then
            spellName = GetSpellInfo(spellID)
        end
        if spellName then
            spellID = self.localizedSpellNames[spellName]
        end
    end

    if not self.spells[spellID] or not self.db.profile.spells[spellID].enable then
        return
    end

    if prefix == "RCD2" and CDLeft == 0 and not self:UnitHasAbility(playerName, spellID) then
        return
    end

    if self:getCDLeft(playerName, spellID) ~= 0 then
        return
    end

    if target then
        if target == "" then
            target = nil
        else
            target = tostring(target)
        end
    end

    self:setCooldown(spellID, playerName, CDLeft, target)
end

function HomeCheck:setCooldown(spellID, playerName, CDLeft, target, source)
    if not spellID or not self.spells[spellID] or not self.db.profile.spells[spellID].enable then
        return
    end

    if CDLeft == true then
        CDLeft = self:getSpellCooldown(spellID, playerName)
    end

    local currentCD = self:getCDLeft(playerName, spellID)
    if currentCD ~= 0 then
        print("overwriting " .. playerName .. " " .. (GetSpellInfo(spellID)) .. " CD " .. currentCD .. "->" .. tostring(CDLeft) .. " (" .. tostring(source) .. ")")
    end

    local frame = self:createCooldownFrame(playerName, spellID)

    if not CDLeft then
        if self.db.global.CDs[playerName][spellID].timestamp and self.db.global.CDs[playerName][spellID].timestamp > time() then
            -- restoring CD info from SV
            CDLeft = self.db.global.CDs[playerName][spellID].timestamp - time()
            target = self.db.global.CDs[playerName][spellID].target
        end
    else
        self.db.global.CDs[playerName][spellID].timestamp = time() + CDLeft
    end

    if CDLeft then
        frame.CDLeft = CDLeft
    end

    self:sortFrames(self.db.profile.spells[spellID].group)

    self:updateCooldownBarProgress(frame)

    if frame.CDLeft > 0 then
        frame.timerFontString:SetText(date("!%M:%S", frame.CDLeft):gsub('^0+:?0?', ''))

        if not frame.CDtimer then
            local tick = 0.1
            frame.CDtimer = self:ScheduleRepeatingTimer(function(frame)
                if frame.CDLeft > 0 then
                    frame.CDLeft = frame.CDLeft - tick
                    frame.CDLeft = tonumber((("%%.%df"):format(1)):format(frame.CDLeft))
                end

                self:updateCooldownBarProgress(frame)

                if frame.CDLeft <= 0 then
                    self:CancelTimer(frame.CDtimer)
                    frame.CDtimer = nil
                    if not self.db.profile.spells[spellID].alwaysShow then
                        self:removeCooldownFrames(playerName, spellID)
                        self:repositionFrames(self.db.profile.spells[spellID].group)
                    else
                        frame.timerFontString:SetText("R")
                        self:setTimerColor(frame)
                    end
                elseif frame.CDLeft == floor(frame.CDLeft) then
                    frame.timerFontString:SetText(date("!%M:%S", frame.CDLeft):gsub('^0+:?0?', ''))
                    self:setTimerColor(frame)
                end
            end, tick, frame)
        end
    else
        frame.timerFontString:SetText("R")
    end

    self:setTimerColor(frame)

    if target then
        self.db.global.CDs[playerName][spellID].target = target
        frame.targetFontString:SetText(target)
        local class = select(2, UnitClass(target))
        if class then
            local targetClassColor = RAID_CLASS_COLORS[class]
            frame.targetFontString:SetTextColor(targetClassColor.r, targetClassColor.g, targetClassColor.b, 1)
        end
    end
end

function HomeCheck:createCooldownFrame(playerName, spellID)
    local group = self:getGroup(self.db.profile.spells[spellID].group)
    for i = 1, #group.CooldownFrames do
        if group.CooldownFrames[i].playerName == playerName and group.CooldownFrames[i].spellID == spellID then
            return group.CooldownFrames[i]
        end
    end

    local frame = CreateFrame("Frame", nil, group)

    frame.playerName = playerName
    frame.spellID = spellID
    frame.CDLeft = 0
    frame.class = select(2, UnitClass(playerName))

    frame.iconFrame = CreateFrame("Frame", nil, frame)
    frame.iconFrame:SetPoint("LEFT")
    local icon = select(3, GetSpellInfo(spellID))
    if icon then
        frame.iconFrame.texture = frame.iconFrame:CreateTexture(nil, "OVERLAY")
        frame.iconFrame.texture:SetTexture(icon)
        frame.iconFrame.texture:SetAllPoints()
        frame.iconFrame.texture:SetPoint("CENTER")
    end

    frame.bar = CreateFrame("Frame", nil, frame)
    frame.bar:SetPoint("LEFT", frame.iconFrame, "RIGHT")
    frame.bar.texture = frame.bar:CreateTexture(nil, "ARTWORK")
    frame.bar.texture:SetAllPoints()
    self:updateRange(frame)

    frame.inactiveBar = CreateFrame("Frame", nil, frame)
    frame.inactiveBar.texture = frame.inactiveBar:CreateTexture(nil, "BACKGROUND")
    frame.inactiveBar.texture:SetAllPoints()
    frame.inactiveBar:SetPoint("BOTTOMRIGHT")

    frame.playerNameFontString = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.playerNameFontString:SetText(frame.playerName)
    frame.playerNameFontString:SetTextColor(1, 1, 1, 1)

    frame.targetFontString = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.targetFontString:SetPoint("LEFT", frame.playerNameFontString, "RIGHT", 1, 0)

    frame.timerFontString = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")

    self:applyGroupSettings(frame)

    table.insert(group.CooldownFrames, frame)
    return frame
end

function HomeCheck:repositionFrames(groupIndex)
    if not groupIndex then
        for i = 1, #self.groups do
            self:repositionFrames(i)
        end
        return
    end
    for j = 1, #self.groups[groupIndex].CooldownFrames do
        self.groups[groupIndex].CooldownFrames[j]:SetPoint("TOPLEFT", 0, -(self.db.profile[self.db.profile[groupIndex].inherit or groupIndex].iconSize + self.db.profile[self.db.profile[groupIndex].inherit or groupIndex].padding) * (j - 1))
    end
end

function HomeCheck:loadProfile()
    for i = 1, #self.groups do
        self.groups[i]:ClearAllPoints()
        self.groups[i]:SetPoint(self.db.profile[i].pos.point, self.db.profile[i].pos.relativeTo, self.db.profile[i].pos.relativePoint, self.db.profile[i].pos.xOfs, self.db.profile[i].pos.yOfs)
    end
    self:scanRaid()
end

function HomeCheck:removeCooldownFrames(playerName, spellID, onlyWhenReady, startGroup, startIndex)
    if spellID then
        startGroup = self.db.profile.spells[spellID].group
    end
    for i = startGroup or 1, #self.groups do
        for j = startIndex or 1, #self.groups[i].CooldownFrames do
            if self.groups[i].CooldownFrames[j].playerName == playerName and (not spellID or self.groups[i].CooldownFrames[j].spellID == spellID) and (not onlyWhenReady or self.groups[i].CooldownFrames[j].CDLeft <= 0) then
                self.groups[i].CooldownFrames[j]:Hide()
                if self.groups[i].CooldownFrames[j].CDtimer then
                    self:CancelTimer(self.groups[i].CooldownFrames[j].CDtimer)
                end
                table.remove(self.groups[i].CooldownFrames, j)
                if spellID then
                    break
                end
                return self:removeCooldownFrames(playerName, spellID, onlyWhenReady, i, j)
            end
        end
    end
end

function HomeCheck:removePlayersNotInRaid(startGroup, startIndex)
    for i = startGroup or 1, #self.groups do
        for j = startIndex or 1, #self.groups[i].CooldownFrames do
            if not UnitInRaid(self.groups[i].CooldownFrames[j].playerName) and not UnitInParty(self.groups[i].CooldownFrames[j].playerName) or not UnitIsConnected(self.groups[i].CooldownFrames[j].playerName) then
                self:removeCooldownFrames(self.groups[i].CooldownFrames[j].playerName)
                return self:removePlayersNotInRaid(i, j)
            end
        end
    end
end

function HomeCheck:scanRaid()
    if GetNumRaidMembers() > 0 then
        for i = 1, 40 do
            local playerName, _, _, _, _, class, _, online, isDead = GetRaidRosterInfo(i)
            if isDead then
                self.deadUnits[playerName] = true
            end
            if playerName and online then
                self:refreshPlayerCooldowns(playerName, class)
            end
        end
    else
        self:refreshPlayerCooldowns((UnitName("player")))
        for i = 1, GetNumPartyMembers() do
            self:refreshPlayerCooldowns((UnitName("party" .. i)))
        end
    end
    self:repositionFrames()
end

function HomeCheck:refreshPlayerCooldowns(playerName, class)
    if not class then
        class = select(2, UnitClass(playerName))
    end

    for spellID, spellConfig in pairs(self.spells) do
        if not spellConfig.class or spellConfig.class == class then
            if self.db.profile.spells[spellID] and self.db.profile.spells[spellID].enable and self:UnitHasAbility(playerName, spellID) then
                if self.db.profile.spells[spellID].alwaysShow then
                    self:setCooldown(spellID, playerName)
                else
                    self:removeCooldownFrames(playerName, spellID, true)
                end
            else
                self:removeCooldownFrames(playerName, spellID)
            end
        end
    end
end

function HomeCheck:UnitHasAbility(playerName, spellID)
    return not self.spells[spellID].talentTab or not self.spells[spellID].talentIndex or self.LibGroupTalents:UnitHasTalent(playerName, (GetSpellInfo(spellID)))
end

function HomeCheck:saveFramePosition(groupIndex)
    local point, relativeTo, relativePoint, xOfs, yOfs = self.groups[groupIndex]:GetPoint(0)
    self.db.profile[groupIndex].pos = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName(),
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
end

function HomeCheck:Readiness(hunterName)
    for i = 1, #self.groups do
        for j = 1, #self.groups[i].CooldownFrames do
            if self.groups[i].CooldownFrames[j].playerName == hunterName then
                self:setCooldown(self.groups[i].CooldownFrames[j].spellID, hunterName, 0)
            end
        end
    end
end

function HomeCheck:sortFrames(groupIndex)
    if not groupIndex then
        for i = 1, #self.groups do
            self:sortFrames(i)
        end
        return
    end

    for j = 1, #self.groups[groupIndex].CooldownFrames - 1 do
        for k = j + 1, #self.groups[groupIndex].CooldownFrames do
            if self:cooldownSorter(self.groups[groupIndex].CooldownFrames[j], self.groups[groupIndex].CooldownFrames[k]) then
                self.groups[groupIndex].CooldownFrames[j], self.groups[groupIndex].CooldownFrames[k] = self.groups[groupIndex].CooldownFrames[k], self.groups[groupIndex].CooldownFrames[j]
            end
        end
    end
    self:repositionFrames(groupIndex)
end

---cooldownSorter
---@param frame1 table cooldown frame to be moved
---@param frame2 table cooldown frame to compare against
---@return boolean true if frame1 should be below frame2
function HomeCheck:cooldownSorter(frame1, frame2)
    local groupIndex = self.db.profile.spells[frame1.spellID].group
    if frame1.inRange < frame2.inRange then
        if self.db.profile[self.db.profile[groupIndex].inherit or groupIndex].rangeUngroup then
            return true
        elseif frame1.spellID == frame2.spellID and self.db.profile[self.db.profile[groupIndex].inherit or groupIndex].rangeDimout then
            return true
        end
    elseif frame1.inRange > frame2.inRange then
        if self.db.profile[self.db.profile[groupIndex].inherit or groupIndex].rangeUngroup or frame1.spellID == frame2.spellID then
            return
        end
    end

    if self.db.profile.spells[frame1.spellID].priority < self.db.profile.spells[frame2.spellID].priority then
        return true
    elseif frame1.spellID == frame2.spellID then
        if frame1.CDLeft > frame2.CDLeft then
            return true
        end
    elseif self.db.profile.spells[frame1.spellID].priority == self.db.profile.spells[frame2.spellID].priority and frame1.spellID < frame2.spellID then
        -- attempt to group spells by ID
        return true
    end
end

function HomeCheck:groupSpells()
    for i = 1, #self.groups do
        for j = 1, #self.groups[i].CooldownFrames do

        end
    end
end

function HomeCheck:GSTriggered(playerName)
    for i = 1, #self.groups[self.db.profile.spells[47788].group].CooldownFrames do
        if self.groups[self.db.profile.spells[47788].group].CooldownFrames[i].playerName == playerName and self.groups[self.db.profile.spells[47788].group].CooldownFrames[i].spellID == 47788 then
            if self.groups[self.db.profile.spells[47788].group].CooldownFrames[i].CDLeft <= self.spells[47788].cd then
                self.groups[self.db.profile.spells[47788].group].CooldownFrames[i].CDLeft = self.groups[self.db.profile.spells[47788].group].CooldownFrames[i].CDLeft + 110
                self:sortFrames(self.db.profile.spells[47788].group)
            end
            return
        end
    end
end

function HomeCheck:getGroup(i)
    i = i or 1
    if self.groups[i] then
        return self.groups[i]
    end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:ClearAllPoints()
    frame:SetPoint(self.db.profile[i].pos.point, self.db.profile[i].pos.relativeTo, self.db.profile[i].pos.relativePoint, self.db.profile[i].pos.xOfs, self.db.profile[i].pos.yOfs)
    frame:SetSize(20, 20)
    frame:SetScript("OnDragStart", function(s)
        s:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        self:saveFramePosition(i)
    end)
    frame.CooldownFrames = {}

    table.insert(self.groups, frame)
    return frame
end

function HomeCheck:getCDLeft(playerName, spellID)
    for i = 1, #self.groups[self.db.profile.spells[spellID].group].CooldownFrames do
        if playerName == self.groups[self.db.profile.spells[spellID].group].CooldownFrames[i].playerName
                and spellID == self.groups[self.db.profile.spells[spellID].group].CooldownFrames[i].spellID then
            return self.groups[self.db.profile.spells[spellID].group].CooldownFrames[i].CDLeft
        end
    end
    return 0
end

function HomeCheck:updateRange(frame)
    if not frame.inRange then
        frame.inRange = self:UnitInRange(frame.playerName) and 1 or 0
        self:setBarColor(frame)
        self:sortFrames()
    elseif frame.inRange == 1 then
        if not self:UnitInRange(frame.playerName) then
            frame.inRange = 0
            if self.db.profile[self.db.profile[self.db.profile.spells[frame.spellID].group].inherit or self.db.profile.spells[frame.spellID].group].rangeDimout then
                self:setBarColor(frame)
            end
            self:sortFrames()
        end
    elseif self:UnitInRange(frame.playerName) then
        frame.inRange = 1
        if self.db.profile[self.db.profile[self.db.profile.spells[frame.spellID].group].inherit or self.db.profile.spells[frame.spellID].group].rangeDimout then
            self:setBarColor(frame)
        end
        self:sortFrames()
    end
end

---@param frame table
function HomeCheck:setBarColor(frame)
    if frame.inRange == 1 or not self.db.profile[self.db.profile[self.db.profile.spells[frame.spellID].group].inherit or self.db.profile.spells[frame.spellID].group].rangeDimout then
        local playerClassColor = RAID_CLASS_COLORS[frame.class]
        frame.bar.texture:SetVertexColor(playerClassColor.r, playerClassColor.g, playerClassColor.b, self.db.profile[self.db.profile.spells[frame.spellID].group].opacity)
    else
        frame.bar.texture:SetVertexColor(0.5, 0.5, 0.5, self.db.profile[self.db.profile.spells[frame.spellID].group].opacity)
    end
end

function HomeCheck:setTimerColor(frame)
    if self.deadUnits[frame.playerName] then
        frame.timerFontString:SetTextColor(1, 0, 0, 1)
    elseif frame.CDLeft <= 0 then
        if self.db.profile.spells[frame.spellID].alwaysShow then
            frame.timerFontString:SetTextColor(0, 1, 0, 1)
        end
    else
        frame.timerFontString:SetTextColor(0.9, 0.7, 0, 1)
    end
end

function HomeCheck:getSpellCooldown(spellID, playerName)
    local CDmodifier = 0
    if spellID == 498 or spellID == 642 then
        -- Divine Shield and Divine Protection
        CDmodifier = -30 * (select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 14)) or 0)
    elseif spellID == 10278 then
        -- HoP
        CDmodifier = -60 * (select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 4)) or 0)
    elseif spellID == 48788 then
        -- Lay on Hands
        CDmodifier = -120 * (select(5, self.LibGroupTalents:GetTalentInfo(playerName, 1, 8)) or 0)
        if self.LibGroupTalents:UnitHasGlyph(playerName, 57955) then
            CDmodifier = CDmodifier - 300
        end
    elseif spellID == 20608 then
        -- Reincarnation
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 3, 3))
        if talentPoints == 1 then
            CDmodifier = -420
        elseif talentPoints == 2 then
            CDmodifier = -900
        end
    elseif spellID == 871 then
        -- Shield Wall
        -- TODO verify spell and glyph ID
        CDmodifierad = -30 * (select(5, self.LibGroupTalents:GetTalentInfo(playerName, 3, 13)) or 0)
        if self.LibGroupTalents:UnitHasGlyph(playerName, 63329) then
            CDmodifier = CDmodifier - 120
        end
    elseif spellID == 12975 then
        -- Last Stand
        -- TODO verify spell and glyph IDs
        if self.LibGroupTalents:UnitHasGlyph(playerName, 58376) then
            CDmodifier = CDmodifier - 60
        end
    elseif spellID == 48447 then
        -- Tranquility
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 3, 14))
        if talentPoints == 1 then
            CDmodifier = -(self.spells[spellID] and self.spells[spellID].cd or 0) * 0.3
        elseif talentPoints == 2 then
            CDmodifier = -(self.spells[spellID] and self.spells[spellID].cd or 0) * 0.5
        end
    elseif spellID == 47585 then
        -- Dispersion
        if self.LibGroupTalents:UnitHasGlyph(playerName, 63229) then
            CDmodifier = CDmodifier - 45
        end
    elseif spellID == 45438 then
        -- Ice Block
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(playerName, 3, 3))
        if talentPoints == 1 then
            CDmodifier = -(self.spells[spellID] and self.spells[spellID].cd or 0) * 0.07
        elseif talentPoints == 2 then
            CDmodifier = -(self.spells[spellID] and self.spells[spellID].cd or 0) * 0.14
        elseif talentPoints == 3 then
            CDmodifier = -(self.spells[spellID] and self.spells[spellID].cd or 0) * 0.2
        end
    elseif spellID == 66 or spellID == 12051 then
        -- Invisibility or Evocation
        CDmodifier = -(self.spells[spellID] and self.spells[spellID].cd or 0) * 0.15 * (select(5, self.LibGroupTalents:GetTalentInfo(playerName, 1, 24)) or 0)
    elseif spellID == 12292 then
        -- Death Wish
        CDmodifier = -(self.spells[spellID] and self.spells[spellID].cd or 0) * 0.11 * (select(5, self.LibGroupTalents:GetTalentInfo(playerName, 2, 18)) or 0)
    elseif spellID == 10060 then
        CDmodifier = -(self.spells[spellID] and self.spells[spellID].cd or 0) * 0.1 * (select(5, self.LibGroupTalents:GetTalentInfo(playerName, 1, 23)) or 0)
    end

    return self.spells[spellID].cd + CDmodifier
end

function HomeCheck:cacheLocalizedSpellNames()
    for spellID, _ in pairs(self.spells) do
        local spellName = GetSpellInfo(spellID)
        self.localizedSpellNames[spellName] = spellID
    end
end

function HomeCheck:applyGroupSettings(frame, groupIndex)
    groupIndex = groupIndex or self.db.profile.spells[frame.spellID].group
    frame:SetParent(self:getGroup(groupIndex))

    groupIndex = self.db.profile[groupIndex].inherit or groupIndex
    frame:SetSize(self.db.profile[groupIndex].frameWidth, self.db.profile[groupIndex].iconSize)
    frame.iconFrame:SetSize(self.db.profile[groupIndex].iconSize, self.db.profile[groupIndex].iconSize)
    frame.playerNameFontString:SetFont(self.LibSharedMedia:Fetch("font", self.db.profile[groupIndex].fontPlayer), self.db.profile[groupIndex].fontSize)
    frame.targetFontString:SetFont(self.LibSharedMedia:Fetch("font", self.db.profile[groupIndex].fontTarget), self.db.profile[groupIndex].fontSizeTarget)
    frame.targetFontString:SetJustifyH(self.db.profile[groupIndex].targetJustify == "l" and "LEFT" or "RIGHT")
    frame.bar:SetSize(self.db.profile[groupIndex].frameWidth - self.db.profile[groupIndex].iconSize, self.db.profile[groupIndex].iconSize)
    frame.bar.texture:SetTexture(self.LibSharedMedia:Fetch("statusbar", self.db.profile[groupIndex].statusbar))
    frame.inactiveBar.texture:SetTexture(self.LibSharedMedia:Fetch("statusbar", self.db.profile[groupIndex].statusbar))
    frame.inactiveBar.texture:SetVertexColor(unpack(self.db.profile[groupIndex].background))
    frame.timerFontString:SetFont(self.LibSharedMedia:Fetch("font", self.db.profile[groupIndex].fontTimer), self.db.profile[groupIndex].fontSizeTimer)

    self:setTimerPosition(frame)
end

function HomeCheck:setSpellGroupIndex(spellID, groupIndex, startIndex)
    if self.db.profile.spells[spellID].group == groupIndex then
        return
    end
    for i = startIndex or 1, #self.groups[self.db.profile.spells[spellID].group].CooldownFrames do
        if spellID == self.groups[self.db.profile.spells[spellID].group].CooldownFrames[i].spellID then
            local frame = table.remove(self.groups[self.db.profile.spells[spellID].group].CooldownFrames, i)
            self:applyGroupSettings(frame, groupIndex)
            table.insert(self.groups[groupIndex].CooldownFrames, frame)
            return self:setSpellGroupIndex(spellID, groupIndex, i)
        end
    end
    self:sortFrames(self.db.profile.spells[spellID].group)
    self:sortFrames(groupIndex)
    self.db.profile.spells[spellID].group = groupIndex
end

function HomeCheck:UnitInRange(unit)
    return select(2, self.LibRangeCheck:GetRange(unit))
end

function HomeCheck:updateCooldownBarProgress(frame)
    local pct = min(frame.CDLeft / self:getSpellCooldown(frame.spellID, frame.playerName), 1)
    if self.db.profile[self.db.profile[self.db.profile.spells[frame.spellID].group].inherit or self.db.profile.spells[frame.spellID].group].invertColors then
        if pct ~= 0 then
            if not frame.bar.texture:IsShown() then
                frame.bar.texture:Show()
                frame.inactiveBar:SetPoint("TOPLEFT", frame.bar, "TOPRIGHT")
            end
            frame.bar:SetWidth((self.db.profile[self.db.profile[self.db.profile.spells[frame.spellID].group].inherit or self.db.profile.spells[frame.spellID].group].frameWidth - self.db.profile[self.db.profile[self.db.profile.spells[frame.spellID].group].inherit or self.db.profile.spells[frame.spellID].group].iconSize) * pct)
        elseif frame.bar.texture:IsShown() then
            frame.bar.texture:Hide()
            frame.inactiveBar:SetPoint("TOPLEFT", frame.iconFrame, "TOPRIGHT")
        end
    else
        if pct ~= 1 then
            if not frame.bar.texture:IsShown() then
                frame.bar.texture:Show()
                frame.inactiveBar:SetPoint("TOPLEFT", frame.bar, "TOPRIGHT")
            end
            frame.bar:SetWidth((self.db.profile[self.db.profile[self.db.profile.spells[frame.spellID].group].inherit or self.db.profile.spells[frame.spellID].group].frameWidth - self.db.profile[self.db.profile[self.db.profile.spells[frame.spellID].group].inherit or self.db.profile.spells[frame.spellID].group].iconSize) * (1 - pct))
        elseif frame.bar.texture:IsShown() then
            frame.bar.texture:Hide()
            frame.inactiveBar:SetPoint("TOPLEFT", frame.iconFrame, "TOPRIGHT")
        end
    end
end

function HomeCheck:setTimerPosition(frame)
    if self.db.profile[self.db.profile[self.db.profile.spells[frame.spellID].group].inherit or self.db.profile.spells[frame.spellID].group].timerPosition == "l" then
        frame.timerFontString:ClearAllPoints()
        frame.timerFontString:SetPoint("LEFT", frame.iconFrame, "RIGHT", 1, 0)
        frame.playerNameFontString:SetPoint("LEFT", frame.timerFontString, "RIGHT", 2, 0)
        frame.targetFontString:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    else
        frame.timerFontString:ClearAllPoints()
        frame.timerFontString:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
        frame.playerNameFontString:SetPoint("LEFT", frame.iconFrame, "RIGHT", 1, 0)
        frame.targetFontString:SetPoint("RIGHT", frame.timerFontString, "LEFT", -1, 0)
    end
end