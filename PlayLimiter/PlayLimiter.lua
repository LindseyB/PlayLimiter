--------------------------------------------------------------------------
-- PlayLimiter
-- Daily play time limits (separate weekday / weekend) with annoying puzzles
-- that must be solved to earn extra time.
--------------------------------------------------------------------------

local DB
local ready = false
local overlay, panel, timerFrame
local puzzleActive = false
local pendingChallenge = false
local combatNotified = false
local streak = 0
local currentToken = 0
local lastKind
local onSuccess            -- function run when the whole challenge is passed
local warned = {}
local BuildSettings   -- defined near the bottom

local defaults = {
    weekdayMinutes  = 120,  -- Mon-Fri daily limit (0 = no limit)
    weekendMinutes  = 240,  -- Sat-Sun daily limit (0 = no limit)
    puzzlesRequired = 3,    -- puzzles in a row needed to earn more time
    bonusMinutes    = 15,   -- extra time granted per completed challenge
    showTimer       = true,
    session         = { elapsed = 0, bonusSec = 0, day = "" },  -- resets only when the date changes
}

local function Print(msg)
    print("|cff33ff99PlayLimiter:|r " .. msg)
end

local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            MergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function FormatTime(sec)
    sec = math.max(0, math.floor(sec))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

local function IsWeekend()
    local wday = date("*t").wday   -- 1 = Sunday ... 7 = Saturday
    return wday == 1 or wday == 7
end

local function Today()
    return date("%Y-%m-%d")
end

-- Starts a fresh day's allowance when the calendar date changes
-- (at login, or at midnight while playing). Returns true if it reset.
local function EnsureToday()
    local s, today = DB.session, Today()
    if s.day == today then return false end
    s.day, s.elapsed, s.bonusSec = today, 0, 0
    wipe(warned)
    return true
end

local function BaseLimitSec()
    local m = IsWeekend() and DB.weekendMinutes or DB.weekdayMinutes
    if not m or m <= 0 then return nil end
    return m * 60
end

local function RemainingSec()
    local base = BaseLimitSec()
    if not base then return nil end
    return base + DB.session.bonusSec - DB.session.elapsed
end

--------------------------------------------------------------------------
-- Challenge flow
--------------------------------------------------------------------------
local NextPuzzle   -- forward declaration
local logoutHidePending = false

-- The logout button is a secure frame: it can only be shown/hidden out of combat.
local function SetLogoutShown(show)
    if InCombatLockdown() then
        logoutHidePending = not show
        return
    end
    logoutHidePending = false
    panel.logout:SetShown(show)
end

local function FinishChallenge()
    puzzleActive = false
    pendingChallenge = false
    combatNotified = false
    currentToken = currentToken + 1
    overlay:Hide()
    SetLogoutShown(false)
    local fn = onSuccess
    onSuccess = nil
    if fn then fn() end
end

local function PuzzleSolved()
    streak = streak + 1
    currentToken = currentToken + 1
    if streak >= DB.puzzlesRequired then
        panel.status:SetText("|cff33ff33All done!|r")
        C_Timer.After(0.6, FinishChallenge)
    else
        panel.status:SetText("|cff33ff33Correct!|r")
        C_Timer.After(0.8, NextPuzzle)
    end
end

local function PuzzleFailed(extra)
    streak = 0
    currentToken = currentToken + 1
    panel.onSubmit = nil
    for _, b in ipairs(panel.simon) do b.locked = true end
    panel.status:SetText("|cffff3333Wrong! Streak reset to zero. " .. (extra or "") .. "|r")
    C_Timer.After(1.5, NextPuzzle)
end

local function StartChallenge(title, successFn)
    if puzzleActive then return end
    onSuccess = successFn
    puzzleActive = true
    streak = 0
    lastKind = nil
    panel.title:SetText(title)
    overlay:Show()
    SetLogoutShown(true)
    NextPuzzle()
end

-- Starts the challenge now, or as soon as combat ends.
local function RequestChallenge(title, successFn)
    if puzzleActive then return end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        pendingChallenge = true
        onSuccess = successFn
        panel.pendingTitle = title
        if not combatNotified then
            combatNotified = true
            Print("Time limit reached. Puzzles will begin when combat ends.")
        end
        return
    end
    StartChallenge(title, successFn)
