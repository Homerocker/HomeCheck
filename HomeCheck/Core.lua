local CanInspect = CanInspect
local CheckInteractDistance = CheckInteractDistance
local date = date
local floor = floor
local GetInventoryItemID = GetInventoryItemID
local GetItemInfo = GetItemInfo
local GetNumPartyMembers = GetNumPartyMembers
local GetNumRaidMembers = GetNumRaidMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetSpellInfo = GetSpellInfo
local GetTime = GetTime
local pairs = pairs
local select = select
local find = string.find
local gmatch = gmatch
local strsplit = strsplit
local insert = table.insert
local ipairs = ipairs
local random = random
local remove = table.remove
local wipe = table.wipe
local time = time
local tonumber = tonumber
local tostring = tostring
local type = type
local UnitClass = UnitClass
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitName = UnitName
local unpack = unpack

HomeCheck = CreateFrame("Frame")

HomeCheck.LibGroupTalents = LibStub("LibGroupTalents-1.0")
HomeCheck.LibSharedMedia = LibStub("LibSharedMedia-3.0")
HomeCheck.LibRangeCheck = LibStub("LibRangeCheck-2.0")

LibStub("AceTimer-3.0"):Embed(HomeCheck)
LibStub("AceComm-3.0"):Embed(HomeCheck)
LibStub("AceSerializer-3.0"):Embed(HomeCheck)

HomeCheck.groups = {}
HomeCheck.localizedSpellNames = {}
HomeCheck.units = {}
HomeCheck.db_ver = 6

local RebirthTarget

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

local currentPlayer = UnitName("player")
local playerInRaid = UnitInRaid("player")

local updateRaidRosterCooldown = 2
local updateRaidRosterTimestamp
local updateRaidRosterScheduleTimer

local childSpells = {}

-- bars that were removed, waiting to be handed out again
local framePool = {}

local groups = 10

HomeCheck:RegisterEvent("ADDON_LOADED")

function HomeCheck:LibGroupTalents_Update(...)
    self:refreshPlayerCooldowns((UnitName((select(3, ...)))))
    self:repositionFrames()
end

function HomeCheck:LibGroupTalents_RoleChange(...)
    self:LibGroupTalents_Update(...)
end

-- the only combat log events this addon acts on
local combatLogEvents = {
    SPELL_CAST_SUCCESS = true,
    SPELL_RESURRECT = true,
    SPELL_AURA_APPLIED = true,
    SPELL_AURA_REMOVED = true,
    SPELL_HEAL = true,
    UNIT_DIED = true,
    SPELL_INSTAKILL = true
}

HomeCheck:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, combatEvent, _, playerName, _, _, targetName, _, spellID, spellName = ...

        -- The combat log fires thousands of times a second in a raid, and all
        -- but a handful of those events mean nothing here. Both tests below are
        -- table lookups, and they come before the roster calls, which search
        -- the raid by name and are the expensive part.
        if not combatLogEvents[combatEvent] then
            return
        end

        if combatEvent == "UNIT_DIED" or combatEvent == "SPELL_INSTAKILL" then
            playerName = targetName
        else
            if not self.spells[spellID] then
                spellID = self.localizedSpellNames[spellName]
            end
            if not spellID then
                -- a spell nobody here tracks
                return
            end
        end

        if not UnitInRaid(playerName) and not UnitInParty(playerName) then
            return
        end

        if combatEvent == "SPELL_CAST_SUCCESS" or combatEvent == "SPELL_RESURRECT" then
            -- don't evaluate "nocast" as it should only be set to true for spells that do not trigger SPELL_CAST_SUCCESS
            -- (assume nocast=nil at this point)
            self:setCooldown(spellID, playerName, true, targetName)
        elseif combatEvent == "SPELL_AURA_APPLIED" then
            if self.spells[spellID] and self.spells[spellID].nocast then
                -- evaluate nocast to skip spells that also trigger SPELL_CAST_SUCCESS (prevent double cooldown trigger)
                self:setCooldown(spellID, playerName, true, targetName)
            end
        elseif combatEvent == "SPELL_AURA_REMOVED" then
            if spellID == 34477 then
                -- Misdirection cancelled
                self:setCooldown(35079, playerName, true)
            elseif spellID == 57934 then
                -- Tricks of the Trade cancelled
                self:setCooldown(59628, playerName, true)
            end
        elseif combatEvent == "SPELL_HEAL" then
            if spellID == 48153 then
                -- Guardian Spirit proced
                self:GSProc(targetName)
            end
        elseif combatEvent == "UNIT_DIED" or combatEvent == "SPELL_INSTAKILL" then
            self:getUnit(playerName).dead = true
        end

        -- UNIT_SPELLCAST events are used to detect double Rebirth only
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, spellName, _, targetName = ...
        if self.localizedSpellNames[spellName] == 48477 then
            RebirthTarget = targetName
        end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        local unit, spellName = ...
        if self.localizedSpellNames[spellName] == 48477 and unit == "player" then
            RebirthTarget = nil
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, spellName = ...
        if self.localizedSpellNames[spellName] == 48477 then
            self:setCooldown(48477, (UnitName(unit)), true, unit == "player" and RebirthTarget)
            if unit == "player" then
                RebirthTarget = nil
            end
        end
    elseif event == "RAID_ROSTER_UPDATE" then
        local instant
        if playerInRaid ~= UnitInRaid("player") then
            -- current player joined/left raid
            if playerInRaid then
                -- player was in raid (left raid)
                self:RegisterEvent("PARTY_MEMBERS_CHANGED")
            else
                self:UnregisterEvent("PARTY_MEMBERS_CHANGED")
                instant = true
            end
            -- updating raid status
            playerInRaid = UnitInRaid("player")
        end
        if playerInRaid then
            self:updateRaidRoster(instant)
        end
    elseif event == "PARTY_MEMBERS_CHANGED" then
        self:updateRaidRoster()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:cacheLocalizedSpellNames()
        self:ScheduleTimer(function()
            self:updateRaidCooldowns()
        end, 2)
        self:ScheduleTimer(function()
            self:updateRaidCooldowns()
        end, 10)
        self:ScheduleTimer(function()
            self:updateRaidCooldowns()
        end, 30)

        -- Initialize test mode if it was enabled
        if self.db.global.testMode then
            self:setTestMode(true)
        end
    elseif event == "ADDON_LOADED" then
        if (...) ~= "HomeCheck" then
            return
        end
        self.db = LibStub("AceDB-3.0"):New("HomeCheck_DB", self.defaults, true)

        self:upgradeDB()

        local current_time = time()
        for playerName, spells in pairs(self.db.global.CDs) do
            for spellID, cd in pairs(spells) do
                if not cd.timestamp or cd.timestamp < current_time then
                    wipe(self.db.global.CDs[playerName][spellID])
                end
            end
        end

        for childSpellID, childSpellConfig in pairs(self.spells) do
            if childSpellConfig.parent then
                childSpells[childSpellConfig.parent] = childSpellID
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
        if not playerInRaid then
            self:RegisterEvent("PARTY_MEMBERS_CHANGED")
        end
        self:RegisterEvent("PLAYER_ENTERING_WORLD")

        self.LibGroupTalents.RegisterCallback(self, "LibGroupTalents_Update")
        self.LibGroupTalents.RegisterCallback(self, "LibGroupTalents_RoleChange")

        for k, _ in pairs(self.comms) do
            if self.db.global.comms[k] then
                self:RegisterComm(k)
            end
        end

        self:ScheduleRepeatingTimer(function()
            if not self.db.global.testMode then
                for playerName, _ in pairs(self.units) do
                    if not UnitInRaid(playerName) and not UnitInParty(playerName) then
                        self.units[playerName] = nil
                    else
                        if self:getUnit(playerName).dead and not UnitIsDeadOrGhost(playerName) then
                            self:getUnit(playerName).dead = nil
                        end

                        self:getUnit(playerName).range = self:UnitInRange(playerName) and 1 or 0

                        if CanInspect(playerName) and CheckInteractDistance(playerName, 1) then
                            local trinket1 = GetInventoryItemID(playerName, 13)
                            local trinket2 = GetInventoryItemID(playerName, 14)

                            local refresh = false
                            if trinket1 or trinket2 then
                                if self:getUnit(playerName).trinket1 ~= trinket1 then
                                    self:getUnit(playerName).trinket1 = trinket1
                                    refresh = true
                                end

                                if self:getUnit(playerName).trinket2 ~= trinket2 then
                                    self:getUnit(playerName).trinket2 = trinket2
                                    refresh = true
                                end

                                if refresh then
                                    self:refreshPlayerCooldowns(playerName)
                                end
                            end
                        end
                    end
                end
            end

            for i = 1, #self.groups do
                for j = 1, #self.groups[i].CooldownFrames do
                    self:setTimerColor(self.groups[i].CooldownFrames[j])
                    self:setBarColor(self.groups[i].CooldownFrames[j])
                end
            end

            self:sortFrames()
        end, 1)
    end
