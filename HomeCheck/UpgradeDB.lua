local function tablecopy(t, copyto)
    if type(t) ~= "table" then
        return
    end
    for k, v in pairs(t) do
        if type(v) == "table" then
            copyto[k] = tablecopy(v, copyto[k])
        else
            copyto[k] = v
        end
    end
    return copyto
end

function HomeCheck:upgradeDB()
    if self.db.global.db_ver ~= self.db_ver then
        if self.db.global.db_ver == 1 then
            for k, v in pairs(self.db.global) do
                if k ~= "db_ver" and k ~= "CDs" and k ~= "comms" and k ~= "link" then
                    self.db.profile[k], self.db.global[k] = tablecopy(v, self.db.profile[k]), nil
                end
            end
            self.db.global.db_ver = 4
        end

        if self.db.global.db_ver == 2 then
            self.db.global.db_ver = 4
        end

        if self.db.global.db_ver == 3 then
            local currentProfile = self.db:GetCurrentProfile()
            local profiles = self.db:GetProfiles()
            for _, profile in ipairs(profiles) do
                self.db:SetProfile(profile)
                for k, v in pairs(self.db.profile.spells[48153]) do
                    if (self.defaults.profile.spells[47788][k] == nil or v ~= self.defaults.profile.spells[47788][k])
                            and (self.defaults.profile.spells['**'][k] == nil or v ~= self.defaults.profile.spells['**'][k]) then
                        self.db.profile.spells[47788][k] = v
                    end
                end
                self.db.profile.spells[48153] = nil
            end
            self.db:SetProfile(currentProfile)
            self.db.global.db_ver = 4
        end

        if self.db.global.db_ver ~= self.db_ver then
            -- unknown db version, resetting db to defaults
            self.db:ResetDB("Default")
            self.db.global.db_ver = self.db_ver
        end
    end
end