end

local function GrantBonus()
    local base = BaseLimitSec() or 0
    -- Remaining time becomes exactly the bonus, regardless of any overshoot.
    DB.session.bonusSec = DB.session.elapsed - base + DB.bonusMinutes * 60
    wipe(warned)
    Print(string.format("Challenge passed. You earned %d more minutes.", DB.bonusMinutes))
end

--------------------------------------------------------------------------
-- UI construction
--------------------------------------------------------------------------
local function AddBorder(f)
    local function edge()
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.8, 0.6, 0.1, 1)
        return t
    end
    local top = edge();    top:SetPoint("TOPLEFT");       top:SetPoint("TOPRIGHT");       top:SetHeight(2)
    local bot = edge();    bot:SetPoint("BOTTOMLEFT");    bot:SetPoint("BOTTOMRIGHT");    bot:SetHeight(2)
    local lef = edge();    lef:SetPoint("TOPLEFT");       lef:SetPoint("BOTTOMLEFT");     lef:SetWidth(2)
    local rig = edge();    rig:SetPoint("TOPRIGHT");      rig:SetPoint("BOTTOMRIGHT");    rig:SetWidth(2)
end

local function SetLit(btn, on)
    local k = on and 1 or 0.3
    local c = btn.color
    btn.tex:SetColorTexture(c[1] * k, c[2] * k, c[3] * k, 1)
end

local function SubmitInput()
    local text = panel.input:GetText() or ""
    panel.input:SetText("")
    local fn = panel.onSubmit
    if fn then
        panel.onSubmit = nil
        fn(text)
    end
end

local function BuildUI()
    -- Full-screen blocker -------------------------------------------------
    overlay = CreateFrame("Frame", "PlayLimiterOverlay", UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetFrameLevel(100)
    overlay:EnableMouse(true)
    overlay:EnableKeyboard(true)   -- swallow keystrokes (typing in the box still works)
    overlay:Hide()
    local dim = overlay:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.88)

    -- Puzzle panel --------------------------------------------------------
    panel = CreateFrame("Frame", nil, overlay)
    panel:SetSize(540, 340)
    panel:SetPoint("CENTER")
    panel:EnableMouse(true)
    local pbg = panel:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0.08, 0.06, 0.04, 1)
    AddBorder(panel)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOP", 0, -14)

    panel.progress = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.progress:SetPoint("TOP", 0, -38)

    panel.prompt = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.prompt:SetPoint("TOP", 0, -66)
    panel.prompt:SetWidth(490)

    panel.display = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.display:SetPoint("TOP", 0, -112)
    panel.display:SetWidth(490)

    panel.input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.input:SetSize(220, 30)
    panel.input:SetPoint("TOP", 0, -165)
    panel.input:SetAutoFocus(false)
    panel.input:SetMaxLetters(30)
    panel.input:SetScript("OnEnterPressed", SubmitInput)

    panel.submit = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.submit:SetSize(110, 26)
    panel.submit:SetPoint("TOP", 0, -205)
    panel.submit:SetText("Submit")
    panel.submit:SetScript("OnClick", SubmitInput)

    -- Wordle guess history (left column)
    panel.board = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.board:SetPoint("TOPLEFT", 40, -112)
    panel.board:SetWidth(130)
    panel.board:SetJustifyH("LEFT")
    panel.board:SetJustifyV("TOP")
    panel.board:SetSpacing(4)
    panel.board:Hide()

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.status:SetPoint("BOTTOM", 0, 50)
    panel.status:SetWidth(490)

    -- Logout() is a protected function, so addon code can't call it directly
    -- (that's what produced "action was prevented"). A secure action button
    -- running a /logout macro counts as the player's own click and is allowed.
    -- It's parented/anchored to UIParent rather than the overlay so hiding the
    -- overlay never touches a protected frame during combat.
    panel.logout = CreateFrame("Button", "PlayLimiterLogoutButton", UIParent,
        "SecureActionButtonTemplate, UIPanelButtonTemplate")
    panel.logout:SetSize(190, 24)
    panel.logout:SetPoint("BOTTOM", UIParent, "CENTER", 0, -170 + 14)  -- bottom of the panel
    panel.logout:SetFrameStrata("FULLSCREEN_DIALOG")
    panel.logout:SetFrameLevel(150)
    panel.logout:SetText("Never mind, log out")
    panel.logout:RegisterForClicks("AnyUp", "AnyDown")
    panel.logout:SetAttribute("type", "macro")
    panel.logout:SetAttribute("macrotext", "/logout")
    panel.logout:Hide()

    -- Memory-game buttons
    panel.simon = {}
    local colors = { {1, 0.2, 0.2}, {0.2, 1, 0.2}, {0.3, 0.5, 1}, {1, 0.9, 0.2} }
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, panel)
        b:SetSize(70, 70)
        b:SetPoint("CENTER", panel, "CENTER", (i - 2.5) * 85, -30)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.color = colors[i]
        SetLit(b, false)
        b:Hide()
        panel.simon[i] = b
    end

    -- Runaway button
    panel.jump = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.jump:SetSize(100, 32)
    panel.jump:SetText("CLICK ME")
    panel.jump:Hide()