end)

function HomeCheck:OnCommReceived(...)
    local prefix, message, _, sender = ...

    if not self.db.global.comms[prefix] then
        return
    end

    if sender == currentPlayer then
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
        if not find(message, ":") then
            return
        end

        messageType, message = strsplit(":", message)
        if messageType ~= "CD" then
            return
        end

        if not find(message, ";") then
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

        for w in gmatch(message, "([^,]*),") do
            spellID, CDLeft = select(3, w:find("(%d+)-(%d+)"))
            spellID = tonumber(spellID)
            CDLeft = tonumber(CDLeft)

            if not spellID or not CDLeft then
                return
            end

            if not self.spells[spellID] then
                spellName = GetSpellInfo(spellID)
                if spellName then
                    spellID = self.localizedSpellNames[spellName]
                end
            end

            self:setCooldown(spellID, playerName, CDLeft, nil, true)
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
    elseif CDLeft <= 0 and not self:getSpellAlwaysShow(spellID) then
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

    if not self.spells[spellID] then
        if not spellName then
            spellName = GetSpellInfo(spellID)
        end
        if spellName then
            spellID = self.localizedSpellNames[spellName]
        end
    end

    if prefix == "RCD2" and CDLeft == 0 and not self:UnitHasAbility(playerName, spellID) then
        return
    end

    if target then
        if target == "" then
            target = nil
        else
            target = tostring(target)
        end
    end

    self:setCooldown(spellID, playerName, CDLeft, target, true)
end

