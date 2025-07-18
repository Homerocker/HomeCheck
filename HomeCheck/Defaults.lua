HomeCheck.defaults = {
    global = {
        CDs = {
            ['*'] = {
                ['*'] = {}
            }
        },
        comms = {
            oRA3 = true,
            BLT = true,
            oRA = true,
            CTRA = true,
            RCD2 = true,
            FRCD3S = true,
            HomeCheck = true,
            FRCD3 = true
        },
        link = true,
        selfignore = false,
        hidesolo = false
    },
    profile = {
        ['*'] = {
            frameWidth = 155,
            iconSize = 14,
            fontSize = 9,
            padding = 0,
            fontSizeTarget = 9,
            fontSizeTimer = 9,
            pos = {
                point = "CENTER",
                relativeTo = "UIParent",
                relativePoint = "CENTER",
                xOfs = 0,
                yOfs = 0
            },
            fontPlayer = "Friz Quadrata TT",
            fontTarget = "Friz Quadrata TT",
            fontTimer = "Friz Quadrata TT",
            statusbar = "Armory",
            opacity = 0.65,
            background = { 0.14, 0.14, 0.14, 0.6 },
            timerPosition = "r",
            targetJustify = "r",
            inherit = 1,
            rangeDimout = true,
            rangeUngroup = true,
            invertColors = false,
            -- Title bar settings
            showTitleBar = true,
            titleText = "",
            titleBarHeight = 18,
            titleFontSize = 9,
            titleBackgroundColor = { 0.1, 0.1, 0.1, 0.8 }
        },
        spells = {
            ["**"] = {
                group = 2,
                priority = 100
            },
            -- DSac
            [64205] = {
                enable = true,
                alwaysShow = true,
                group = 1,
                priority = 195
            },
            -- GS
            [47788] = {
                enable = true,
                alwaysShow = true,
                group = 1,
                priority = 190
            },
            -- Sac
            [6940] = {
                enable = true,
                alwaysShow = true,
                group = 1,
                priority = 185
            },
            -- PS
            [33206] = {
                enable = true,
                alwaysShow = true,
                group = 1,
                priority = 190
            },
            -- Rebirth
            [48477] = {
                enable = true,
                alwaysShow = true,
                group = 2,
                priority = 175
            },
            -- Innervate
            [29166] = {
                enable = true,
                alwaysShow = true,
                group = 2,
                priority = 170
            },
            -- MD
            [35079] = {
                enable = true,
                group = 2,
                priority = 160
            },
            -- ToT
            [59628] = {
                enable = true,
                group = 2,
                priority = 160
            },
            -- Reincarnation
            [21169] = {
                priority = 174,
                enable = true
            },
            -- HoF
            [1044] = {
                enable = true
            },
            -- Hand of Salvation
            [1038] = {
                enable = true
            },
            -- Heroism
            [16190] = {
                enable = true
            },
            -- Bloodlust
            [2825] = {
                enable = true
            },
            -- Army of the Dead
            [42650] = {
                enable = true
            },
            -- Holy Wrath
            [48817] = {
                enable = true
            },
            -- Hysteria
            [49016] = {
                enable = true
            },
            -- PI
            [10060] = {
                enable = true
            },
            -- Divine Protection
            [498] = {
                tanksonly = true
            },
            -- Vampiric Blood
            [55233] = {
                tanksonly = true
            },
            -- Icebound Fortitude
            [48792] = {
                tanksonly = true
            },
            -- Shield Wall
            [871] = {
                tanksonly = true
            },
            -- Last Stand
            [12975] = {
                tanksonly = true
            },
            -- Enraged Regeneration
            [55694] = {
                tanksonly = true
            },
            -- Barkskin
            [22812] = {
                tanksonly = true
            },
            -- Survival Instincts
            [61336] = {
                tanksonly = true
            },
            -- Frenzied Regeneration
            [22842] = {
                tanksonly = true
            }
        }
    }
}