end

local function ResetWidgets()
    panel.input:SetText("")
    panel.input:ClearFocus()
    panel.input:Hide()
    panel.submit:Hide()
    panel.jump:Hide()
    panel.board:SetText("")
    panel.board:Hide()
    panel.display:SetText("")
    panel.status:SetText("")
    panel.prompt:SetText("")
    panel.onSubmit = nil
    for _, b in ipairs(panel.simon) do
        b:Hide()
        b.locked = true
        SetLit(b, false)
    end
end

local function ShowInput(fn)
    panel.onSubmit = fn
    panel.input:SetText("")
    panel.input:Show()
    panel.submit:Show()
    panel.input:SetFocus()
end

--------------------------------------------------------------------------
-- Puzzles
--------------------------------------------------------------------------
local puzzles = {}

-- 1. Mental arithmetic
puzzles.math = function()
    -- One easy step, friendly numbers (5s and 10s only).
    local ans, question
    local kind = random(3)
    if kind == 1 then
        local a, b = (random(2) == 1) and 5 or 10, random(2, 9)   -- e.g. 5 x 6
        ans, question = a * b, string.format("%d x %d = ?", a, b)
    elseif kind == 2 then
        local a, b = 10 * random(1, 9), 5 * random(1, 10)          -- e.g. 40 + 25
        ans, question = a + b, string.format("%d + %d = ?", a, b)
    else
        local a = 10 * random(5, 10)                               -- 50 .. 100
        local b = 5 * random(1, 9)                                 -- 5 .. 45
        ans, question = a - b, string.format("%d - %d = ?", a, b)
    end
    panel.prompt:SetText("Quick one! No calculator.")
    panel.display:SetText(question)
    ShowInput(function(text)
        if tonumber(text) == ans then PuzzleSolved() else PuzzleFailed() end
    end)
end

-- 2. Memorize a 4-digit code that vanishes, then type it
puzzles.memory = function()
    local code = ""
    for _ = 1, 4 do code = code .. random(0, 9) end
    local token = currentToken
    panel.prompt:SetText("Memorize this code. It vanishes in 4 seconds. Then type it in.")
    panel.display:SetText(code)
    C_Timer.After(4, function()
        if token ~= currentToken then return end
        panel.display:SetText("? ? ? ?")
        ShowInput(function(text)
            if (text:gsub("%s", "")) == code then PuzzleSolved() else PuzzleFailed() end
        end)
    end)
end

-- 3. Pattern repeat
puzzles.simon = function()
    local len = 4 + streak
    local seq = {}
    for i = 1, len do seq[i] = random(4) end
    local token = currentToken
    local pos = 1
    panel.prompt:SetText("Watch the pattern. Then repeat it. Pattern length: " .. len)
    for i, b in ipairs(panel.simon) do
        b:Show()
        b.locked = true
        b:SetScript("OnClick", function()
            if b.locked or token ~= currentToken then return end
            SetLit(b, true)
            C_Timer.After(0.2, function() SetLit(b, false) end)
            if seq[pos] ~= i then
                PuzzleFailed()
                return
            end
            pos = pos + 1
            if pos > len then PuzzleSolved() end
        end)
    end
    for i, v in ipairs(seq) do
        C_Timer.After(i * 0.8, function()
            if token ~= currentToken then return end
            SetLit(panel.simon[v], true)
            C_Timer.After(0.45, function() SetLit(panel.simon[v], false) end)
        end)
    end
    C_Timer.After((len + 1) * 0.8, function()
        if token ~= currentToken then return end
        panel.prompt:SetText("Your turn!")
        for _, b in ipairs(panel.simon) do b.locked = false end
    end)