---@param spellID number
---@param playerName string
---@param CDLeft number|boolean|nil
---@param target string|nil
---@param isRemote boolean|nil
function HomeCheck:setCooldown(spellID, playerName, CDLeft, target, isRemote, testMode)
    if not spellID or not self.spells[spellID] then
        return
    end

    if self.spells[spellID].ignore then
        return
    end

    if spellID == 23989 then
        -- Readiness
        self:Readiness(playerName)
    end

    if not isRemote and CDLeft == true then
        if not target or self.spells[spellID].notarget then
            self:SendCommMessage("HomeCheck", self:Serialize(spellID, playerName), "RAID")
        else
            self:SendCommMessage("HomeCheck", self:Serialize(spellID, playerName, target), "RAID")
        end
    end

    if self.db.global.selfignore and playerName == currentPlayer then
        return
    end

    if not self:isSpellEnabled(spellID) then
        return
    end

    if self.spells[spellID].parent then
        local frame = self:getCooldownFrame(playerName, self.spells[spellID].parent)
        if frame then
            if frame.CDLeft ~= 0 then
                self:setTarget(frame, target)
                return
            else
                self:removeCooldownFrames(playerName, self.spells[spellID].parent)
            end
        end
    end

    local frame = self:createCooldownFrame(playerName, spellID, testMode)

    if CDLeft == true then
        CDLeft = self:getSpellCooldown(frame)
    end

    if not CDLeft and frame.CDLeft == 0 and self.db.global.CDs[playerName][spellID].timestamp and self.db.global.CDs[playerName][spellID].timestamp > time() then
        -- restoring CD info from SV
        CDLeft = self.db.global.CDs[playerName][spellID].timestamp - time()
        target = self.db.global.CDs[playerName][spellID].target
        -- unknown data source and reliability, treat it as remote
        isRemote = true
    end

    target = self:setTarget(frame, target)

    if CDLeft then
        if frame.isRemote then
            if isRemote then
                if frame.CDLeft > 5 then
                    if CDLeft >= frame.CDLeft and CDLeft - frame.CDLeft < 5 then
                        return
                    end
                end
            else
                frame.isRemote = false
            end
        else
            if isRemote then
                if frame.CDLeft > 5 then
                    return
                end
                if CDLeft >= frame.CDLeft and CDLeft - frame.CDLeft < 5 then
                    return
                end
            else
                if CDLeft >= frame.CDLeft and CDLeft - frame.CDLeft < 2 then
                    return
                end
            end
        end

        frame.CDLeft = CDLeft
    elseif frame.initialized then
        return
    end

    if childSpells[spellID] then
        if not target then
            self:setTarget(frame, self:getTarget(playerName, childSpells[spellID]))
        end
        self:removeCooldownFrames(playerName, childSpells[spellID])
    end

    frame.CDLeft = CDLeft or frame.CDLeft
    frame.CDReady = GetTime() + frame.CDLeft
    frame.isRemote = isRemote
    frame.CD = self:getSpellCooldown(frame)
    if frame.CD < frame.CDLeft then
        frame.CD = frame.CDLeft
    end

    if not testMode then
        self.db.global.CDs[playerName][spellID].timestamp = frame.CDLeft > 0 and (time() + frame.CDLeft) or nil
    end

    if frame.CDLeft > 0 then
        frame.timerFontString:SetText(date("!%M:%S", frame.CDLeft):gsub('^0+:?0?', ''))
        -- the shared ticker counts it down from here
        frame.ticking = true
    elseif not self:getSpellAlwaysShow(spellID) then
        self:removeCooldownFrames(playerName, spellID, true)
        self:repositionFrames(self:getSpellGroup(spellID))
        return
    else
        frame.timerFontString:SetText("R")
    end

    self:updateCooldownBarProgress(frame)

    self:sortFrames(self:getSpellGroup(spellID))

    self:setTimerColor(frame)

    frame.initialized = true
end

---One bar's countdown, a tenth of a second's worth.
function HomeCheck:tickCooldown(frame)
    local playerName, spellID = frame.playerName, frame.spellID
    frame.CDLeft = frame.CDReady - GetTime()

    if frame.CDLeft <= 0 then
        frame.ticking = nil
        wipe(self.db.global.CDs[playerName][spellID])
        if not self:getSpellAlwaysShow(spellID) then
            self:removeCooldownFrames(playerName, spellID)
            self:repositionFrames(self:getSpellGroup(spellID))
            return
        end
        if frame.CDLeft < 0 then
            frame.CDLeft = 0
        end
        frame.timerFontString:SetText("R")
        self:setTimerColor(frame)
    elseif frame.timerText ~= floor(frame.CDLeft) then
        frame.timerText = floor(frame.CDLeft)
        frame.timerFontString:SetText(date("!%M:%S", frame.CDLeft):gsub('^0+:?0?', ''))
        self:setTimerColor(frame)
    end
    self:updateCooldownBarProgress(frame)
end

-- One ticker for every bar on screen, instead of a repeating AceTimer each.
-- Bars are walked backwards because a bar that just came off cooldown removes
-- itself from the list it is being walked through.
local tickElapsed = 0
HomeCheck:SetScript("OnUpdate", function(self, elapsed)
    tickElapsed = tickElapsed + elapsed
    if tickElapsed < 0.1 then
        return
    end
    tickElapsed = 0

    for i = 1, #self.groups do
        local frames = self.groups[i].CooldownFrames
        for j = #frames, 1, -1 do
            if frames[j].ticking then
                self:tickCooldown(frames[j])
            end
        end
    end
end)

function HomeCheck:getCooldownFrame(playerName, spellID)
    local group = self:getGroup(self:getSpellGroup(spellID))
    for i = 1, #group.CooldownFrames do
        if group.CooldownFrames[i].playerName == playerName and group.CooldownFrames[i].spellID == spellID then
            return group.CooldownFrames[i]
        end
    end
end

function HomeCheck:createCooldownFrame(playerName, spellID, testMode)
    local frame = self:getCooldownFrame(playerName, spellID)

    if frame then
        return frame
    end

    local group = self:getGroup(self:getSpellGroup(spellID))

    -- A bar is built once and kept: frames are never collected by the garbage
    -- collector, so a raid's worth of cooldowns coming and going would leave
    -- hundreds of them behind. A released bar waits in the pool instead.
    frame = remove(framePool)
    if frame then
        frame:SetParent(group)
        frame:ClearAllPoints()
        frame:Show()
    else
        frame = CreateFrame("Frame", nil, group)

        frame.icon = frame:CreateTexture(nil, "OVERLAY")
        frame.icon:SetPoint("LEFT")

        frame.bar = CreateFrame("Frame", nil, frame)
        frame.bar:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT")
        frame.bar:SetPoint("BOTTOMRIGHT")

        frame.bar.active = frame.bar:CreateTexture(nil, "ARTWORK")
        frame.bar.active:SetPoint("LEFT")
        frame.bar.inactive = frame.bar:CreateTexture(nil, "ARTWORK")
        frame.bar.inactive:SetPoint("RIGHT")
        frame.bar.inactive:SetPoint("LEFT", frame.bar.active, "RIGHT")

        frame.playerNameFontString = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.playerNameFontString:SetTextColor(1, 1, 1, 1)

        frame.targetFontString = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.targetFontString:SetPoint("LEFT", frame.playerNameFontString, "RIGHT", 1, 0)

        frame.timerFontString = frame.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end

    frame.playerName = playerName
    frame.spellID = spellID
    frame.CDLeft = 0
    frame.class = self.spells[spellID].class
    if not frame.class then
        frame.class = testMode and select(2, UnitClass("player")) or select(2, UnitClass(playerName))
    end
    frame.CD = self:getSpellCooldown(frame)
    frame.testMode = testMode

    -- whatever the previous holder of this bar left behind
    frame.target = nil
    frame.isRemote = nil
    frame.initialized = nil
    frame.ticking = nil
    frame.timerText = nil
    frame.timerColorState = nil
    frame.barColorDimmed, frame.barColorOpacity, frame.barColorClass = nil, nil, nil

    frame.icon:SetTexture(select(2, self:getSpellInfo(spellID)))
    frame.playerNameFontString:SetText(playerName)
    frame.targetFontString:SetText("")
    frame.timerFontString:SetText("")

    self:applyGroupSettings(frame)

    self:EnableMouse(frame, not self.db.global.link)

    insert(group.CooldownFrames, frame)
    self:updateFramesVisibility(self:getSpellGroup(spellID))
    return frame
