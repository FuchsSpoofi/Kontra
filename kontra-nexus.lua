-- Kontra Nexus 4.6 / Matcha. RightShift: menu. End: hide everything.
-- Uses only replicated rigs. Enemy identities/health are not invented.
local previousConfig = _G.KontraVision and _G.KontraVision.config
local uiSource = _G.KontraNexaSource or game:HttpGet("https://raw.githubusercontent.com/OgTen/Nexa-UI/refs/heads/main/nexa-ui.lua")
local uiChunk, compileError = loadstring(uiSource)
if not uiChunk then print("Nexus UI compile error:", compileError) return end
_G.KontraNexaSource=uiSource

if _G.KontraVision and _G.KontraVision.cleanup then pcall(_G.KontraVision.cleanup) end
if type(Nexa) == "table" and type(Nexa.Destroy) == "function" then pcall(function() Nexa:Destroy() end) end
local loaded, uiError = pcall(uiChunk)
if not loaded then print("Nexus UI error:", uiError) return end
local ui = Nexa
if type(ui) ~= "table" then print("Nexus UI unavailable") return end

local Players = game:GetService("Players")
local World = game:GetService("Workspace")
local Run = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local me = Players.LocalPlayer
local GameStats = game:GetService("ReplicatedStorage"):FindFirstChild("GameStats")
local WHITE = Color3.fromRGB(241, 247, 255)
local INK = Color3.fromRGB(12, 17, 25)
local config = {
    enabled = true, box = "Corners", labels = true, distance = true,
    skeleton = true, arrows = false, tracers = false, status = true,
    visibility = false, visibleOnly = false, range = 1200, width = 2,
    opacity = 1, fontSize = 12,
    enemyColor = Color3.fromRGB(255, 82, 109),
    visibleColor = Color3.fromRGB(72, 232, 221),
    skeletonWidth = 1.5, lastSeen = true, lastSeenSeconds = 3,
    lastSeenPolicy = "Replication loss", lastSeenColor = Color3.fromRGB(167, 160, 221),
    bomb = true, bombTimer = true, bombArrows = true, bombColor = Color3.fromRGB(255, 201, 74),
    gunshots = true, shotSeconds = 2.5, shotRange = 2500, shotArrows = true,
    shotsEnemyOnly = false, shotColor = Color3.fromRGB(255, 151, 64), shotPinSize = 14,
    refreshProfile = "Fastest", refreshInterval = 0.025,
    distanceScaling = true, scaleNear = 60, scaleFar = 500, minimumScale = 0.7,
    performanceHud = true, defuseProgress = true,
    defuseColor = Color3.fromRGB(108, 237, 173),
    declutter = true, labelBudget = 18, labelSpacing = 4, mergeLabels = true,
    footsteps = true, footSeconds = 1.2, footRange = 90, footArrows = true,
    footHideAllies = true, footEnemyOnly = false, footLandings = true, footPinSize = 10,
    footColor = Color3.fromRGB(80, 213, 255),
    heightIndicators = true, bombPinSize = 14, bombAudioFallback = true,
    quietMovement = true, quietSpeed = 12, quietWindow = 0.6, quietRange = 80,
    quietColor = Color3.fromRGB(194, 153, 255),
}
if previousConfig then
    for key, value in pairs(previousConfig) do
        if config[key] ~= nil and type(config[key]) == type(value) then config[key] = value end
    end
end
-- Explicitly enable the newly requested skeleton feature on this upgrade.
if not previousConfig or not previousConfig.skeletonWidth then config.skeleton = true end
-- Migrate the old restrictive default, without changing a 4.3 user's choice.
if previousConfig and previousConfig.shotPinSize == nil then
    config.shotsEnemyOnly=false;config.shotRange=math.max(2500,config.shotRange)
end
local state = {running = true, open = true, targets = {}, pool = {}, connections = {}, ui = ui, version="4.6",
    camera = nil, team = nil, settleUntil = 0, seen = {}, errors = 0,
    stats = {enemies = 0, allies = 0, self = 0, pending = 0}, config = config, frames = 0,
    contacts = {}, ghosts = {}, ghostPool = {}, shotPool = {}, shots = {}, soundSeen = {},
    friendPositions = {}, phase = nil, bombData = nil, soundWarm = false,
    shotEvents = 0, soundEvents = 0, ignoredShotEvents = 0, ghostFrames = 0, bombFrames = 0, shotFrames = 0,
    rigCache = {}, teams = {}, nextRosterAt = 0, nextUiAt = 0,
    collectPasses = 0, shotPasses = 0, collectMs = 0, maxCollectMs = 0, startedAt = tick(),
    performance = {fps=0,discovery=0,sounds=0,collectMs=0,renderMs=0,ping=0},
    nextMetricsAt=0,renderMs=0,lastCollectAt=0,defuseFrames=0,
    shotRejects={self=0,ally=0,range=0,unlinked=0,invalid=0},
    farthestSound=0,farthestShot=0,shotSequence=0,
    lastShotCollectAt=0,shotScanErrors=0,shotStage="starting",soundCandidates=0,soundParts=0,
    footsteps={},footPool={},footSoundEvents=0,footEvents=0,footFrames=0,footSequence=0,footCandidates=0,
    footRejects={self=0,ally=0,range=0,unlinked=0,invalid=0},farthestFootSound=0,farthestFoot=0,
    quietFrames=0,bombPinPosition=nil,
    bombScanPasses=0,bombScanErrors=0,lastBombCollectAt=0,bombModelCount=0,bombCueEvents=0,
    labelStats={requested=0,shown=0,hidden=0,moved=0}}
_G.KontraVision = state

-- Nexa's working Drawing renderer uses 1 for solid colored foregrounds.
local function drawing(kind, z)
    local d = Drawing.new(kind)
    d.Visible = false
    d.Transparency = 1
    d.Color = config.enemyColor
    d.ZIndex = z or 10
    return d
end
local function text(size)
    local d = drawing("Text", 12)
    d.Size = size or 12
    d.Font = 11
    d.Center = true
    d.Outline = false
    return d