end

-- 4. Wordle: guess the 5-letter word, unlimited guesses
local words = {
    "GNOME", "TROLL", "DWARF", "HORDE", "ROGUE", "QUEST", "DRAKE", "TOTEM",
    "SPELL", "MOUNT", "ARMOR", "BLADE", "STAFF", "FLASK", "GUILD", "FEAST",
    "BEAST", "CHEST", "CLOTH", "PLATE", "GHOST", "DEMON", "SKULL", "CROWN",
    "TOWER", "STORM", "FLAME", "FROST", "HONOR", "MAGIC", "SWORD", "SMITE",
}
local GREEN, YELLOW, GREY = "ff6aaa64", "ffc9b458", "ff808080"

-- Returns the guess as colored letters, Wordle-style (handles repeated letters).
local function ScoreGuess(guess, answer)
    local colors, left = {}, {}
    for i = 1, 5 do
        local a = answer:sub(i, i)
        if guess:sub(i, i) == a then
            colors[i] = GREEN
        else
            left[a] = (left[a] or 0) + 1
        end
    end
    for i = 1, 5 do
        if not colors[i] then
            local g = guess:sub(i, i)
            if (left[g] or 0) > 0 then
                colors[i], left[g] = YELLOW, left[g] - 1
            else
                colors[i] = GREY
            end
        end
    end
    local out = {}
    for i = 1, 5 do out[i] = "|c" .. colors[i] .. guess:sub(i, i) .. "|r" end
    return table.concat(out, " ")
end