end

function HomeCheck:EnableMouse(frame, disable)
    if disable then
        frame:SetScript("OnMouseDown", nil)
        frame:EnableMouse(false)
    else
        frame:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and (IsShiftKeyDown() or IsControlKeyDown()) then
                local message = frame.playerName .. " " .. (GetSpellLink(frame.spellID))
                if frame.CDLeft == 0 then
                    message = message .. " READY"
                else
                    if frame.target then
                        message = message .. " (" .. frame.target .. ")"
                    end
                    message = message .. " " .. date("!%M:%S", frame.CDLeft)
                end
                if IsShiftKeyDown() then
                    ChatThrottleLib:SendChatMessage("NORMAL", "HomeCheck", message, playerInRaid and "RAID" or "PARTY")
                elseif IsControlKeyDown() then
                    ChatThrottleLib:SendChatMessage("NORMAL", "HomeCheck", message, "WHISPER", nil, frame.playerName)
                end
            end
        end)
        frame:EnableMouse(true)
    end
end

--- called when group sizing changes (icon, padding, etc.), or titleBar is toggled, or cooldown frame is added or removed
function HomeCheck:repositionFrames(groupIndex)
    if not groupIndex then
        for i = 1, #self.groups do
            self:repositionFrames(i)
        end
    else
        local titleBarHeight = 0
        if self:getIProp(groupIndex, "showTitleBar") and self.groups[groupIndex].titleBar and self.groups[groupIndex].titleBar:IsShown() then
            titleBarHeight = self:getIProp(groupIndex, "titleBarHeight")
        end
        for j = 1, #self.groups[groupIndex].CooldownFrames do
            self.groups[groupIndex].CooldownFrames[j]:SetPoint("TOPLEFT", 0, -titleBarHeight - (self:getIProp(groupIndex, "iconSize") + self:getIProp(groupIndex, "padding")) * (j - 1))
        end
    end
end

function HomeCheck:loadProfile()
    for i = 1, #self.groups do
        self.groups[i].anchor:ClearAllPoints()
        self.groups[i].anchor:SetPoint(self.db.profile[i].pos.point, self.db.profile[i].pos.relativeTo, self.db.profile[i].pos.relativePoint, self.db.profile[i].pos.xOfs, self.db.profile[i].pos.yOfs)
        for j = 1, #self.groups[i].CooldownFrames do
            if i ~= self:getSpellGroup(self.groups[i].CooldownFrames[j].spellID) then
                self:moveFrameToGroup(self.groups[i].CooldownFrames[j].spellID, i, self:getSpellGroup(self.groups[i].CooldownFrames[j].spellID))
            else
                self:applyGroupSettings(self.groups[i].CooldownFrames[j])
            end
        end
    end
    self:updateRaidCooldowns()
    self:sortFrames()
end

