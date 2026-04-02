![ScreenShot](https://advent-wow.ru/HomeCheck/HomeCheck.png)

# Why HomeCheck?

- Works in raid/party/solo
- Receives cooldowns info sent by most popular cooldown addons, if any of your raid members use them:
    - oRA
    - oRA3
    - RaidCooldowns
    - CTRA
    - BLT
    - FatCooldowns
    - more addons can be added by request
- Shares cooldowns info with other HomeCheck users in raid
- Up to 10 separate frames to sort cooldowns, 2 used by default:
    - Frame 1: important raid defensives (Divine Sacrifice, Hand of Sacrifice, Guardian Spirit etc.)
    - Frame 2: all other raid cooldowns (Misdirection, Innervate, Rebirth, etc.)

  You can adjust everything to your needs and move spells between frames however you like
- Spells priority: adjust which spells should be displayed above others.
- Gray out players out of range (>80 yards) to improve visual perception (very useful on Halion to filter out players from other realm)
- Hide cooldowns when player leaves raid or goes offline
- Restore cooldowns after relog or UI reload
- Adjust frame size, fonts, textures and more
- Scans talents and glyphs to detect which spells raid members have and get their precise cooldowns duration
- Correct Misdirection and Tricks of Trade cooldown duration (can be more than 30 sec)
- Tracks Guardian Spirit proc and updates its cooldown
- Tracks Readiness
- Displays double Rebirth on same target
- Link cooldown duration to raid chat
- Bug fixes, updates and support
- etc.

# Settings

- Settings are available in default addons options panel interface:  
  <kbd>Esc</kbd> &rarr; Interface &rarr; Addons &rarr; HomeCheck  
  ![ScreenShot](https://advent-wow.ru/HomeCheck/Settings.png)
- "Frames" are simply multiple addon windows you can assign different cooldowns to
- By default, some defensive cooldowns are assigned to Frame 1, everything else to Frame 2
- Each frame settings can be adjusted individually or copied from other frame
- To move a frame drag its top-left corner  
  ![ScreenShot](https://advent-wow.ru/HomeCheck/Move.png)

# Known issues

- MD target can be empty in some cases, most likely caused by communication from other cooldown addons (requires further investigation).
- In rare cases, Rebirth cast may trigger incorrect Rebirth cooldown for other druid who did not finish Rebirth cast or cast failed (requires further investigation).
- Guardian Spirit heal will not update GS cooldown if GS cast was not detected beforehand (very rare case in specific situations).

# Something does not work?

- If you had previous version of addon installed try deleting settings file
<code>\WTF\Account\\<ACCOUNT_NAME\>\SavedVariables\HomeCheck.lua</code>. All addon settings will be lost.
- Report bug here or contact me directly.

# Donate

https://dalink.to/homerocker or contact me in any other way