puzzles.wordle = function()
    local answer = words[random(#words)]
    local history = {}
    panel.prompt:SetText("Guess the 5-letter word. Unlimited guesses!\n" ..
        "|c" .. GREEN .. "Green|r = right spot,  |c" .. YELLOW .. "yellow|r = wrong spot,  " ..
        "|c" .. GREY .. "grey|r = not in the word.")
    panel.display:SetText("_ _ _ _ _")
    panel.board:Show()
    local function Guess(text)
        local guess = strupper(strtrim(text))
        if not guess:match("^%a%a%a%a%a$") then
            panel.status:SetText("Please type exactly 5 letters.")
            ShowInput(Guess)
            return
        end
        panel.status:SetText("")
        history[#history + 1] = ScoreGuess(guess, answer)
        -- Show the most recent 6 guesses
        local first = math.max(1, #history - 5)
        panel.board:SetText(table.concat(history, "\n", first))
        panel.display:SetText("Guess " .. (#history + 1))
        if guess == answer then
            PuzzleSolved()
        else
            ShowInput(Guess)
        end
    end
    ShowInput(Guess)
end

-- 5. Runaway button
puzzles.jump = function()
    local need, clicks = 7, 0
    local token = currentToken
    local jump = panel.jump
    panel.prompt:SetText("Click the button " .. need .. " times. It does not like being clicked.")
    panel.display:SetText("0 / " .. need)
    local function Move()
        jump:ClearAllPoints()
        jump:SetPoint("CENTER", panel, "CENTER", random(-200, 200), random(-100, 30))
    end
    local function Wander()
        if token ~= currentToken then return end
        Move()
        C_Timer.After(0.9, Wander)
    end
    jump:Show()
    Move()
    jump:SetScript("OnClick", function()
        if token ~= currentToken then return end
        clicks = clicks + 1
        panel.display:SetText(clicks .. " / " .. need)
        if clicks >= need then
            jump:Hide()
            PuzzleSolved()
        else
            Move()
        end
    end)
    C_Timer.After(0.9, Wander)
end

local order = { "math", "memory", "simon", "wordle", "jump" }

NextPuzzle = function()
    if not puzzleActive then return end
    currentToken = currentToken + 1
    ResetWidgets()
    local kind
    repeat kind = order[random(#order)] until kind ~= lastKind
    lastKind = kind
    panel.progress:SetText(string.format("Puzzle %d of %d  (a wrong answer resets your streak)",
        streak + 1, DB.puzzlesRequired))
    puzzles[kind]()
end

--------------------------------------------------------------------------
-- Timer display
--------------------------------------------------------------------------
local function BuildTimer()
    timerFrame = CreateFrame("Frame", "PlayLimiterTimer", UIParent)
    timerFrame:SetSize(210, 24)
    timerFrame:SetFrameStrata("MEDIUM")
    timerFrame:SetMovable(true)
    timerFrame:EnableMouse(true)
    timerFrame:RegisterForDrag("LeftButton")
    timerFrame:SetClampedToScreen(true)
    local bg = timerFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    timerFrame.text = timerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerFrame.text:SetPoint("CENTER")
    timerFrame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
    end)
    timerFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        DB.pos = { p, rp, x, y }
    end)
    if DB.pos then
        timerFrame:SetPoint(DB.pos[1], UIParent, DB.pos[2], DB.pos[3], DB.pos[4])
    else
        timerFrame:SetPoint("TOP", UIParent, "TOP", 0, -8)
    end
    timerFrame:SetShown(DB.showTimer)
end

local function UpdateTimerText()
    if not timerFrame then return end
    local rem = RemainingSec()
    if not rem then
        timerFrame.text:SetText("Play time: no limit today")
    else
        local color = "ffffffff"
        if rem <= 60 then color = "ffff3333" elseif rem <= 300 then color = "ffffaa33" end
        timerFrame.text:SetText(string.format("%s left: |c%s%s|r",
            IsWeekend() and "Weekend" or "Weekday", color, FormatTime(rem)))
    end
end

--------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------
local WARN_AT = { 60, 300, 600 }   -- ascending, seconds

local function CheckLimit()
    local rem = RemainingSec()
    if not rem or puzzleActive then return end

    if rem <= 0 then
        RequestChallenge("Time's up! Prove you deserve more.", GrantBonus)
        return
    end

    for _, t in ipairs(WARN_AT) do
        if rem <= t and not warned[t] then
            for _, t2 in ipairs(WARN_AT) do
                if t2 >= t then warned[t2] = true end
            end
            local msg = string.format("%d minute(s) of play time left today.", math.ceil(rem / 60))
            Print(msg)
            if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.5, 0.1, 1) end
            if SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
            break
        end
    end
end

local acc = 0
local loop = CreateFrame("Frame")
loop:SetScript("OnUpdate", function(_, dt)
    if not ready then return end
    acc = acc + dt
    if acc < 0.5 then return end
    local step = acc
    acc = 0
    if EnsureToday() then Print("It's a new day. Your play time has been reset.") end
    if not puzzleActive then
        DB.session.elapsed = DB.session.elapsed + step
    end
    UpdateTimerText()
    CheckLimit()
end)

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "PlayLimiter" then
        PlayLimiterDB = PlayLimiterDB or {}
        DB = PlayLimiterDB
        MergeDefaults(DB, defaults)

    elseif event == "PLAYER_LOGIN" then
        BuildUI()
        BuildTimer()
        BuildSettings()
        DB.breakMinutes, DB.session.lastSeen = nil, nil   -- old settings, no longer used
        if EnsureToday() then
            Print("New day, fresh play time. Type /pl to open settings.")
        else
            Print("Welcome back. " .. FormatTime(DB.session.elapsed) .. " played so far today.")
        end
        ready = true

    elseif event == "PLAYER_REGEN_ENABLED" then
        if logoutHidePending and not puzzleActive then SetLogoutShown(false) end
        if pendingChallenge and not puzzleActive then
            local title = panel.pendingTitle or "Time's up!"
            pendingChallenge = false
            StartChallenge(title, onSuccess)
        end
    end
end)

--------------------------------------------------------------------------
-- Settings panel (Options > AddOns > Play Limiter)
-- Clicking Save applies changes immediately.
--------------------------------------------------------------------------
local settingsPanel, settingsCategory

local FIELDS = {
    { key = "weekdayMinutes",  label = "Weekday daily limit (minutes)",
      hint = "Monday to Friday. 0 = no limit." },
    { key = "weekendMinutes",  label = "Weekend daily limit (minutes)",
      hint = "Saturday and Sunday. 0 = no limit." },
    { key = "puzzlesRequired", label = "Puzzles required per challenge", min = 1,
      hint = "Puzzles in a row needed to earn more time." },
    { key = "bonusMinutes",    label = "Minutes earned per challenge", min = 1,
      hint = "Extra play time granted when you pass." },
}

local function RefreshSettings()
    if not settingsPanel or not DB then return end
    for _, f in ipairs(FIELDS) do
        f.edit:SetText(tostring(DB[f.key]))
        f.edit:SetCursorPosition(0)
    end
    settingsPanel.showTimer:SetChecked(DB.showTimer)
end

local function UpdateSettingsStatus()
    if not settingsPanel or not DB then return end
    local rem = RemainingSec()
    settingsPanel.status:SetText(string.format(
        "Today is a %s.   Played today: %s.   Remaining: %s.",
        IsWeekend() and "weekend" or "weekday",
        FormatTime(DB.session.elapsed),
        rem and FormatTime(rem) or "unlimited"))
end

local function ApplySettings()
    for _, f in ipairs(FIELDS) do
        local n = tonumber(f.edit:GetText())
        if not n then n = DB[f.key] end
        n = math.floor(n)
        if n < 0 then n = 0 end
        if f.min and n < f.min then n = f.min end
        DB[f.key] = n
    end
    DB.showTimer = settingsPanel.showTimer:GetChecked() and true or false
    if timerFrame then timerFrame:SetShown(DB.showTimer) end
    RefreshSettings()
    UpdateSettingsStatus()
    Print("Settings saved.")
end

BuildSettings = function()
    local p = CreateFrame("Frame", "PlayLimiterSettings", UIParent)
    p.name = "Play Limiter"
    settingsPanel = p

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Play Limiter")

    local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetWidth(560)
    sub:SetJustifyH("LEFT")
    sub:SetText("Set how much you can play per day on weekdays and weekends. Play time resets at midnight. When time runs out, " ..
        "you must solve puzzles to keep playing. Click Save to apply your changes.")

    p.status = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    p.status:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)

    local y = -130
    for _, f in ipairs(FIELDS) do
        local label = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("TOPLEFT", 16, y)
        label:SetText(f.label)

        local edit = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        edit:SetSize(70, 24)
        edit:SetPoint("TOPLEFT", 24, y - 20)
        edit:SetAutoFocus(false)
        edit:SetNumeric(true)
        edit:SetMaxLetters(5)
        edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.edit = edit

        local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        hint:SetPoint("LEFT", edit, "RIGHT", 12, 0)
        hint:SetText(f.hint)

        y = y - 52
    end

    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 14, y)
    local cbLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cbLabel:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cbLabel:SetText("Show on-screen timer (Shift+drag to move it)")
    p.showTimer = cb

    local save = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    save:SetSize(120, 26)
    save:SetPoint("TOPLEFT", 16, y - 44)
    save:SetText("Save")
    save:SetScript("OnClick", ApplySettings)

    local test = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    test:SetSize(160, 26)
    test:SetPoint("LEFT", save, "RIGHT", 12, 0)
    test:SetText("Test the puzzles")
    test:SetScript("OnClick", function()
        RequestChallenge("Test challenge (no time awarded)", function() Print("Test passed.") end)
    end)

    local elapsed = 0
    p:SetScript("OnShow", function() RefreshSettings(); UpdateSettingsStatus() end)
    p:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            UpdateSettingsStatus()
        end
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(p, p.name)
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(p)
    end
    RefreshSettings()
end

local function OpenSettings()
    if Settings and Settings.OpenToCategory and settingsCategory then
        local id = settingsCategory.GetID and settingsCategory:GetID() or settingsCategory.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(settingsPanel)
        InterfaceOptionsFrame_OpenToCategory(settingsPanel)
    else
        Print("Open the game menu > Options > AddOns > Play Limiter.")
    end
end

SLASH_PLAYLIMITER1 = "/playlimit"
SLASH_PLAYLIMITER2 = "/pl"
SlashCmdList["PLAYLIMITER"] = function()
    if ready then OpenSettings() end
end