function HomeCheck:removeCooldownFrames(playerName, spellID, onlyWhenReady, testMode)
    for i = spellID and self:getSpellGroup(spellID) or 1, #self.groups do
        local group = self.groups[i].CooldownFrames
        for j = #group, 1, -1 do
            local frame = group[j]
            if (
                    frame.playerName == playerName
                            and (not spellID or frame.spellID == spellID)
                            and (not onlyWhenReady or frame.CDLeft <= 0)
            ) or (
                    testMode and frame.testMode
            ) then
                local released = remove(group, j)
                released:Hide()
                released.ticking = nil
                framePool[#framePool + 1] = released
                self:updateFramesVisibility(i)
                if playerName and spellID then
                    return
                end
            end
        end
        if spellID then
            return
        end
    end
end

function HomeCheck:updateRaidRoster(instant, startGroup, startIndex)
    if not instant then
        if updateRaidRosterScheduleTimer then
            -- update is scheduled
            return
        end

        if updateRaidRosterTimestamp and time() - updateRaidRosterTimestamp < updateRaidRosterCooldown then
            -- update is on cooldown
            updateRaidRosterScheduleTimer = self:ScheduleTimer(function()
                updateRaidRosterScheduleTimer = nil
                self:updateRaidRoster()
            end, updateRaidRosterCooldown)
            return
        end
    end

    for i = startGroup or 1, #self.groups do
        for j = startIndex or 1, #self.groups[i].CooldownFrames do
            if not UnitInRaid(self.groups[i].CooldownFrames[j].playerName) and not UnitInParty(self.groups[i].CooldownFrames[j].playerName) or not UnitIsConnected(self.groups[i].CooldownFrames[j].playerName) then
                self:removeCooldownFrames(self.groups[i].CooldownFrames[j].playerName)
                return self:updateRaidRoster(true, i, j)
            end
        end
    end
    self:updateRaidCooldowns()
    updateRaidRosterTimestamp = time()
end

function HomeCheck:updateRaidCooldowns()
    if GetNumRaidMembers() > 0 then
        for i = 1, 40 do
            local playerName, _, _, _, _, class, _, online, isDead = GetRaidRosterInfo(i)
            if playerName and online then
                if self:getUnit(playerName).dead ~= isDead then
                    self:getUnit(playerName).dead = isDead
                end
                self:refreshPlayerCooldowns(playerName, class)
            end
        end
    else
        local isDead = UnitIsDeadOrGhost("player")
        if self:getUnit(currentPlayer).dead ~= isDead then
            self:getUnit(currentPlayer).dead = isDead
        end
        self:refreshPlayerCooldowns(currentPlayer)
        for i = 1, GetNumPartyMembers() do
            if UnitIsConnected("party" .. i) then
                local playerName = (UnitName("party" .. i))
                isDead = UnitIsDeadOrGhost("party" .. i)
                if self:getUnit(playerName).dead ~= isDead then
                    self:getUnit(playerName).dead = isDead
                end
                self:refreshPlayerCooldowns(playerName)
            end
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
            if self.db.profile.spells[spellID] and self:isSpellEnabled(spellID) and self:UnitHasAbility(playerName, spellID)
                    and (not self:isSpellTanksOnly(spellID) or self.LibGroupTalents:GetUnitRole(playerName) == "tank")
                    and (not self.db.global.selfignore or playerName ~= currentPlayer) then
                if not spellConfig.parent then
                    self:setCooldown(spellID, playerName)
                end
            else
                self:removeCooldownFrames(playerName, spellID)
            end
        end
    end
end

function HomeCheck:UnitHasAbility(playerName, spellID)
    if self.spells[spellID].parent then
        spellID = self.spells[spellID].parent
    end

    if self.spells[spellID].trinket then
        -- trinket proc
        return self:UnitTrinketEquipped(playerName, self.spells[spellID].trinket)
    end

    -- using UnitHasTalent() as GetTalentInfo() does not return correct value right after respec
    return not self.spells[spellID].talentTab or not self.spells[spellID].talentIndex or self.LibGroupTalents:UnitHasTalent(playerName, (GetSpellInfo(spellID)))
end

function HomeCheck:saveFramePosition(groupIndex)
    local point, relativeTo, relativePoint, xOfs, yOfs = self.groups[groupIndex].anchor:GetPoint(0)
    self.db.profile[groupIndex].pos = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName(),
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
end

function HomeCheck:Readiness(hunterName)
    if self:getUnit(hunterName).readiness and time() - self:getUnit(hunterName).readiness < 100 then
        return
    end

    local refreshSpellIDs = {}
    for i = 1, #self.groups do
        for j = 1, #self.groups[i].CooldownFrames do
            if self.groups[i].CooldownFrames[j].playerName == hunterName and self.groups[i].CooldownFrames[j].spellID ~= 34477 then
                insert(refreshSpellIDs, self.groups[i].CooldownFrames[j].spellID)
            end
        end
    end

    for _, spellID in ipairs(refreshSpellIDs) do
        self:setCooldown(spellID, hunterName, 0)
    end

    self:getUnit(hunterName).readiness = time()
end

function HomeCheck:GSProc(targetName)
    local spellGroup = self:getSpellGroup(47788)
    for i = #self.groups[spellGroup].CooldownFrames, 1, -1 do
        if self.groups[spellGroup].CooldownFrames[i].spellID == 47788
                and self.groups[spellGroup].CooldownFrames[i].target == targetName
                and self.groups[spellGroup].CooldownFrames[i].CDLeft > 55
                and self.groups[spellGroup].CooldownFrames[i].CDLeft <= 70 then
            self:setCooldown(47788, self.groups[spellGroup].CooldownFrames[i].playerName, 180 - 70 + self.groups[spellGroup].CooldownFrames[i].CDLeft)
            break
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
    local groupIndex = self:getSpellGroup(frame1.spellID)
    local spellId1 = self.spells[frame1.spellID].parent or frame1.spellID
    local spellId2 = self.spells[frame2.spellID].parent or frame2.spellID

    if self:getUnit(frame1.playerName).range < self:getUnit(frame2.playerName).range then
        if self:getIProp(groupIndex, "rangeUngroup") then
            return true
        elseif spellId1 == spellId2 and self:getIProp(groupIndex, "rangeDimout") then
            return true
        end
    elseif self:getUnit(frame1.playerName).range > self:getUnit(frame2.playerName).range then
        if self:getIProp(groupIndex, "rangeUngroup") or spellId1 == spellId2 then
            return
        end
    end

    if spellId1 == spellId2 then
        if self:getUnit(frame1.playerName).dead
                and not self:getUnit(frame2.playerName).dead then
            return true
        elseif self:getUnit(frame1.playerName).dead ~= self:getUnit(frame2.playerName).dead then
            return
        end
    end

    if self.db.profile.spells[spellId1].priority < self.db.profile.spells[spellId2].priority then
        return true
    elseif spellId1 == spellId2 then
        if frame1.CDLeft > frame2.CDLeft then
            return true
        end
    elseif self.db.profile.spells[spellId1].priority == self.db.profile.spells[spellId2].priority and spellId1 < spellId2 then
        -- attempt to group spells by ID
        return true
    end
end

function HomeCheck:getGroup(i)
    i = i or 1
    if self.groups[i] then
        return self.groups[i]
    end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:ClearAllPoints()

    frame.anchor = CreateFrame("Frame", nil, frame)
    frame.anchor:SetClampedToScreen(true)
    frame.anchor:SetSize(20, 20)
    frame.anchor:SetPoint(self.db.profile[i].pos.point, self.db.profile[i].pos.relativeTo, self.db.profile[i].pos.relativePoint, self.db.profile[i].pos.xOfs, self.db.profile[i].pos.yOfs)
    frame.anchor:SetFrameStrata("HIGH")
    frame.anchor:SetMovable(true)
    frame.anchor:RegisterForDrag("LeftButton")
    frame.anchor:SetScript("OnDragStart", function(s)
        s:StartMoving()
    end)
    frame.anchor:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        self:saveFramePosition(i)
    end)
    frame.anchor:EnableMouse(true)

    frame:SetAllPoints(frame.anchor)

    -- Create title bar
    frame.titleBar = CreateFrame("Frame", nil, frame)
    frame.titleBar:SetHeight(self:getIProp(i, "titleBarHeight"))
    frame.titleBar:SetWidth(self:getIProp(i, "frameWidth"))
    frame.titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    -- Enable dragging on title bar
    frame.titleBar:EnableMouse(true)
    frame.titleBar:RegisterForDrag("LeftButton")
    frame.titleBar:SetScript("OnDragStart", function()
        frame.anchor:StartMoving()
    end)
    frame.titleBar:SetScript("OnDragStop", function()
        frame.anchor:StopMovingOrSizing()
        self:saveFramePosition(i)
    end)

    -- Visual feedback when hovering over title bar
    frame.titleBar:SetScript("OnEnter", function(s)
        local bgColor = self:getIProp(i, "titleBackgroundColor")
        s.bg:SetVertexColor(bgColor[1] * 1.2, bgColor[2] * 1.2, bgColor[3] * 1.2, bgColor[4])
    end)
    frame.titleBar:SetScript("OnLeave", function(s)
        local bgColor = self:getIProp(i, "titleBackgroundColor")
        s.bg:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    end)

    -- Title background (optional)
    frame.titleBar.bg = frame.titleBar:CreateTexture(nil, "BACKGROUND")
    frame.titleBar.bg:SetAllPoints(frame.titleBar)
    frame.titleBar.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    local bgColor = self:getIProp(i, "titleBackgroundColor")
    frame.titleBar.bg:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Title text
    frame.titleBar.text = frame.titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.titleBar.text:SetPoint("LEFT", frame.titleBar, "LEFT", 2, 0)
    frame.titleBar.text:SetPoint("RIGHT", frame.titleBar, "RIGHT", -2, 0)
    frame.titleBar.text:SetJustifyH("LEFT")
    local titleText = self:getIProp(i, "titleText")
    local displayText = titleText ~= "" and titleText or ("Group " .. i)
    frame.titleBar.text:SetText(displayText)
    frame.titleBar.text:SetTextColor(1, 1, 1, 1)
    local font = frame.titleBar.text:GetFont()
    frame.titleBar.text:SetFont(font, self:getIProp(i, "titleFontSize"))

    -- Show/hide title bar based on settings
    if self:getIProp(i, "showTitleBar") then
        frame.titleBar:Show()
    else
        frame.titleBar:Hide()
    end

    frame.CooldownFrames = {}

    frame:Hide()

    insert(self.groups, frame)
    return frame