end
local skeletonPairs = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
}
for i = 1, 32 do
    local e = {all = {}, corners = {}, bones = {}}
    local function add(d) e.all[#e.all + 1] = d return d end
    for j = 1, 8 do e.corners[j] = add(drawing("Line")) end
    for j = 1, #skeletonPairs do e.bones[j] = add(drawing("Line")) end
    e.box = add(drawing("Square")); e.box.Filled = false
    e.label = add(text()); e.distance = add(text(10))
    e.tracer = add(drawing("Line", 8))
    e.arrow = add(drawing("Triangle", 11)); e.arrow.Filled = true
    state.pool[i] = e
end
local function marker()
    local e = {all = {}}
    local function add(d) e.all[#e.all + 1] = d return d end
    e.ring = add(drawing("Circle", 13)); e.ring.NumSides = 24; e.ring.Filled = false
    e.ring.Thickness = 2
    e.label = add(text(11)); e.label.ZIndex = 14
    e.arrow = add(drawing("Triangle", 13)); e.arrow.Filled = true
    e.crossA = add(drawing("Line", 13)); e.crossB = add(drawing("Line", 13))
    return e
end
for i = 1, 32 do
    local e = {all = {}, dash = {}}
    for j = 1, 8 do e.dash[j] = drawing("Line"); e.all[#e.all+1] = e.dash[j] end
    e.label = text(11); e.all[#e.all+1] = e.label
    state.ghostPool[i] = e
end
for i = 1, 24 do state.shotPool[i] = marker() end
for i = 1, 20 do state.footPool[i] = marker() end
local bombMarker = marker()
state.bombMarker=bombMarker
local bombHud = text(13)
state.bombHud=bombHud
local bombBar = drawing("Line", 12)
local bombBarBack = drawing("Line", 11)
local defuseHud = text(12)
local defuseBar = drawing("Line",12)
local defuseBarBack = drawing("Line",11)
local perfBack = drawing("Square",18);perfBack.Filled=true;perfBack.Color=INK;perfBack.Rounding=4
local perfLineA=text(11);perfLineA.Center=false;perfLineA.ZIndex=20
local perfLineB=text(10);perfLineB.Center=false;perfLineB.ZIndex=20
local perfAccent=drawing("Line",20)
local hud = text(11); hud.Center = false
local hudRule = drawing("Line", 12); hudRule.Thickness = 3
local function hide(e) for _, d in ipairs(e.all) do d.Visible = false end end
local function hideAll()
    for _, e in ipairs(state.pool) do hide(e) end
    for _, e in ipairs(state.ghostPool) do hide(e) end
    for _, e in ipairs(state.shotPool) do hide(e) end
    for _, e in ipairs(state.footPool) do hide(e) end
    hide(bombMarker); bombHud.Visible=false; bombBar.Visible=false; bombBarBack.Visible=false
    defuseHud.Visible=false;defuseBar.Visible=false;defuseBarBack.Visible=false
    perfBack.Visible=false;perfLineA.Visible=false;perfLineB.Visible=false;perfAccent.Visible=false
    hud.Visible = false; hudRule.Visible = false
end
state.cleanup = function()
    if not state.running then return end
    state.running = false
    for _, c in pairs(state.connections) do pcall(function() c:Disconnect() end) end
    for _, e in ipairs(state.pool) do for _, d in ipairs(e.all) do pcall(function() d:Remove() end) end end
    for _, group in ipairs({state.ghostPool,state.shotPool,state.footPool,{bombMarker}}) do
        for _, e in ipairs(group) do for _, d in ipairs(e.all) do pcall(function() d:Remove() end) end end
    end
    bombHud:Remove(); bombBar:Remove(); bombBarBack:Remove()
    defuseHud:Remove();defuseBar:Remove();defuseBarBack:Remove()
    perfBack:Remove();perfLineA:Remove();perfLineB:Remove();perfAccent:Remove()
    hud:Remove(); hudRule:Remove()
    if _G.KontraVision == state then _G.KontraVision = nil end
end
ui:OnDestroy(state.cleanup)

local teamStatus, targetStatus, nearestStatus, bombStatus, shotStatus, refreshStatus, performanceStatus, defuseStatus
local declutterStatus, shotRangeStatus, shotStrictControl, shotRangeControl, shotScanStatus
local footStatus,footScanStatus,footRangeStatus
local quietStatus,bombAnchorStatus,bombScanStatus
local function validPosition(p)
    return p and p.X == p.X and p.Y == p.Y and p.Z == p.Z
        and math.abs(p.X) < 100000 and math.abs(p.Y) < 100000 and math.abs(p.Z) < 100000
end
local function validAnchor(part,model)
    if not part then return nil end
    local class=part.ClassName
    if class~="Part" and class~="MeshPart" and class~="UnionOperation" then return nil end
    if not part.Parent or not part:IsDescendantOf(model) then return nil end
    local p=part.Position
    return validPosition(p) and p or nil
end
local function positionOf(model)
    -- Matcha can return an invalid but truthy PrimaryPart wrapper. Prefer a
    -- real named Handle, and validate every fallback belongs to this model.
    local handle=model:FindFirstChild("Handle")
    local p=validAnchor(handle,model)
    if p then return p,handle,"Handle" end
    local primary=model.PrimaryPart
    p=validAnchor(primary,model)
    if p then return p,primary,"PrimaryPart" end
    local display=model:FindFirstChild("Display")
    local part=display and display:FindFirstChild("Part")
    p=validAnchor(part,model)
    if p then return p,part,"Display" end
    return nil
end
state.resolveBombAnchor=positionOf
local function isBombModel(model)
    if model:GetAttribute("WeaponName")=="Bomb" then return true end
    -- Fallback only to the verified C4 model signature, not any unlabelled gun.
    local display=model:FindFirstChild("Display")
    local part=display and display:FindFirstChild("Part")
    local surface=part and part:FindFirstChild("SurfaceGui")
    return model:FindFirstChild("HandleMotorLeft")~=nil and surface~=nil
end
state.isBombModel=isBombModel
local BOMB_CUE_LIFETIME=1.75
local function recordBombCue(name,position,now)
    if name~="Bomb.c4_beep" and name~="Bomb.c4-plant-quiet" then return false end
    if not validPosition(position) then return false end
    state.latestBombCue={position=position,at=now,map=state.map}
    state.bombCueEvents=state.bombCueEvents+1
    return true
end
state.recordBombCue=recordBombCue
local function getBombPosition(data,now)
    if not data or now-(data.observedAt or 0)>0.25 then return nil end
    if data.heard then
        local age=now-(data.sampledAt or 0)
        if not config.bombAudioFallback or data.map~=state.map or age<0 or age>BOMB_CUE_LIFETIME then return nil end
        return validPosition(data.position) and data.position or nil
    end
    -- Collection establishes the bomb's folder. During rendering, validate
    -- the live anchor's ownership rather than a second folder-wrapper read.
    return data.model and data.model.Parent and validAnchor(data.part,data.model) or nil
end
state.getBombPosition=getBombPosition
local function scanBombFolder(folder,planted,now)
    if not folder then return nil,0 end
    local children=folder:GetChildren()
    for _,model in ipairs(children) do
        -- BombExplosion is a Part, whereas planted C4 entities are Models.
        if model.ClassName=="Model" and (planted or isBombModel(model)) then
            local pos,part,source=positionOf(model)
            if pos then return {position=pos,part=part,model=model,folderAddress=folder.Address,
                source=source,planted=planted,kind=planted and "PLANTED BOMB" or "DROPPED BOMB",observedAt=now},#children end
        end
    end
    return nil,#children
end
state.scanBombFolder=scanBombFolder
local function heightTag(position,cameraPosition)
    if not config.heightIndicators then return "" end
    local delta=position.Y-cameraPosition.Y
    if delta>6 then return " / ABOVE" end
    if delta< -6 then return " / BELOW" end
    return ""
end
state.heightTag=heightTag
local function distanceScale(distance)
    if not config.distanceScaling then return 1 end
    local fraction=math.max(0,math.min(1,(distance-config.scaleNear)/math.max(1,config.scaleFar-config.scaleNear)))
    return 1-fraction*(1-config.minimumScale)
end
state.distanceScale=distanceScale
local function defuseDigits(value)
    if type(value)~="string" or #value>8 then return nil end
    if value=="" then return 0 end
    if not string.match(value,"^%d+$") or string.sub("75384270",1,#value)~=value then return nil end
    return #value
end
state.defuseDigits=defuseDigits
local function readDefuseDisplay(model)
    local address=model.Address
    if address~=state.defuseModelAddress then
        state.defuseModelAddress=address
        local display=model:FindFirstChild("Display")
        local part=display and display:FindFirstChild("Part")
        local surface=part and part:FindFirstChild("SurfaceGui")
        state.defuseDisplay=surface and surface:FindFirstChild("TextLabel")
    end
    return state.defuseDisplay and defuseDigits(state.defuseDisplay.Text) or nil
end
local function updateMetrics(now)
    if now<state.nextMetricsAt then return end
    local old=state.metricSample
    if old then
        local dt=math.max(0.001,now-old.at)
        local ping=0
        if type(GetPingValue)=="function" then local ok,n=pcall(GetPingValue);if ok then ping=tonumber(n) or 0 end end
        state.performance={fps=(state.frames-old.frames)/dt,discovery=(state.collectPasses-old.collect)/dt,
            sounds=(state.shotPasses-old.shots)/dt,collectMs=state.collectMs,renderMs=state.renderMs,ping=ping}
        local p=state.performance
        state.perfTextA=string.format("NEXUS  |  %.0f FPS  |  %.0fms ping",p.fps,p.ping)
        state.perfTextB=string.format("ESP %.0fHz / SOUNDS %.0fHz / POLL %.1fms",p.discovery,p.sounds,p.collectMs)
        if performanceStatus then performanceStatus:SetValue(string.format("%.0f FPS / %.0f Hz / %.1fms collect",p.fps,p.discovery,p.collectMs),"success") end
    end
    state.metricSample={at=now,frames=state.frames,collect=state.collectPasses,shots=state.shotPasses}
    state.nextMetricsAt=now+0.5
end
local function collectBomb(now)
    state.bombScanPasses=state.bombScanPasses+1
    local debris = World:FindFirstChild("Debris")
    local phase = GameStats and GameStats:GetAttribute("State")
    local timeValue = GameStats and tonumber(GameStats:GetAttribute("Time"))
    -- Ignore sentinel round clocks; they are not a valid bomb countdown.
    if timeValue and (timeValue<0 or timeValue>120) then timeValue=nil end
    if phase ~= state.timerPhase or timeValue ~= state.timerValue then
        state.timerPhase, state.timerValue, state.timerAt = phase, timeValue, now
    end
    -- Inspect the planted entity even before/without the round-state label.
    local data,count=scanBombFolder(debris and debris:FindFirstChild("Bomb"),true,now)
    state.bombModelCount=count
    if data then
        data.defuseDigits=readDefuseDisplay(data.model)
    elseif phase=="BombPlanted" then
        data={kind="PLANTED BOMB",planted=true,observedAt=now}
        local cue=state.latestBombCue
        if config.bombAudioFallback and cue and cue.map==state.map and now-cue.at>=0 and now-cue.at<=BOMB_CUE_LIFETIME then
            data.position=cue.position;data.heard=true;data.source="Recent bomb audio"
            data.sampledAt=cue.at;data.map=cue.map;data.kind="PLANTED BOMB / HEARD"
        end
    else
        data=scanBombFolder(debris and debris:FindFirstChild("DroppedWeapons"),false,now)
    end
    if data and data.planted then
        -- Do not mistake the normal round clock for a bomb countdown.
        data.time=phase=="BombPlanted" and timeValue or nil
        data.anchor=state.timerAt
        if data.time then state.bombObservedMaximum=math.max(state.bombObservedMaximum or data.time,data.time) end
    else
        state.bombObservedMaximum = nil
        state.defuseModelAddress=nil;state.defuseDisplay=nil
    end
    state.bombData = data
    state.lastBombCollectAt=tick()
    if bombAnchorStatus then
        bombAnchorStatus:SetValue(data and data.part and ("Live "..data.source.." / entity "..data.model.Name)
            or (data and data.heard and "Recent beep position / not live model tracking")
            or (data and "LOCATION UNAVAILABLE: no model or recent beep" or "No bomb position received"),data and data.part and "success" or "accent")
    end
    if bombScanStatus then
        bombScanStatus:SetValue(string.format("Live / %d scans / %d entities / %d beeps / %d errors",
            state.bombScanPasses,count,state.bombCueEvents,state.bombScanErrors),state.bombScanErrors==0 and "success" or "danger")
    end
    if defuseStatus then
        local n=data and data.defuseDigits
        defuseStatus:SetValue(n and n>0 and (n.." / 8 code steps") or "No defuse progress received",n and n>0 and "success" or "accent")
    end
    if bombStatus then
        local value = data and data.kind or "Not planted / carried"
        if data and data.time then value=value.." / "..math.max(0,math.ceil(data.time)).."s" end
        bombStatus:SetValue(value,data and "warning" or "accent")
    end
end
state.collectBomb=collectBomb
local function sampleQuiet(cache,position,now,distance)
    if not validPosition(position) then cache.quiet=false;cache.motionBase=nil;return false end
    cache.motionPosition=position;cache.motionAt=now
    if not config.quietMovement or distance>config.quietRange then
        cache.quiet=false;cache.motionBase=nil;return false
    end
    if not cache.motionBase then
        cache.motionBase=position;cache.motionBaseAt=now;cache.motionStartedAt=now
        cache.slowSince=nil;cache.quiet=false;cache.speed=0;return false
    end
    local dt=now-cache.motionBaseAt
    if dt<0.10 then
        -- A newly received nearby step suppresses an estimate immediately.
        if now-(cache.lastFootAt or -math.huge)<config.quietWindow then cache.quiet=false end
        return cache.quiet
    end
    local delta=position-cache.motionBase
    cache.motionBase=position;cache.motionBaseAt=now
    if dt>0.4 or delta.Magnitude>10 then
        cache.quiet=false;cache.slowSince=nil;cache.motionStartedAt=now;cache.speed=0;return false
    end
    local speed=math.sqrt(delta.X*delta.X+delta.Z*delta.Z)/dt
    cache.speed=speed
    local slow=speed>=0.7 and speed<=config.quietSpeed and math.abs(delta.Y)/dt<4
    if slow then cache.slowSince=cache.slowSince or now else cache.slowSince=nil end
    local enough=cache.slowSince and now-cache.slowSince>=0.18
    cache.quiet=enough and now-cache.motionStartedAt>=config.quietWindow
        and now-(cache.lastFootAt or -math.huge)>=config.quietWindow or false
    return cache.quiet
end
state.sampleQuiet=sampleQuiet
local function noteFootSound(position,now)
    if not validPosition(position) then return end
    for _,cache in pairs(state.rigCache) do
        if cache.motionPosition and now-(cache.motionAt or 0)<0.3 and (position-cache.motionPosition).Magnitude<8 then
            cache.lastFootAt=now;cache.quiet=false
        end
    end
end
state.noteFootSound=noteFootSound
local function collect()
    local now = tick()
    state.collectPasses=state.collectPasses+1
    local camera = World:FindFirstChildOfClass("Camera")
    state.camera = camera
    local team = me:GetAttribute("Team")
    local phase = GameStats and GameStats:GetAttribute("State")
    local map = GameStats and GameStats:GetAttribute("Map")
    local roundReset = phase ~= state.phase and phase ~= "BombPlanted" and phase ~= "RoundTime"
    if team ~= state.team or roundReset or map ~= state.map then
        -- Only a team swap gets a short atomic-transition guard. New targets
        -- have no spawn/detection holdoff and are eligible on their first pass.
        state.settleUntil = state.team and team ~= state.team and now+0.075 or 0
        state.team = team; state.seen = {};state.rigCache={};state.nextRosterAt=0
        state.contacts = {}; state.ghosts = {}; state.shots = {};state.footsteps={};state.latestBombCue=nil
    end
    state.phase, state.map = phase, map
    local stats = {enemies = 0, allies = 0, self = 0, pending = 0,quiet=0}
    local result, seen, live, friends = {}, {}, {}, {}
    local nearest = math.huge
    if camera and (team == "CT" or team == "T") then
        if now>=state.nextRosterAt then
            local roster={}
            for _,player in ipairs(Players:GetPlayers()) do roster[player.Name]=player:GetAttribute("Team") end
            state.teams=roster;state.nextRosterAt=now+0.5
        end
        local teams=state.teams
        local folder = World:FindFirstChild("Characters")
        if folder then
            local rigs=folder:GetChildren()
            local params
            if config.visibility or config.visibleOnly or config.lastSeenPolicy == "Line of sight loss" then
                params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
                local exclusions={camera}
                for _,other in ipairs(rigs) do
                    local otherRoot=other:FindFirstChild("HumanoidRootPart")
                    local otherPos=otherRoot and otherRoot.Position
                    if validPosition(otherPos) and (otherPos-camera.Position).Magnitude<3.2 then exclusions[#exclusions+1]=other end
                end
                params.FilterDescendantsInstances=exclusions
            end
            for _, rig in ipairs(rigs) do
                local head, root = rig:FindFirstChild("Head"), rig:FindFirstChild("HumanoidRootPart")
                local rp, hp = root and root.Position, head and head.Position
                if validPosition(rp) and validPosition(hp) then
                    local tag = rig:FindFirstChild("NameTag")
                    local canvas = tag and tag:FindFirstChild("CanvasGroup")
                    local label = canvas and canvas:FindFirstChild("PlayerName")
                    local name = label and label.Text
                    local distance = (rp - camera.Position).Magnitude
                    -- Kontra's NameTag.Create explicitly tags same-team entities.
                    -- The first-person local rig is untagged, so suppress it by camera proximity.
                    local isSelf = name == me.Name or distance < 3.2
                    local isAlly = tag ~= nil or (name and teams[name] == team)
                    local key = rig.Name .. ":" .. tostring(root.Address)
                    seen[key] = state.seen[key] or now
                    if isSelf then
                        stats.self = stats.self + 1
                        friends[#friends+1] = rp
                        state.contacts[key] = nil
                    elseif isAlly then
                        stats.allies = stats.allies + 1
                        friends[#friends+1] = rp
                        state.contacts[key] = nil
                    elseif now < state.settleUntil then
                        stats.pending = stats.pending + 1
                    elseif distance <= config.range then
                        local clear = false
                        if params then
                            local hit = World:Raycast(camera.Position, hp - camera.Position,params)
                            clear = not hit or (hit.Instance and hit.Instance:IsDescendantOf(rig)) or false
                        end
                        local canRemember = config.lastSeenPolicy == "Replication loss" or clear
                        if canRemember then
                            for previousKey, contact in pairs(state.contacts) do
                                if contact.slot==rig.Name and previousKey~=key then state.contacts[previousKey]=nil end
                            end
                            state.contacts[key] = {key=key,slot=rig.Name,root=rp,head=hp,at=now}
                        end
                        local showLive = (not config.visibleOnly or clear) and (config.lastSeenPolicy~="Line of sight loss" or clear)
                        if showLive then
                            live[key]=true
                            local cached=state.rigCache[key]
                            if not cached then
                                cached={bones={},nextBonesAt=0,label="ENEMY  /  "..rig.Name}
                                state.rigCache[key]=cached
                            end
                            local quiet=sampleQuiet(cached,rp,now,distance)
                            if config.skeleton and now>=cached.nextBonesAt then
                                local bones={}
                                for j, pair in ipairs(skeletonPairs) do
                                    bones[j] = {rig:FindFirstChild(pair[1]), rig:FindFirstChild(pair[2])}
                                end
                                cached.bones=bones;cached.nextBonesAt=now+0.5
                            end
                            result[#result + 1] = {
                                head = head, root = root, bones = cached.bones, clear = clear, key=key,
                                label = cached.label, distance = math.floor(distance) .. " studs",
                                quiet=quiet,speed=cached.speed or 0,motion=cached,
                            }
                            stats.enemies = stats.enemies + 1
                            if quiet then stats.quiet=stats.quiet+1 end
                            nearest = math.min(nearest, distance)
                        end
                    end
                end
            end
        end
    end
    local ghosts={}
    for key,contact in pairs(state.contacts) do
        local age=now-contact.at
        if age>math.max(config.lastSeenSeconds,5) then
            state.contacts[key]=nil
        elseif config.lastSeen and not live[key] and age<=config.lastSeenSeconds and camera
                and (contact.root-camera.Position).Magnitude<=config.range then
            ghosts[#ghosts+1]=contact
        end
    end
    state.seen, state.targets, state.stats = seen, result, stats
    for key in pairs(state.rigCache) do if not seen[key] then state.rigCache[key]=nil end end
    state.friendPositions, state.ghosts = friends, ghosts
    local teamLabel = (team == "CT" or team == "T") and team or "Spectating - overlay paused"
    state.hudText = "NEXUS   |   " .. teamLabel .. "   |   " .. stats.enemies .. " enemies"
    if now>=state.nextUiAt then
        if teamStatus then teamStatus:SetValue(teamLabel, "accent") end
        if targetStatus then targetStatus:SetValue(stats.enemies .. " enemies / " .. stats.allies .. " allies hidden", "success") end
        if nearestStatus then nearestStatus:SetValue(nearest < math.huge and math.floor(nearest) .. " studs" or "No replicated enemy nearby") end
        if quietStatus then quietStatus:SetValue(stats.quiet.." quiet-movement estimates / received enemies only","accent") end
        if refreshStatus then refreshStatus:SetValue(math.floor(config.refreshInterval*1000).."ms discovery / every-frame drawing", "success") end
        if declutterStatus then
            local s=state.labelStats
            declutterStatus:SetValue(config.declutter and (s.shown.." labels / "..s.hidden.." suppressed / "..s.moved.." repositioned") or "Decluttering off","accent")
        end
        state.nextUiAt=now+0.25
    end
    state.collectMs=(tick()-now)*1000
    state.maxCollectMs=math.max(state.maxCollectMs,state.collectMs)
    state.lastCollectAt=tick()
    updateMetrics(state.lastCollectAt)
end

-- A new Weapons.<name>.Fire sound part carries the actual audible source position.
-- Its position is not a bullet-impact point and is not an inferred aim direction.
local function ingestShot(position, weapon, now)
    if not state.camera or not validPosition(position) then state.shotRejects.invalid=state.shotRejects.invalid+1 return false end
    local distance=(position-state.camera.Position).Magnitude
    state.farthestSound=math.max(state.farthestSound,distance)
    local function reject(reason)
        state.shotRejects[reason]=state.shotRejects[reason]+1
        state.ignoredShotEvents=state.ignoredShotEvents+1
        return false
    end
    if distance<6 then return reject("self") end
    if distance>config.shotRange then return reject("range") end
    local nearestEnemy, nearestFriend=math.huge,math.huge
    for _,contact in pairs(state.contacts) do
        if now-contact.at<=5 then nearestEnemy=math.min(nearestEnemy,(position-contact.head).Magnitude) end
    end
    for _,pos in ipairs(state.friendPositions) do nearestFriend=math.min(nearestFriend,(position-pos).Magnitude) end
    if nearestFriend<9 and nearestFriend<=nearestEnemy+1 then return reject("ally") end
    if config.shotsEnemyOnly and nearestEnemy>10 then return reject("unlinked") end
    state.farthestShot=math.max(state.farthestShot,distance)
    -- An unlinked source is gunfire, not a confirmed enemy identity.
    local linked=nearestEnemy<=10
    for _,shot in ipairs(state.shots) do
        if now-shot.at<0.3 and (shot.position-position).Magnitude<3 then
            shot.position=position;shot.at=now;shot.weapon=weapon;shot.linked=linked
            state.shotEvents=state.shotEvents+1
            return true
        end
    end
    state.shotSequence=state.shotSequence+1
    state.shots[#state.shots+1]={position=position,weapon=weapon,at=now,linked=linked,id=state.shotSequence}
    if #state.shots>24 then table.remove(state.shots,1) end
    state.shotEvents=state.shotEvents+1
    return true
end
state.ingestShot=ingestShot
local function footSourceKind(name)
    local surface=string.match(name,"^Footsteps%.([%w_]+)$")
    if not surface then return nil end
    if string.sub(surface,1,4)=="Land" then return "LAND",surface end
    if surface=="Ladder" then return "LADDER",surface end
    return "STEP",surface
end
state.footSourceKind=footSourceKind
local function ingestFootstep(position,kind,surface,now)
    local function reject(reason)
        state.footRejects[reason]=state.footRejects[reason]+1
        return false
    end
    if not state.camera or not validPosition(position) then return reject("invalid") end
    local distance=(position-state.camera.Position).Magnitude
    state.farthestFootSound=math.max(state.farthestFootSound,distance)
    if distance<6 then return reject("self") end
    if distance>config.footRange then return reject("range") end
    local enemy,friend=math.huge,math.huge
    for _,contact in pairs(state.contacts) do
        if now-contact.at<=1.5 then enemy=math.min(enemy,(position-contact.root).Magnitude) end
    end
    if config.footHideAllies then
        for _,pos in ipairs(state.friendPositions) do friend=math.min(friend,(position-pos).Magnitude) end
        if friend<6 and friend<=enemy+1 then return reject("ally") end
    end
    if config.footEnemyOnly and enemy>10 then return reject("unlinked") end
    state.farthestFoot=math.max(state.farthestFoot,distance)
    -- Merge nearby recent steps; each update is an actual sound position,
    -- not a predicted player location. Expired markers never follow a rig.
    for _,step in ipairs(state.footsteps) do
        if now-step.at>=0 and now-step.at<0.65 and (step.position-position).Magnitude<6 then
            step.position=position;step.at=now;step.kind=kind;step.surface=surface;step.linked=enemy<=10
            state.footEvents=state.footEvents+1;return true
        end
    end
    state.footSequence=state.footSequence+1
    state.footsteps[#state.footsteps+1]={position=position,at=now,kind=kind,surface=surface,
        linked=enemy<=10,id=state.footSequence}
    if #state.footsteps>#state.footPool then table.remove(state.footsteps,1) end
    state.footEvents=state.footEvents+1
    return true
end
state.ingestFootstep=ingestFootstep
local function collectShots()
    state.shotPasses=state.shotPasses+1
    state.shotStage="find sounds"
    local now=tick()
    local debris=World:FindFirstChild("Debris")
    local sounds=debris and debris:FindFirstChild("Sounds")
    local seen={}
    local parts,candidates,footCandidates=0,0,0
    if sounds then
        state.shotStage="scan sources"
        for _,emitter in ipairs(sounds:GetChildren()) do
            parts=parts+1
            local name=emitter.Name
            local weapon=string.match(name,"^Weapons%.(.+)%.Fire")
            local footKind,surface=footSourceKind(name)
            local bombCue=name=="Bomb.c4_beep" or name=="Bomb.c4-plant-quiet"
            if (weapon or footKind or bombCue) and emitter.ClassName=="Part" then
                if weapon then candidates=candidates+1 elseif footKind then footCandidates=footCandidates+1 end
                local key=tostring(emitter.Address)..":"..name
                seen[key]=true
                if state.soundWarm and not state.soundSeen[key] then
                    if bombCue then
                        recordBombCue(name,emitter.Position,now)
                    elseif weapon and config.enabled and config.gunshots then
                        state.soundEvents=state.soundEvents+1
                        ingestShot(emitter.Position,weapon,now)
                    elseif footKind then
                        state.footSoundEvents=state.footSoundEvents+1
                        noteFootSound(emitter.Position,now)
                        if config.enabled and config.footsteps and (config.footLandings or footKind=="STEP") then
                            ingestFootstep(emitter.Position,footKind,surface,now)
                        end
                    end
                end
            end
        end
    end
    state.soundSeen=seen;state.soundWarm=true
    state.soundParts=parts;state.soundCandidates=candidates
    state.footCandidates=footCandidates
    state.shotStage="expire pins"
    local remaining={}
    for _,shot in ipairs(state.shots) do if now-shot.at<=config.shotSeconds then remaining[#remaining+1]=shot end end
    state.shots=remaining
    local recentSteps={}
    for _,step in ipairs(state.footsteps) do if now-step.at<=config.footSeconds then recentSteps[#recentSteps+1]=step end end
    state.footsteps=recentSteps
    state.lastShotCollectAt=tick()
    state.shotStage="status"
    if now>=(state.nextShotUiAt or 0) then
        if shotStatus then shotStatus:SetValue(#remaining.." active / "..state.shotEvents.." accepted", "accent") end
        if shotRangeStatus then
            shotRangeStatus:SetValue(string.format("Farthest source %.0f / pin %.0f studs",state.farthestSound,state.farthestShot),"accent")
        end
        if shotScanStatus then
            shotScanStatus:SetValue(string.format("Live / %.0fHz / %d fire emitters / %d errors",
                state.performance.sounds,candidates,state.shotScanErrors),state.shotScanErrors==0 and "success" or "danger")
        end
        if footStatus then footStatus:SetValue(#recentSteps.." active / "..state.footEvents.." accepted / "..state.footSoundEvents.." received","accent") end
        if footScanStatus then
            footScanStatus:SetValue(string.format("Live / %.0fHz / %d movement emitters",state.performance.sounds,footCandidates),"success")
        end
        if footRangeStatus then footRangeStatus:SetValue(string.format("Received %.0f / shown %.0f studs",state.farthestFootSound,state.farthestFoot),"accent") end
        state.nextShotUiAt=now+0.25
    end
    state.shotStage="idle"
end

-- Placement is resolved during this same render frame: no debounce or smoothing.
-- Only text is suppressed; boxes, skeletons and source pins remain visible.
local labelCache, labelOrder, labelCount = {}, {}, 0
local labelOffsets={0,-1,1,-2,2}
local function overlaps(x,y,w,h,other,gap)
    return x<other.px+other.w+gap and x+w+gap>other.px
        and y<other.py+other.h+gap and y+h+gap>other.py
end
local function layoutLabels(items,view,reserved,limit,gap)
    table.sort(items,function(a,b)
        if a.priority==b.priority then return a.key<b.key end
        return a.priority<b.priority
    end)
    local placed,shown,moved={},0,0
    for _,r in ipairs(items) do
        r.placed=false
        if shown<limit then
            local x=math.max(6,math.min(view.X-r.w-6,r.x-r.w*0.5))
            for _,offset in ipairs(labelOffsets) do
                local y=math.max(6,math.min(view.Y-r.h-6,r.y+offset*(r.h+gap)))
                local blocked=false
                for _,o in ipairs(reserved) do if overlaps(x,y,r.w,r.h,o,gap) then blocked=true break end end
                if not blocked then
                    for _,o in ipairs(placed) do if overlaps(x,y,r.w,r.h,o,gap) then blocked=true break end end
                end
                if not blocked then
                    r.px,r.py,r.placed=x,y,true
                    placed[#placed+1]=r;shown=shown+1
                    if math.abs(x+r.w*0.5-r.x)>1 or math.abs(y-r.y)>1 then moved=moved+1 end
                    break
                end
            end
        end
        -- Critical objective text must survive HUD reservations and the cap.
        if not r.placed and r.priority<=0 then
            r.px=math.max(6,math.min(view.X-r.w-6,r.x-r.w*0.5))
            r.py=math.max(6,math.min(view.Y-r.h-6,r.y))
            r.placed=true;placed[#placed+1]=r;shown=shown+1
        end
    end
    return shown,moved
end
state.layoutLabels=layoutLabels
local function queueLabel(d,value,x,y,size,color,opacity,priority,key)
    d.Text=value;d.Size=size;d.Color=color;d.Transparency=opacity
    if not config.declutter then d.Position=Vector2.new(x,y);d.Visible=true return end
    d.Visible=false
    labelCount=labelCount+1
    local r=labelCache[labelCount]
    if not r then r={};labelCache[labelCount]=r end
    r.d,r.x,r.y,r.priority,r.key=d,x,y,priority,tostring(key)
    -- Conservative bounds leave room for font bearings and fractional sizing.
    r.w=math.max(size, #value*size*0.65+6);r.h=size+4
    labelOrder[labelCount]=r
end
local reservedHud={{},{},{}}
local function flushLabels(view)
    for i=#labelOrder,labelCount+1,-1 do labelOrder[i]=nil end
    if not config.declutter then
        state.labelStats={requested=0,shown=0,hidden=0,moved=0};return
    end
    local reserved={}
    if config.status then
        local r=reservedHud[1];r.px,r.py,r.w,r.h=12,12,380,28;reserved[#reserved+1]=r
    end
    if config.performanceHud then
        local r=reservedHud[2];r.px,r.py,r.w,r.h=math.max(15,view.X-287),14,271,52;reserved[#reserved+1]=r
    end
    if bombHud.Visible or defuseHud.Visible then
        local r=reservedHud[3];r.px,r.py,r.w,r.h=view.X*0.5-170,65,340,68;reserved[#reserved+1]=r
    end
    local shown,moved=layoutLabels(labelOrder,view,reserved,config.labelBudget,config.labelSpacing)
    for _,r in ipairs(labelOrder) do
        if r.placed then r.d.Position=Vector2.new(r.px+r.w*0.5,r.py);r.d.Visible=true end
    end
    state.labelStats.requested=labelCount;state.labelStats.shown=shown
    state.labelStats.hidden=labelCount-shown;state.labelStats.moved=moved
end

local function segment(d, x1, y1, x2, y2, color, width)
    d.From = Vector2.new(x1, y1); d.To = Vector2.new(x2, y2)
    d.Color = color; d.Thickness = width or config.width
    d.Transparency = config.opacity; d.Visible = true
end
local function edgeMarker(e, position, color, camera, label, opacity, priority, key, labelSize)
    local view=camera.ViewportSize
    local localPos=camera.CFrame:PointToObjectSpace(position)
    local dx,dy=localPos.X,-localPos.Y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<0.001 then dx,dy,length=0,1,1 end
    dx,dy=dx/length,dy/length
    local radius=math.min(view.X,view.Y)*0.39
    local tx,ty=view.X*0.5+dx*radius,view.Y*0.5+dy*radius
    e.arrow.PointA=Vector2.new(tx,ty)
    e.arrow.PointB=Vector2.new(tx-dx*15-dy*7,ty-dy*15+dx*7)
    e.arrow.PointC=Vector2.new(tx-dx*15+dy*7,ty-dy*15-dx*7)
    e.arrow.Color=color;e.arrow.Transparency=opacity;e.arrow.Visible=true
    queueLabel(e.label,label,tx-dx*25,ty-dy*25+14,labelSize,color,opacity,priority,key)
end
local function pin(e, position, label, color, radius, opacity, arrows, camera, priority, key, minimumSize)
    hide(e)
    local scale=distanceScale((position-camera.Position).Magnitude)
    radius=math.max(minimumSize or 7,radius*scale)
    local labelSize=math.max(minimumSize and 11 or 9,11*scale)
    local screen,visible=WorldToScreen(position)
    if visible then
        e.ring.Position=screen;e.ring.Radius=radius;e.ring.Color=color
        e.ring.Transparency=opacity;e.ring.Visible=true
        queueLabel(e.label,label,screen.X,screen.Y-radius-19,labelSize,color,opacity,priority,key)
        segment(e.crossA,screen.X-4,screen.Y,screen.X+4,screen.Y,color,1)
        segment(e.crossB,screen.X,screen.Y-4,screen.X,screen.Y+4,color,1)
        e.crossA.Transparency=opacity;e.crossB.Transparency=opacity
    elseif arrows then
        edgeMarker(e,position,color,camera,label,opacity,priority,key,labelSize)
    end
end
local function renderExtras(camera, now)
    local n=0
    if config.lastSeen then
        for _,contact in ipairs(state.ghosts) do
            if n>=#state.ghostPool then break end
            local age=now-contact.at
            if age>=0 and age<config.lastSeenSeconds then
                n=n+1
                local e=state.ghostPool[n];hide(e)
                local top,a=WorldToScreen(contact.head+Vector3.new(0,0.7,0))
                local bottom,b=WorldToScreen(contact.root-Vector3.new(0,2.85,0))
                if a and b then
                    local h=bottom.Y-top.Y
                    if h>8 and h<camera.ViewportSize.Y*2 then
                        local w=h*0.48
                        local x,y=top.X-w*0.5,top.Y
                        local alpha=config.opacity*(1-age/config.lastSeenSeconds)*0.75
                        local cw,ch=w*0.15,h*0.1
                        segment(e.dash[1],x,y,x+cw,y,config.lastSeenColor,1)
                        segment(e.dash[2],x,y,x,y+ch,config.lastSeenColor,1)
                        segment(e.dash[3],x+w,y,x+w-cw,y,config.lastSeenColor,1)
                        segment(e.dash[4],x+w,y,x+w,y+ch,config.lastSeenColor,1)
                        segment(e.dash[5],x,y+h,x+cw,y+h,config.lastSeenColor,1)
                        segment(e.dash[6],x,y+h,x,y+h-ch,config.lastSeenColor,1)
                        segment(e.dash[7],x+w,y+h,x+w-cw,y+h,config.lastSeenColor,1)
                        segment(e.dash[8],x+w,y+h,x+w,y+h-ch,config.lastSeenColor,1)
                        for _,d in ipairs(e.dash) do d.Transparency=alpha end
                        local distance=(contact.root-camera.Position).Magnitude
                        queueLabel(e.label,string.format("LAST SEEN / %.1fs",age),top.X,top.Y-17,
                            math.max(9,11*distanceScale(distance)),config.lastSeenColor,alpha,40+age,contact.key)
                        state.ghostFrames=state.ghostFrames+1
                    end
                end
            end
        end
    end
    for i=n+1,#state.ghostPool do hide(state.ghostPool[i]) end
    n=0
    if config.gunshots then
        for _,shot in ipairs(state.shots) do
            if n>=#state.shotPool then break end
            local age=now-shot.at
            if age>=0 and age<config.shotSeconds then
                n=n+1
                -- Stay legible until the final quarter, then fade away.
                local opacity=config.opacity*math.min(1,(1-age/config.shotSeconds)*4)
                local distance=(shot.position-camera.Position).Magnitude
                local label=string.format("SHOT / %s / %.0f studs / %.1fs",shot.weapon,distance,age)..heightTag(shot.position,camera.Position)
                pin(state.shotPool[n],shot.position,label,config.shotColor,config.shotPinSize+math.min(age,0.6)*14,
                    opacity,config.shotArrows,camera,10+age,"shot:"..tostring(shot.id),config.shotPinSize)
                state.shotFrames=state.shotFrames+1
            end
        end
    end
    for i=n+1,#state.shotPool do hide(state.shotPool[i]) end
    n=0
    if config.footsteps then
        for _,step in ipairs(state.footsteps) do
            if n>=#state.footPool then break end
            local age=now-step.at
            if age>=0 and age<config.footSeconds then
                n=n+1
                local fraction=age/config.footSeconds
                local alpha=config.opacity*math.min(1,(1-fraction)*2)
                local distance=(step.position-camera.Position).Magnitude
                local label=string.format("%s / %.0f studs / %.1fs",step.kind,distance,age)..heightTag(step.position,camera.Position)
                local e=state.footPool[n]
                pin(e,step.position,label,config.footColor,config.footPinSize+fraction*13,
                    alpha,config.footArrows,camera,18+fraction,"step:"..tostring(step.id),config.footPinSize)
                -- Footsteps use a clean pulse ring; gunshots keep their crosshair.
                e.crossA.Visible=false;e.crossB.Visible=false
                state.footFrames=state.footFrames+1
            end
        end
    end
    for i=n+1,#state.footPool do hide(state.footPool[i]) end
    hide(bombMarker);bombHud.Visible=false;bombBar.Visible=false;bombBarBack.Visible=false
    defuseHud.Visible=false;defuseBar.Visible=false;defuseBarBack.Visible=false
    local bomb=state.bombData
    state.bombPinPosition=nil
    if config.bomb and bomb then
        local remaining=bomb.time and math.max(0,bomb.time-(now-bomb.anchor))
        local color=remaining and remaining<=10 and config.enemyColor or config.bombColor
        local label=bomb.kind
        if remaining and config.bombTimer then label=label..string.format(" / %.1fs",remaining) end
        -- Read the current validated physical part every render. A removed
        -- model or stale folder identity must never leave an old location pin.
        local position=getBombPosition(bomb,now)
        if validPosition(position) then
            state.bombPinPosition=position
            label=label.." / "..math.floor((position-camera.Position).Magnitude).." studs"..heightTag(position,camera.Position)
            pin(bombMarker,position,label,color,config.bombPinSize+math.sin(now*4)*2,config.opacity,
                config.bombArrows,camera,0,"bomb",config.bombPinSize)
        end
        if config.bombTimer and bomb.planted then
            local v=camera.ViewportSize
            bombHud.Text=remaining and string.format("BOMB / %.1fs",remaining) or "BOMB / timer unavailable"
            if not position then bombHud.Text=bombHud.Text.." / LOCATION UNAVAILABLE" end
            bombHud.Position=Vector2.new(v.X*0.5,70);bombHud.Color=color
            bombHud.Transparency=config.opacity;bombHud.Visible=true
            if remaining and (state.bombObservedMaximum or 0)>0 then
                segment(bombBarBack,v.X*0.5-90,94,v.X*0.5+90,94,INK,4)
                segment(bombBar,v.X*0.5-90,94,v.X*0.5-90+180*math.min(1,remaining/state.bombObservedMaximum),94,color,3)
            end
        end
        local digits=bomb.defuseDigits
        if config.defuseProgress and digits and digits>0 and bomb.planted then
            local v=camera.ViewportSize
            defuseHud.Text="DEFUSE / "..digits.." of 8 code steps"
            if digits==8 then defuseHud.Text="DEFUSE / final code step" end
            defuseHud.Position=Vector2.new(v.X*0.5,104)
            defuseHud.Color=config.defuseColor;defuseHud.Transparency=config.opacity;defuseHud.Visible=true
            segment(defuseBarBack,v.X*0.5-90,124,v.X*0.5+90,124,INK,4)
            segment(defuseBar,v.X*0.5-90,124,v.X*0.5-90+180*(digits/8),124,config.defuseColor,3)
            state.defuseFrames=state.defuseFrames+1
        end
        state.bombFrames=state.bombFrames+1
    end
end
local function render()
    state.frames = state.frames + 1
    labelCount=0
    local camera = state.camera
    if not config.enabled or not camera then hideAll() return end
    local camPos, view = camera.Position, camera.ViewportSize
    local used = 0
    for _, target in ipairs(state.targets) do
        if used >= #state.pool then break end
        local rp, hp = target.root.Parent and target.root.Position, target.head.Parent and target.head.Position
        if validPosition(rp) and validPosition(hp) and (rp - camPos).Magnitude >= 3.2 then
            used = used + 1
            local e = state.pool[used]
            -- Clear every element before reuse; arrows cannot leave stale on-screen boxes.
            hide(e)
            local color = config.visibility and target.clear and config.visibleColor or config.enemyColor
            local distance=(rp-camPos).Magnitude
            local scale=distanceScale(distance)
            local lineWidth=math.max(1,config.width*scale)
            local top, a = WorldToScreen(hp + Vector3.new(0, 0.7, 0))
            local bottom, b = WorldToScreen(rp - Vector3.new(0, 2.85, 0))
            local height = bottom.Y - top.Y
            if a and b and height > 8 and height < view.Y * 2 then
                local width = height * 0.48
                local x, y = top.X - width * 0.5, top.Y
                if config.box == "Corners" then
                    local cw, ch = width * 0.28, height * 0.18
                    segment(e.corners[1], x, y, x+cw, y, color,lineWidth)
                    segment(e.corners[2], x, y, x, y+ch, color,lineWidth)
                    segment(e.corners[3], x+width, y, x+width-cw, y, color,lineWidth)
                    segment(e.corners[4], x+width, y, x+width, y+ch, color,lineWidth)
                    segment(e.corners[5], x, y+height, x+cw, y+height, color,lineWidth)
                    segment(e.corners[6], x, y+height, x, y+height-ch, color,lineWidth)
                    segment(e.corners[7], x+width, y+height, x+width-cw, y+height, color,lineWidth)
                    segment(e.corners[8], x+width, y+height, x+width, y+height-ch, color,lineWidth)
                elseif config.box == "Full" then
                    e.box.Position = Vector2.new(x,y); e.box.Size = Vector2.new(width,height)
                    e.box.Color = color; e.box.Thickness = lineWidth
                    e.box.Transparency = config.opacity; e.box.Visible = true
                end
                local quiet=config.quietMovement and target.motion and target.motion.quiet or false
                if config.labels or quiet then
                    local label=config.labels and target.label or ""
                    if quiet then label=label..(label~="" and " / " or "").."QUIET MOVE?" end
                    if config.declutter and config.mergeLabels and config.distance then label=label.." / "..math.floor(distance).." studs" end
                    queueLabel(e.label,label,top.X,y-17,math.max(quiet and 11 or 9,config.fontSize*scale),quiet and config.quietColor or color,
                        config.opacity,(quiet and 17 or 20)+math.min(distance,2500)*0.003,target.key..":label")
                    if quiet then state.quietFrames=state.quietFrames+1 end
                end
                if config.distance and not (config.labels and config.declutter and config.mergeLabels) then
                    queueLabel(e.distance,math.floor(distance).." studs",top.X,bottom.Y+4,math.max(9,10*scale),WHITE,
                        config.opacity,28+math.min(distance,2500)*0.003,target.key..":distance")
                end
                if config.tracers then segment(e.tracer,view.X*0.5,view.Y-6,bottom.X,bottom.Y,color,1) end
                if config.skeleton then
                    for j, pair in ipairs(target.bones) do
                        local p1, p2 = pair[1] and pair[1].Position, pair[2] and pair[2].Position
                        if validPosition(p1) and validPosition(p2) then
                            local s1,v1 = WorldToScreen(p1); local s2,v2 = WorldToScreen(p2)
                            if v1 and v2 then segment(e.bones[j],s1.X,s1.Y,s2.X,s2.Y,color,math.max(1,config.skeletonWidth*scale)) end
                        end
                    end
                end
            elseif config.arrows then
                local localPos = camera.CFrame:PointToObjectSpace(rp)
                local dx,dy = localPos.X,-localPos.Y
                local length = math.sqrt(dx*dx+dy*dy)
                if length < 0.001 then dx,dy,length = 0,1,1 end
                dx,dy = dx/length,dy/length
                local radius = math.min(view.X,view.Y)*0.39
                local tx,ty = view.X*0.5+dx*radius,view.Y*0.5+dy*radius
                e.arrow.PointA = Vector2.new(tx,ty)
                e.arrow.PointB = Vector2.new(tx-dx*15-dy*7,ty-dy*15+dx*7)
                e.arrow.PointC = Vector2.new(tx-dx*15+dy*7,ty-dy*15-dx*7)
                e.arrow.Color = color; e.arrow.Transparency = config.opacity; e.arrow.Visible = true
            end
        end
    end
    for i = used + 1, #state.pool do hide(state.pool[i]) end
    hud.Visible = config.status; hudRule.Visible = config.status
    if config.status then
        hud.Text = state.hudText or "NEXUS / Collecting..."
        hud.Position = Vector2.new(26,19); hud.Color = WHITE; hud.Transparency = 1
        segment(hudRule,17,19,17,33,config.enemyColor,3)
    end
    renderExtras(camera,tick())
    perfBack.Visible=config.performanceHud;perfLineA.Visible=config.performanceHud
    perfLineB.Visible=config.performanceHud;perfAccent.Visible=config.performanceHud
    if config.performanceHud then
        local x=math.max(15,view.X-287)
        perfBack.Position=Vector2.new(x,14);perfBack.Size=Vector2.new(271,52);perfBack.Transparency=0.85
        perfLineA.Text=state.perfTextA or "NEXUS / Measuring...";perfLineA.Color=WHITE
        perfLineA.Position=Vector2.new(x+13,23);perfLineA.Transparency=1
        perfLineB.Text=state.perfTextB or "Collecting refresh statistics";perfLineB.Color=config.visibleColor
        perfLineB.Position=Vector2.new(x+13,43);perfLineB.Transparency=1
        segment(perfAccent,x+5,23,x+5,55,config.enemyColor,2)
    end
    flushLabels(view)
end
-- Callable only from a render callback for bounded renderer regression checks.
state.renderOnce=render

local selectedProfile="Kontra_Main"
local selectedProfileControl,profileStateControl,startupStateControl
local STARTUP_FILE="KontraNexus_startup.txt"
local function profileName(value)
    local name=string.gsub(tostring(value or "Kontra_Main"),"[^%w_%-]","_")
    if string.sub(name,1,7)~="Kontra_" then name="Kontra_"..name end
    return string.sub(name,1,64)
end
local function profileNames()
    local result={"Kontra_Main","Kontra_Minimal","Kontra_Detailed"}
    local seen={Kontra_Main=true,Kontra_Minimal=true,Kontra_Detailed=true}
    local ok,files=pcall(listfiles,".")
    if ok and type(files)=="table" then
        for _,file in ipairs(files) do
            local base=string.gsub(tostring(file),"\\","/"):match("([^/]+)$")
            local name=base and string.match(base,"^Nexa_(Kontra_[%w_%-]+)%.json$")
            if name and not seen[name] then seen[name]=true;result[#result+1]=name end
        end
    end
    return result
end
local function profileFeedback(message,ok,quiet)
    if profileStateControl then profileStateControl:SetValue(message,ok and "success" or "danger") end
    if not quiet then ui:Notify({Title=ok and "Profile ready" or "Profile error",Content=message,Type=ok and "success" or "error",Duration=4}) end
end
local function saveProfile(name,quiet)
    name=profileName(name)
    local called,ok,info=pcall(ui.SaveConfig,ui,name)
    local success=called and ok==true
    if success and selectedProfileControl then selectedProfileControl.Options=profileNames() end
    profileFeedback(success and ("Saved "..name) or tostring(called and info or ok),success,quiet)
    return success,success and info or tostring(called and info or ok)
end
local function loadProfile(name,quiet)
    name=profileName(name)
    local called,ok,info=pcall(ui.LoadConfig,ui,name)
    local success=called and ok==true
    if success then
        selectedProfile=name
        state.loadedProfile=name
        if selectedProfileControl then selectedProfileControl:SetValue(name,true) end
        local readOk,raw=pcall(readfile,"Nexa_"..name..".json")
        if readOk and not string.find(raw,"Minimum shot pin size",1,true) then
            -- Old profiles inherited a strict default that dropped distant unlinked shots.
            -- Migrate in memory; never silently overwrite the saved profile.
            config.shotsEnemyOnly=false;config.shotRange=math.max(2500,config.shotRange)
            if shotStrictControl then shotStrictControl:SetValue(false,true) end
            if shotRangeControl then shotRangeControl:SetValue(config.shotRange,true) end
            state.migratedProfile=name
        end
    end
    profileFeedback(success and ("Loaded "..name) or tostring(called and info or ok),success,quiet)
    return success,success and info or tostring(called and info or ok)
end
local function setStartup(name,quiet)
    name=profileName(name)
    if not isfile("Nexa_"..name..".json") then
        profileFeedback("Save this profile before setting startup.",false,quiet)
        return false
    end
    local ok,err=pcall(writefile,STARTUP_FILE,name)
    if startupStateControl then startupStateControl:SetValue(ok and name or tostring(err),ok and "success" or "danger") end
    if not quiet then profileFeedback(ok and ("Startup: "..name) or tostring(err),ok,false) end
    return ok
end
state.saveProfile=saveProfile;state.loadProfile=loadProfile
state.profileNames=profileNames;state.setStartupProfile=setStartup

ui:CreateWindow({Title="Kontra Nexus 4.6",Subtitle="Independent objective scanner",GameName="Kontra",Width=780,Height=540,
    Theme="Crimson",Background="none",Opacity=100,MenuKey="F8",ShowGameName=true})
local visual = ui:AddTab({Title="ESP",Icon="eye",Select=true})
local main = visual:AddSection("Enemy visuals","Your team and local rig are excluded.",{Column="left"})
main:AddToggle({Title="Enable ESP",Default=config.enabled,Callback=function(v) config.enabled=v end})
main:AddDropdown({Title="Box style",Options={"Corners","Full","None"},Default=config.box,Callback=function(v) config.box=v end})
main:AddToggle({Title="Enemy labels",Default=config.labels,Callback=function(v) config.labels=v end})
main:AddToggle({Title="Distance",Default=config.distance,Callback=function(v) config.distance=v end})
main:AddToggle({Title="Skeleton",Default=config.skeleton,Callback=function(v) config.skeleton=v end})
main:AddSlider({Title="Skeleton thickness",Min=1,Max=3,Step=0.5,Default=config.skeletonWidth,Callback=function(v) config.skeletonWidth=v end})
main:AddToggle({Title="Tracers",Default=config.tracers,Callback=function(v) config.tracers=v end})
main:AddToggle({Title="Off-screen arrows",Default=config.arrows,Callback=function(v) config.arrows=v end})
local details = visual:AddSection("Visibility and range","Only currently replicated positions are displayed.",{Column="right"})
details:AddToggle({Title="Color by line of sight",Default=config.visibility,Callback=function(v) config.visibility=v end})
details:AddToggle({Title="Visible targets only",Default=config.visibleOnly,Callback=function(v) config.visibleOnly=v end})
details:AddSlider({Title="Maximum range",Min=100,Max=2500,Step=50,Default=config.range,Suffix=" studs",Callback=function(v) config.range=v end})
details:AddToggle({Title="Compact status",Default=config.status,Callback=function(v) config.status=v end})
teamStatus=details:AddStatus({Title="Your team",Default="Reading..."})
targetStatus=details:AddStatus({Title="Targets",Default="Collecting..."})
nearestStatus=details:AddStatus({Title="Nearest enemy",Default="--"})
details:AddDropdown({Title="Refresh profile",Options={"Fastest","Fast","Balanced"},Default=config.refreshProfile,Callback=function(v)
    config.refreshProfile=v
    config.refreshInterval=v=="Fastest" and 0.025 or (v=="Fast" and 0.05 or 0.1)
end})
refreshStatus=details:AddStatus({Title="ESP refresh",Default="25ms discovery / every-frame drawing",Tone="success"})

local intel=ui:AddTab({Title="Memory & shots",Icon="target"})
local memory=intel:AddSection("Last seen","Fading snapshots at previously received positions.",{Column="left"})
memory:AddToggle({Title="Last-seen markers",Default=config.lastSeen,Callback=function(v) config.lastSeen=v end})
memory:AddDropdown({Title="When to freeze",Options={"Replication loss","Line of sight loss"},Default=config.lastSeenPolicy,Callback=function(v)
    config.lastSeenPolicy=v;state.contacts={};state.ghosts={}
end})
memory:AddSlider({Title="Snapshot lifetime",Min=1,Max=10,Step=0.5,Default=config.lastSeenSeconds,Suffix="s",Callback=function(v) config.lastSeenSeconds=v end})
memory:AddColorPicker({Title="Snapshot color",Default=config.lastSeenColor,Callback=function(v) config.lastSeenColor=v end})
memory:AddLabel({Title="Stale positions",Description="LAST SEEN labels show their age. Snapshots never follow a hidden player."})
memory:AddButton({Title="Clear recent markers",ButtonText="Clear",Callback=function() state.contacts={};state.ghosts={};state.shots={};state.footsteps={} end})
local signals=intel:AddSection("Gunshot sources","Pins on new, positioned weapon-fire sounds.",{Column="right"})
signals:AddToggle({Title="Shot-source ESP",Default=config.gunshots,Callback=function(v) config.gunshots=v;if not v then state.shots={} end end})
shotStrictControl=signals:AddToggle({Title="Tracked enemies only",Default=config.shotsEnemyOnly,Callback=function(v) config.shotsEnemyOnly=v end})
signals:AddToggle({Title="Shot edge arrows",Default=config.shotArrows,Callback=function(v) config.shotArrows=v end})
signals:AddSlider({Title="Shot-marker lifetime",Min=0.5,Max=6,Step=0.5,Default=config.shotSeconds,Suffix="s",Callback=function(v) config.shotSeconds=v end})
shotRangeControl=signals:AddSlider({Title="Sound-marker range",Min=100,Max=5000,Step=50,Default=config.shotRange,Suffix=" studs",Callback=function(v) config.shotRange=v end})
signals:AddColorPicker({Title="Gunshot color",Default=config.shotColor,Callback=function(v) config.shotColor=v end})
shotStatus=signals:AddStatus({Title="Detected shots",Default="Listening..."})
signals:AddLabel({Title="Source meaning",Description="Pins show the firing sound's original location. Only received sound emitters can be marked."})
signals:AddSlider({Title="Minimum shot pin size",Min=8,Max=24,Step=1,Default=config.shotPinSize,Suffix=" px",Callback=function(v) config.shotPinSize=v end})
shotRangeStatus=signals:AddStatus({Title="Received source range",Default="Listening..."})
signals:AddLabel({Title="Distant shots",Description="Leave Tracked enemies only OFF to mark sources without a visible enemy. Known nearby allies/self are excluded; unlinked shots are not confirmed enemies."})
shotScanStatus=signals:AddStatus({Title="Shot scanner",Default="Starting..."})

local movement=ui:AddTab({Title="Footsteps",Icon="target"})
local footControls=movement:AddSection("Footstep ESP","Cyan pulses at received movement-sound positions.",{Column="left"})
footControls:AddToggle({Title="Footstep ESP",Default=config.footsteps,Callback=function(v) config.footsteps=v;if not v then state.footsteps={} end end})
footControls:AddToggle({Title="Footstep edge arrows",Default=config.footArrows,Callback=function(v) config.footArrows=v end})
footControls:AddToggle({Title="Hide known teammates",Default=config.footHideAllies,Callback=function(v) config.footHideAllies=v end})
footControls:AddToggle({Title="Confirmed enemies only",Default=config.footEnemyOnly,Callback=function(v) config.footEnemyOnly=v end})
footControls:AddToggle({Title="Landing and ladder sounds",Default=config.footLandings,Callback=function(v) config.footLandings=v end})
footControls:AddSlider({Title="Footstep lifetime",Min=0.5,Max=3,Step=0.1,Default=config.footSeconds,Suffix="s",Callback=function(v) config.footSeconds=v end})
footControls:AddSlider({Title="Footstep range",Min=10,Max=90,Step=5,Default=config.footRange,Suffix=" studs",Callback=function(v) config.footRange=v end})
footControls:AddSlider({Title="Footstep pulse size",Min=8,Max=18,Step=1,Default=config.footPinSize,Suffix=" px",Callback=function(v) config.footPinSize=v end})
footControls:AddColorPicker({Title="Footstep color",Default=config.footColor,Callback=function(v) config.footColor=v end})
footControls:AddToggle({Title="Above / below indicators",Default=config.heightIndicators,Callback=function(v) config.heightIndicators=v end})
local footInfo=movement:AddSection("Received sounds","Shares the gunshot scanner; no second background loop.",{Column="right"})
footStatus=footInfo:AddStatus({Title="Footstep events",Default="Listening..."})
footScanStatus=footInfo:AddStatus({Title="Movement scanner",Default="Starting..."})
footRangeStatus=footInfo:AddStatus({Title="Movement source range",Default="Listening..."})
footInfo:AddLabel({Title="Fastest response",Description="Fastest scans positioned sounds on every Heartbeat. Markers draw on the next render; no smoothing or extra reveal timer."})
footInfo:AddLabel({Title="About 87 studs",Description="Kontra discards remote footsteps beyond 86.75 studs before making sounds. This ESP cannot show movement the client never receives."})
footInfo:AddLabel({Title="Not an enemy identity",Description="STEP, LAND and LADDER mark sound locations, not live tracking. Nearby known teammates/self are suppressed; unlinked movement may still be a teammate."})
footInfo:AddButton({Title="Clear footstep markers",ButtonText="Clear",Callback=function() state.footsteps={} end})
local quietControls=movement:AddSection("Quiet movement estimates","Uses received enemy motion, never silent hidden-player detection.",{Column="right"})
quietControls:AddToggle({Title="Quiet movement badges",Default=config.quietMovement,Callback=function(v) config.quietMovement=v end})
quietControls:AddSlider({Title="Slow-movement limit",Min=4,Max=16,Step=1,Default=config.quietSpeed,Suffix=" studs/s",Callback=function(v) config.quietSpeed=v end})
quietControls:AddSlider({Title="Quiet observation window",Min=0.3,Max=1.5,Step=0.1,Default=config.quietWindow,Suffix="s",Callback=function(v) config.quietWindow=v end})
quietControls:AddSlider({Title="Quiet estimate range",Min=20,Max=85,Step=5,Default=config.quietRange,Suffix=" studs",Callback=function(v) config.quietRange=v end})
quietControls:AddColorPicker({Title="Quiet badge color",Default=config.quietColor,Callback=function(v) config.quietColor=v end})
quietStatus=quietControls:AddStatus({Title="Quiet movement",Default="Waiting for received enemies..."})
quietControls:AddLabel({Title="QUIET MOVE?",Description="An estimate: a nearby received enemy is moving slowly without a recent matching step. It does not confirm crouching, a held walk key, or inaudibility."})
quietControls:AddLabel({Title="Replication boundary",Description="No badge for culled enemies, no invented sound pins. The short observation window applies only to this estimate; normal ESP remains live."})

local objectives=ui:AddTab({Title="Bomb",Icon="target"})
local bombControls=objectives:AddSection("Bomb objective","Gold markers for planted and dropped bombs.",{Column="left"})
bombControls:AddToggle({Title="Bomb ESP",Default=config.bomb,Callback=function(v) config.bomb=v end})
bombControls:AddToggle({Title="Bomb countdown",Default=config.bombTimer,Callback=function(v) config.bombTimer=v end})
bombControls:AddToggle({Title="Bomb edge arrow",Default=config.bombArrows,Callback=function(v) config.bombArrows=v end})
bombControls:AddToggle({Title="Defuse progress",Default=config.defuseProgress,Callback=function(v) config.defuseProgress=v end})
bombControls:AddColorPicker({Title="Bomb color",Default=config.bombColor,Callback=function(v) config.bombColor=v end})
bombControls:AddColorPicker({Title="Defuse color",Default=config.defuseColor,Callback=function(v) config.defuseColor=v end})
bombStatus=bombControls:AddStatus({Title="Objective",Default="Reading round state..."})
defuseStatus=bombControls:AddStatus({Title="Defuse progress",Default="Waiting for planted bomb..."})
bombControls:AddSlider({Title="Bomb pin size",Min=8,Max=24,Step=1,Default=config.bombPinSize,Suffix=" px",Callback=function(v) config.bombPinSize=v end})
bombAnchorStatus=bombControls:AddStatus({Title="Position anchor",Default="Waiting for a bomb model..."})
bombControls:AddToggle({Title="Recent bomb-beep fallback",Default=config.bombAudioFallback,Callback=function(v) config.bombAudioFallback=v end})
bombScanStatus=bombControls:AddStatus({Title="Bomb scanner",Default="Starting..."})
local bombHelp=objectives:AddSection("Timer and markers","",{Column="right"})
bombHelp:AddLabel({Title="Countdown",Description="Uses the server's planted-bomb time when available; no invented planting time."})
bombHelp:AddLabel({Title="Dropped / planted",Description="The planted folder is scanned independently of round labels and enemy ESP. Live model anchors take priority. Missing models never reuse an old round's point."})
bombHelp:AddLabel({Title="HEARD fallback",Description="If the round is planted but the model is unavailable, a received C4 beep can supply a clearly marked HEARD position for at most 1.75 seconds. No sound/model means LOCATION UNAVAILABLE."})
bombHelp:AddLabel({Title="Defuse steps",Description="The planted bomb reveals an eight-step defuse code. The bar follows those replicated steps; the final digit is not confirmation of completion."})

local style = ui:AddTab({Title="Colors",Icon="palette"})
local colors = style:AddSection("ESP colors","These controls change the player overlay.",{Column="left"})
colors:AddColorPicker({Title="Enemy color",Default=config.enemyColor,Callback=function(v) config.enemyColor=v end})
colors:AddColorPicker({Title="Visible color",Default=config.visibleColor,Callback=function(v) config.visibleColor=v end})
colors:AddSlider({Title="ESP opacity",Min=25,Max=100,Step=5,Default=config.opacity*100,Suffix="%",Callback=function(v) config.opacity=v/100 end})
colors:AddSlider({Title="Line thickness",Min=1,Max=4,Step=1,Default=config.width,Callback=function(v) config.width=v end})
colors:AddSlider({Title="Label size",Min=10,Max=17,Step=1,Default=config.fontSize,Callback=function(v) config.fontSize=v end})
local scaling=style:AddSection("Distance scaling","Keeps distant labels, bones and pins compact.",{Column="right"})
scaling:AddToggle({Title="Scale with distance",Default=config.distanceScaling,Callback=function(v) config.distanceScaling=v end})
scaling:AddSlider({Title="Start scaling at",Min=10,Max=200,Step=10,Default=config.scaleNear,Suffix=" studs",Callback=function(v) config.scaleNear=v end})
scaling:AddSlider({Title="Smallest size at",Min=200,Max=1500,Step=50,Default=config.scaleFar,Suffix=" studs",Callback=function(v) config.scaleFar=v end})
scaling:AddSlider({Title="Minimum scale",Min=50,Max=100,Step=5,Default=config.minimumScale*100,Suffix="%",Callback=function(v) config.minimumScale=v/100 end})
local clutter=style:AddSection("Smart decluttering","Same-frame label layout; source pins stay visible.",{Column="left"})
clutter:AddToggle({Title="Smart decluttering",Default=config.declutter,Callback=function(v) config.declutter=v end})
clutter:AddSlider({Title="Maximum labels",Min=8,Max=48,Step=1,Default=config.labelBudget,Callback=function(v) config.labelBudget=v end})
clutter:AddSlider({Title="Label spacing",Min=0,Max=12,Step=1,Default=config.labelSpacing,Suffix=" px",Callback=function(v) config.labelSpacing=v end})
clutter:AddToggle({Title="Merge name and distance",Default=config.mergeLabels,Callback=function(v) config.mergeLabels=v end})
declutterStatus=clutter:AddStatus({Title="Label layout",Default="Measuring..."})
clutter:AddLabel({Title="Priority",Description="Bomb > newest shots > movement sounds > nearby enemies > last-seen labels. Text can be repositioned or hidden; source pins stay visible."})
local session = style:AddSection("Session","RightShift opens the menu. End hides everything.",{Column="right"})
session:AddLabel({Title="Enemy identity",Description="Anonymous rigs use their slot number. Unavailable enemy health is omitted."})
session:AddLabel({Title="Two ESP layers?",Description="Matcha native player ESP has separate team/color settings. Disable it if it adds duplicate boxes."})
session:AddButton({Title="Unload Nexus",ButtonText="Unload",Variant="danger",Callback=function() ui:Destroy() end})

local profilesTab=ui:AddTab({Title="Profiles & HUD",Icon="settings"})
local perf=profilesTab:AddSection("Live performance","Measured over a rolling half-second window.",{Column="left"})
perf:AddToggle({Title="Performance HUD",Default=config.performanceHud,Callback=function(v) config.performanceHud=v end})
performanceStatus=perf:AddStatus({Title="Draw / discovery / cost",Default="Measuring..."})
perf:AddLabel({Title="Refresh rates",Description="FPS is drawing frequency. ESP and SOUNDS show actual collection rates, not requested intervals."})
perf:AddLabel({Title="Distance scaling",Description="Adjust scaling under Colors. Player box geometry stays aligned with the body."})
local profiles=profilesTab:AddSection("Saved profiles","Save the current ESP settings and colors to disk.",{Column="right"})
selectedProfileControl=profiles:AddDropdown({Title="Profile slot",Options=profileNames(),Default=selectedProfile,Callback=function(v) selectedProfile=profileName(v) end})
profiles:AddButton({Title="Save / overwrite selected",ButtonText="Save",Callback=function() saveProfile(selectedProfile) end})
profiles:AddButton({Title="Load selected profile",ButtonText="Load",Callback=function() loadProfile(selectedProfile) end})
profiles:AddButton({Title="Use selected on startup",ButtonText="Set startup",Callback=function() setStartup(selectedProfile) end})
profileStateControl=profiles:AddStatus({Title="Profile",Default="Ready"})
startupStateControl=profiles:AddStatus({Title="Startup profile",Default="Not set"})
profiles:AddButton({Title="Refresh saved profile list",ButtonText="Refresh",Callback=function() selectedProfileControl.Options=profileNames() end})
profiles:AddLabel({Title="Custom names",Description="Use Settings > Configs to save any name starting with Kontra_. Then refresh this list."})
profiles:AddButton({Title="Custom profile editor",ButtonText="Open Settings",Callback=function() ui:SelectTab("Settings") end})

-- Create a recoverable baseline without overwriting an existing user profile.
if not isfile("Nexa_Kontra_Main.json") then
    local ok=saveProfile("Kontra_Main",true)
    if ok and not isfile(STARTUP_FILE) then setStartup("Kontra_Main",true) end
end
if isfile(STARTUP_FILE) then
    local ok,name=pcall(readfile,STARTUP_FILE)
    if ok and type(name)=="string" and string.match(name,"^Kontra_[%w_%-]+$") then
        if startupStateControl then startupStateControl:SetValue(name,"success") end
        if not previousConfig then state.startupLoaded=loadProfile(name,true) end
    end
end

state.connections.input=Input.InputBegan:Connect(function(input)
    if input.KeyCode==Enum.KeyCode.RightShift then
        state.open=not state.open; if state.open then ui:Show() else ui:Hide() end
    elseif input.KeyCode==Enum.KeyCode.End then
        config.enabled=false; state.open=false; hideAll(); ui:Hide()
    end
end)
state.connections.render=Run.RenderStepped:Connect(function()
    if not state.running then return end
    local renderStarted=tick()
    local ok,err=pcall(render)
    state.renderMs=(tick()-renderStarted)*1000
    if not ok then
        state.errors=state.errors+1; hideAll()
        if state.errors==1 then print("Nexus render check:",err) end
    end
end)
-- Independent scan clocks, driven by Heartbeat instead of spawned coroutines.
local nextCollectAt,nextShotAt,nextBombAt=0,0,0
state.connections.collect=Run.Heartbeat:Connect(function()
    if not state.running then return end
    local now=tick()
    if now>=nextCollectAt then
        nextCollectAt=now+config.refreshInterval
        local ok,err=pcall(collect)
        if not ok then
            state.targets={};state.errors=state.errors+1
            if state.errors==1 then print("Nexus collector check:",err) end
        end
    end
    if now>=nextShotAt then
        nextShotAt=now+(config.refreshProfile=="Fastest" and 0 or math.min(config.refreshInterval,0.05))
        local ok,err=pcall(collectShots)
        if not ok then
            state.shotScanErrors=state.shotScanErrors+1;state.errors=state.errors+1
            state.lastShotError=tostring(err);state.shotStage="error"
            if shotScanStatus then shotScanStatus:SetValue("Scanner error: "..tostring(err),"danger") end
            if state.shotScanErrors==1 then print("Nexus sound check:",err) end
        end
    end
    if now>=nextBombAt then
        nextBombAt=now+math.min(config.refreshInterval,0.05)
        local ok,err=pcall(collectBomb,now)
        if not ok then
            state.bombScanErrors=state.bombScanErrors+1;state.errors=state.errors+1
            state.bombData=nil;state.lastBombError=tostring(err)
            if bombScanStatus then bombScanStatus:SetValue("Bomb scanner error: "..tostring(err),"danger") end
            if state.bombScanErrors==1 then print("Nexus bomb check:",err) end
        end
    end
end)
ui:Notify({Title="Nexus 4.6 restarted",Content="Independent planted-bomb scanner, critical labels and recent beep fallback. RightShift: menu.",Type="success",Duration=4})
print("Kontra Nexus 4.6 cleanly restarted. Independent planted-bomb scan; live model first, explicitly labelled recent-audio fallback.")