end

---@param playerName string
---@param spellID number
function HomeCheck:getCDLeft(playerName, spellID)
    for i = 1, #self.groups[self:getSpellGroup(spellID)].CooldownFrames do
        if playerName == self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].playerName
                and spellID == self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].spellID then
            return self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].CDLeft
        end
    end
    return 0
end

function HomeCheck:getTarget(playerName, spellID)
    for i = 1, #self.groups[self:getSpellGroup(spellID)].CooldownFrames do
        if playerName == self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].playerName
                and spellID == self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].spellID then
            return self.groups[self:getSpellGroup(spellID)].CooldownFrames[i].target
        end
    end
end

function HomeCheck:setTarget(frame, target)
    if not target or self.spells[frame.spellID].notarget then
        return
    end
    -- The bar already shows this target: there is nothing to set, but the
    -- caller must not read the answer as "no target" and go looking for one
    -- elsewhere, because the one it has is right.
    if target == frame.target then
        return target
    end
    if self.spells[frame.spellID].noself and target == frame.playerName then
        return
    end
    frame.target = target
    self.db.global.CDs[frame.playerName][frame.spellID].target = target
    frame.targetFontString:SetText(target)
    local class = select(2, UnitClass(target))
    if class then
        local targetClassColor = RAID_CLASS_COLORS[class]
        frame.targetFontString:SetTextColor(targetClassColor.r, targetClassColor.g, targetClassColor.b, 1)
    end
    return target
end

-- Both colour setters run for every bar once a second, and the colour almost
-- never differs from the one the bar already carries. Each remembers what it
-- last applied and does nothing until that changes.
---@param frame
function HomeCheck:setBarColor(frame)
    local dimmed = self:getUnit(frame.playerName).dead
            or (self:getUnit(frame.playerName).range == 0
            and self:getIPropBySpellId(frame.spellID, "rangeDimout"))
    local opacity = self:getIPropBySpellId(frame.spellID, "opacity")

    if frame.barColorDimmed == dimmed and frame.barColorOpacity == opacity and frame.barColorClass == frame.class then
        return
    end
    frame.barColorDimmed, frame.barColorOpacity, frame.barColorClass = dimmed, opacity, frame.class

    if dimmed then
        frame.bar.active:SetVertexColor(0.5, 0.5, 0.5, opacity)
    else
        local playerClassColor = RAID_CLASS_COLORS[frame.class]
        frame.bar.active:SetVertexColor(playerClassColor.r, playerClassColor.g, playerClassColor.b, opacity)
    end
end

-- what setTimerColor last painted: dead, ready, or counting down
local TIMER_DEAD, TIMER_READY, TIMER_RUNNING = 1, 2, 3

function HomeCheck:setTimerColor(frame)
    local state
    if self:getUnit(frame.playerName).dead then
        state = TIMER_DEAD
    elseif frame.CDLeft <= 0 then
        if not self.db.profile.spells[frame.spellID].alwaysShow then
            -- the bar is on its way out, leave the colour alone
            return
        end
        state = TIMER_READY
    else
        state = TIMER_RUNNING
    end

    if frame.timerColorState == state then
        return
    end
    frame.timerColorState = state

    if state == TIMER_DEAD then
        frame.timerFontString:SetTextColor(1, 0, 0, 1)
    elseif state == TIMER_READY then
        frame.timerFontString:SetTextColor(0, 1, 0, 1)
    else
        frame.timerFontString:SetTextColor(0.9, 0.7, 0, 1)
    end
end

function HomeCheck:getSpellCooldown(frame)
    local CDmodifier = 0
    if frame.spellID == 498 or frame.spellID == 642 then
        -- Divine Shield and Divine Protection
        CDmodifier = -30 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 2, 14)) or 0)
    elseif frame.spellID == 10278 then
        -- HoP
        CDmodifier = -60 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 2, 4)) or 0)
    elseif frame.spellID == 48788 then
        -- Lay on Hands
        CDmodifier = -120 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 1, 8)) or 0)
        if self:UnitHasGlyph(frame.playerName, 57955) then
            CDmodifier = CDmodifier - 300
        end
    elseif frame.spellID == 20608 then
        -- Reincarnation
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 3))
        if talentPoints == 1 then
            CDmodifier = -420
        elseif talentPoints == 2 then
            CDmodifier = -900
        end
    elseif frame.spellID == 871 then
        -- Shield Wall
        CDmodifier = -30 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 13)) or 0)
        if self:UnitHasGlyph(frame.playerName, 63329) then
            CDmodifier = CDmodifier - 120
        end
    elseif frame.spellID == 12975 then
        -- Last Stand
        if self:UnitHasGlyph(frame.playerName, 58376) then
            CDmodifier = CDmodifier - 60
        end
    elseif frame.spellID == 48447 then
        -- Tranquility
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 14))
        if talentPoints == 1 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.3
        elseif talentPoints == 2 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.5
        end
    elseif frame.spellID == 47585 then
        -- Dispersion
        if self:UnitHasGlyph(frame.playerName, 63229) then
            CDmodifier = CDmodifier - 45
        end
    elseif frame.spellID == 45438 then
        -- Ice Block
        local talentPoints = select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 3))
        if talentPoints == 1 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.07
        elseif talentPoints == 2 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.14
        elseif talentPoints == 3 then
            CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.2
        end
    elseif frame.spellID == 66 or frame.spellID == 12051 then
        -- Invisibility or Evocation
        CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.15 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 1, 24)) or 0)
    elseif frame.spellID == 12292 then
        -- Death Wish
        CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.11 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 2, 18)) or 0)
    elseif frame.spellID == 10060 or frame.spellID == 33206 then
        -- Power Infusion and Pain Suppression
        CDmodifier = -(self.spells[frame.spellID] and self.spells[frame.spellID].cd or 0) * 0.1 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 1, 23)) or 0)
    elseif frame.spellID == 47788 then
        -- Guardian spirit
        if frame.CDLeft > self.spells[frame.spellID].cd then
            return 180
        end
        if not self:UnitHasGlyph(frame.playerName, 63231, true) then
            return 180
        end
    elseif frame.spellID == 42650 then
        -- Army of the Dead
        CDmodifier = -120 * (select(5, self.LibGroupTalents:GetTalentInfo(frame.playerName, 3, 13)) or 0)
    end

    return self.spells[frame.spellID].cd + CDmodifier
end

function HomeCheck:cacheLocalizedSpellNames()
    for spellID, _ in pairs(self.spells) do
        local spellName = GetSpellInfo(spellID)
        self.localizedSpellNames[spellName] = spellID
    end
end

function HomeCheck:getSpellGroup(spellID)
    return self.spells[spellID].parent and self.db.profile.spells[self.spells[spellID].parent].group or self.db.profile.spells[spellID].group
end

function HomeCheck:applyGroupSettings(frame, groupIndex)
    groupIndex = groupIndex or self:getSpellGroup(frame.spellID)

    frame:SetParent(self:getGroup(groupIndex))

    self:setFrameHeight(frame, self:getIProp(groupIndex, "iconSize"))
    frame:SetWidth(self:getIProp(groupIndex, "frameWidth"))
    frame.playerNameFontString:SetFont(self.LibSharedMedia:Fetch("font", self:getIProp(groupIndex, "fontPlayer")), self:getIProp(groupIndex, "fontSize"))
    frame.targetFontString:SetFont(self.LibSharedMedia:Fetch("font", self:getIProp(groupIndex, "fontTarget")), self:getIProp(groupIndex, "fontSizeTarget"))
    frame.targetFontString:SetJustifyH(self:getIProp(groupIndex, "targetJustify") == "l" and "LEFT" or "RIGHT")
    self:setBarTexture(frame, self.LibSharedMedia:Fetch("statusbar", self:getIProp(groupIndex, "statusbar")))
    self:setBarColor(frame)
    frame.bar.inactive:SetVertexColor(unpack(self:getIProp(groupIndex, "background")))
    frame.timerFontString:SetFont(self.LibSharedMedia:Fetch("font", self:getIProp(groupIndex, "fontTimer")), self:getIProp(groupIndex, "fontSizeTimer"))
    self:setTimerPosition(frame)
end

function HomeCheck:setSpellGroupIndex(spellID, groupIndex)
    if self.db.profile.spells[spellID].group == groupIndex then
        return
    end
    self:moveFrameToGroup(spellID, self.db.profile.spells[spellID].group, groupIndex)
    self:sortFrames(self.db.profile.spells[spellID].group)
    self:sortFrames(groupIndex)
    self.db.profile.spells[spellID].group = groupIndex
end

function HomeCheck:moveFrameToGroup(spellID, sourceGroupIndex, destGroupIndex, startIndex)
    for i = startIndex or 1, #self.groups[sourceGroupIndex].CooldownFrames do
        if spellID == self.groups[sourceGroupIndex].CooldownFrames[i].spellID then
            local frame = remove(self.groups[sourceGroupIndex].CooldownFrames, i)
            self:updateFramesVisibility(sourceGroupIndex)
            self:applyGroupSettings(frame, destGroupIndex)
            insert(self.groups[destGroupIndex].CooldownFrames, frame)
            self:updateFramesVisibility(destGroupIndex)
            return self:moveFrameToGroup(spellID, sourceGroupIndex, destGroupIndex, i)
        end
    end
end

function HomeCheck:UnitInRange(unit)
    return select(2, self.LibRangeCheck:GetRange(unit))
end

function HomeCheck:updateCooldownBarProgress(frame)
    local pct = frame.CDLeft / frame.CD
    if self:getIPropBySpellId(frame.spellID, "invertColors") then
        if pct ~= 0 then
            if not frame.bar.active:IsShown() then
                frame.bar.active:Show()
                frame.bar.inactive:SetPoint("LEFT", frame.bar.active, "RIGHT")
            end
            frame.bar.active:SetWidth((self:getIPropBySpellId(frame.spellID, "frameWidth") - self:getIPropBySpellId(frame.spellID, "iconSize")) * pct)
        elseif frame.bar.active:IsShown() then
            frame.bar.active:Hide()
            frame.bar.inactive:SetPoint("LEFT", frame.icon, "RIGHT")
        end
    else
        if pct ~= 1 then
            if not frame.bar.active:IsShown() then
                frame.bar.active:Show()
                frame.bar.inactive:SetPoint("LEFT", frame.bar.active, "RIGHT")
            end
            frame.bar.active:SetWidth((self:getIPropBySpellId(frame.spellID, "frameWidth") - self:getIPropBySpellId(frame.spellID, "iconSize")) * (1 - pct))
        elseif frame.bar.active:IsShown() then
            frame.bar.active:Hide()
            frame.bar.inactive:SetPoint("LEFT", frame.icon, "RIGHT")
        end
    end
end

function HomeCheck:setTimerPosition(frame)
    frame.timerFontString:ClearAllPoints()
    if self:getIPropBySpellId(frame.spellID, "timerPosition") == "l" then
        frame.timerFontString:SetPoint("LEFT", frame.icon, "RIGHT", 1, 0)
        frame.playerNameFontString:SetPoint("LEFT", frame.timerFontString, "RIGHT", 2, 0)
        frame.targetFontString:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    else
        frame.timerFontString:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
        frame.playerNameFontString:SetPoint("LEFT", frame.icon, "RIGHT", 1, 0)
        frame.targetFontString:SetPoint("RIGHT", frame.timerFontString, "LEFT", -1, 0)
    end
end

function HomeCheck:getSpellSetting(spellID, setting)
    local spell = self.spells[spellID]
    return self.db.profile.spells[spell and spell.parent or spellID][setting]
end

function HomeCheck:getSpellAlwaysShow(spellID)
    return self:getSpellSetting(spellID, "alwaysShow")
end

function HomeCheck:isSpellEnabled(spellID)
    return self:getSpellSetting(spellID, "enable")
end

function HomeCheck:isSpellTanksOnly(spellID)
    return self:getSpellSetting(spellID, "tanksonly")
end

function HomeCheck:UnitHasGlyph(unit, glyphID, default)
    if self.LibGroupTalents:UnitHasGlyph(unit, glyphID) then
        return true
    end
    if not default then
        return false
    end
    local a, b, c, d, e, f = self.LibGroupTalents:GetUnitGlyphs(unit)
    if a or b or c or d or e or f then
        -- checking if any glyph info exists to make sure glyph info was actually fetched
        return false
    end
    -- assume player has glyph if glyph info is empty and default=true
    return true
end

function HomeCheck:setBarTexture(frame, texture)
    frame.bar.active:SetTexture(texture)
    frame.bar.inactive:SetTexture(texture)
end

function HomeCheck:setFrameHeight(frame, height)
    if not height then
        height = self:getIPropBySpellId(frame.spellID, "iconSize")
    end
    frame:SetHeight(height)
    frame.icon:SetSize(height, height)
    frame.bar.active:SetHeight(height)
    frame.bar.inactive:SetHeight(height)
    self:updateCooldownBarProgress(frame)
end

-- Title bar properties are never inherited - always use the specific group's settings
local titleBarProperties = {
    showTitleBar = true,
    titleText = true,
    titleBarHeight = true,
    titleFontSize = true,
    titleBackgroundColor = true
}

---getIProp
---@param frameId number frame group number
---@param propertyName string property name to get
function HomeCheck:getIProp(frameId, propertyName)
    if titleBarProperties[propertyName] then
        return self.db.profile[frameId][propertyName]
    else
        return self.db.profile[self.db.profile[frameId].inherit or frameId][propertyName]
    end
end

function HomeCheck:getIPropBySpellId(spellId, propertyName)
    return self:getIProp(self:getSpellGroup(spellId), propertyName)
end

function HomeCheck:updateFramesVisibility(groupIndex)
    if groupIndex then
        if self.groups[groupIndex]:IsShown() then
            if #self.groups[groupIndex].CooldownFrames == 0
                    or (self.db.global.hidesolo and not playerInRaid and GetNumPartyMembers() == 0) then
                self.groups[groupIndex]:Hide()
            end
        elseif #self.groups[groupIndex].CooldownFrames ~= 0
                and (not self.db.global.hidesolo or playerInRaid or GetNumPartyMembers() ~= 0) then
            self.groups[groupIndex]:Show()
        end

        return
    end

    for i = 1, #self.groups do
        self:updateFramesVisibility(i)
    end
end

function HomeCheck:setTestMode(enable)
    self.db.global.testMode = enable
    if enable then
        for spellId, _ in pairs(self.db.profile.spells) do
            if self.spells[spellId] then
                -- Create test cooldown with varying times
                local testCDLeft = random(1, 5) * 10
                self:setCooldown(spellId, "Testframe" .. random(1, 4), testCDLeft, nil, nil, true)
            end
        end
    else
        -- Remove all test frames
        self:removeCooldownFrames(nil, nil, nil, true)
    end

    self:repositionFrames()
end

function HomeCheck:getUnit(playerName)
    if not self.units[playerName] then
        self.units[playerName] = {
            dead = self.db.global.testMode and (random(1, 100) > 80 and 1 or nil) or UnitIsDeadOrGhost(playerName),
            range = self.db.global.testMode and (random(1, 100) > 80 and 0 or 1) or (self:UnitInRange(playerName) and 1 or 0)
        }
    end
    return self.units[playerName]
end

function HomeCheck:UnitTrinketEquipped(playerName, trinketId)
    if type(trinketId) == "table" then
        for _, id in ipairs(trinketId) do
            if self:getUnit(playerName).trinket1 == id or self:getUnit(playerName).trinket2 == id then
                return true
            end
        end
    elseif self:getUnit(playerName).trinket1 == trinketId or self:getUnit(playerName).trinket2 == trinketId then
        return true
    end

    return false
end

function HomeCheck:getSpellInfo(spellId)
    local spell = self.spells[spellId]

    local name = spell.name
    local icon = spell.icon

    if not name or not icon then
        local trinket = spell.trinket

        if not trinket then
            local parent = self.spells[spell.parent]
            trinket = parent and parent.trinket
        end

        if trinket then
            name, _, _, _, _, _, _, _, _, icon = GetItemInfo(type(trinket) == "table" and trinket[1] or trinket)
        else
            name, _, icon = GetSpellInfo(spellId)
        end
    end

    --caching
    spell.name, spell.icon = name, icon

    return name, icon
end