-- kontra-nexus / Matcha. RightShift: menu. End: hide everything.
-- Left Alt (configurable): hold for configured details. Focus: nearest received enemies.
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
local RADAR_GRID = Color3.fromRGB(104, 126, 151)
local config = {
    enabled = true, box = "Corners", labels = true, distance = true,
    skeleton = true, arrows = false, tracers = false, status = true,
    visibility = false, visibleOnly = false, range = 1200, width = 2,
    visibilityFade = true, visibilityFadeTime = 0.18, occludedOpacity = 0.4,
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
    soundConfidence = true,
    soundDetail = "Compact", maximumShotPins = 6, maximumFootPins = 8,
    soundSourceColor = Color3.fromRGB(126, 231, 212),
    soundInferenceColor = Color3.fromRGB(255, 199, 111),
    focusMode = true, focusCount = 3, unfocusedOpacity = 0.25, focusTransition = 0.12,
    holdDetails = true, detailsKey = "LeftAlt",
    lastSeenDirection = true, directionMinSpeed = 2, directionSize = 24,
    rearSounds = true, rearLifetime = 1, rearSize = 12,
    heartbeat = true, heartbeatRadius = 1.15, heartbeatRate = 72, heartbeatOpacity = 0.8,
    worldSoundPulses = true, worldPulseSeconds = 0.65, worldStepRadius = 0.85, worldShotSize = 6,
    nearbyStepPriority = true, stepAgeWeight = 0.35,
    soundDisplay = "Radar", radarSize = 148, radarRange = 120, radarCorner = "Bottom left",
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
local state = {running = true, open = true, targets = {}, pool = {}, connections = {}, ui = ui, version="4.14",
    camera = nil, team = nil, settleUntil = 0, seen = {}, errors = 0,
    stats = {enemies = 0, allies = 0, self = 0, pending = 0}, config = config, frames = 0,
    contacts = {}, ghosts = {}, ghostPool = {}, shotPool = {}, shots = {}, soundSeen = {},
    friendPositions = {}, friendTracks = {}, footRevalidated = 0, phase = nil, bombData = nil, soundWarm = false,
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
    soundDisplayStats={shots=0,footsteps=0},
    preparedTargets={},focusStats={selected=0,eligible=0},detailsShown=false,detailsHeld=false,inputPollErrors=0,
    rearPool={},rearSelection={},rearFrames=0,directionFrames=0,
    selectedShots={},selectedSteps={},shotChoicePool={},stepChoicePool={},radarFrames=0,radarBoundsCache={},radarStats={shots=0,steps=0},
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
local HEARTBEAT_SEGMENTS=20
local heartbeatUnit={}
for i=1,HEARTBEAT_SEGMENTS do
    local angle=(i-1)*math.pi*2/HEARTBEAT_SEGMENTS
    heartbeatUnit[i]={x=math.cos(angle),z=math.sin(angle)}
end
local skeletonPairs = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
}
for i = 1, 32 do
    local e = {all = {}, corners = {}, bones = {}, heartbeat = {}, heartbeatPoints = {}}
    local function add(d) e.all[#e.all + 1] = d return d end
    for j = 1, 8 do e.corners[j] = add(drawing("Line")) end
    for j = 1, #skeletonPairs do e.bones[j] = add(drawing("Line")) end
    for j=1,HEARTBEAT_SEGMENTS do
        e.heartbeat[j]=add(drawing("Line",9))
        e.heartbeatPoints[j]={x=0,y=0,visible=false}
    end
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
    e.confidence = add(text(10)); e.confidence.ZIndex = 14
    e.arrow = add(drawing("Triangle", 13)); e.arrow.Filled = true
    e.crossA = add(drawing("Line", 13)); e.crossB = add(drawing("Line", 13))
    return e
end
for i = 1, 32 do
    local e = {all = {}, dash = {}, direction = {}}
    for j = 1, 8 do e.dash[j] = drawing("Line"); e.all[#e.all+1] = e.dash[j] end
    for j = 1, 3 do e.direction[j]=drawing("Line",11);e.all[#e.all+1]=e.direction[j] end
    e.label = text(11); e.all[#e.all+1] = e.label
    state.ghostPool[i] = e
end
for i = 1, 24 do state.shotPool[i] = marker() end
for i = 1, 20 do
    local e=marker()
    e.heartbeat={};e.heartbeatPoints={}
    for j=1,HEARTBEAT_SEGMENTS do
        local line=drawing("Line",13)
        e.heartbeat[j]=line;e.all[#e.all+1]=line
        e.heartbeatPoints[j]={x=0,y=0,visible=false}
    end
    state.footPool[i]=e
end
for i=1,2 do
    local arrow=drawing("Triangle",16);arrow.Filled=true
    local label=text(11);label.ZIndex=17
    state.rearPool[i]={all={arrow,label},arrow=arrow,label=label}
end
local radar={all={},shots={},steps={}}
local function radarAdd(d) radar.all[#radar.all+1]=d return d end
radar.back=radarAdd(drawing("Circle",14));radar.back.Filled=true;radar.back.NumSides=48;radar.back.Color=INK
radar.rim=radarAdd(drawing("Circle",15));radar.rim.NumSides=48;radar.rim.Filled=false;radar.rim.Thickness=1.5
radar.mid=radarAdd(drawing("Circle",15));radar.mid.NumSides=40;radar.mid.Filled=false
radar.axisH=radarAdd(drawing("Line",15));radar.axisV=radarAdd(drawing("Line",15))
radar.heading=radarAdd(drawing("Triangle",19));radar.heading.Filled=true
radar.title=radarAdd(text(11));radar.title.ZIndex=20
radar.info=radarAdd(text(10));radar.info.ZIndex=20
for i=1,24 do
    local d=radarAdd(drawing("Quad",18));d.Filled=true;d.Thickness=1.5;radar.shots[i]=d
end
for i=1,20 do
    local d=radarAdd(drawing("Circle",18));d.Filled=true;d.NumSides=16;d.Thickness=1.5;radar.steps[i]=d
end
state.radar=radar
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
    for _, e in ipairs(state.rearPool) do hide(e) end
    hide(radar);state.radarBounds=nil
    state.radarStats.shots=0;state.radarStats.steps=0
    state.rearSelection.shot=nil;state.rearSelection.step=nil
    hide(bombMarker); bombHud.Visible=false; bombBar.Visible=false; bombBarBack.Visible=false
    defuseHud.Visible=false;defuseBar.Visible=false;defuseBarBack.Visible=false
    perfBack.Visible=false;perfLineA.Visible=false;perfLineB.Visible=false;perfAccent.Visible=false
    hud.Visible = false; hudRule.Visible = false
    state.focusStats.selected=0;state.focusStats.eligible=0
    state.soundDisplayStats.shots=0;state.soundDisplayStats.footsteps=0
end
state.cleanup = function()
    if not state.running then return end
    state.running = false
    state.detailsHeld=false;state.detailsShown=false
    for _, c in pairs(state.connections) do pcall(function() c:Disconnect() end) end
    for _, e in ipairs(state.pool) do for _, d in ipairs(e.all) do pcall(function() d:Remove() end) end end
    for _, group in ipairs({state.ghostPool,state.shotPool,state.footPool,state.rearPool,{bombMarker},{radar}}) do
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
local footStatus,footScanStatus,footRangeStatus,footStrictControl
local quietStatus,bombAnchorStatus,bombScanStatus,soundDisplayStatus,focusStatus,detailsStatus
local function validPosition(p)
    return p and p.X == p.X and p.Y == p.Y and p.Z == p.Z
        and math.abs(p.X) < 100000 and math.abs(p.Y) < 100000 and math.abs(p.Z) < 100000
end
local function selectSoundSources(events,camera,now,lifetime,range,limit,excluded,prioritize,pool,result,predicate)
    limit=math.max(0,math.floor(limit))
    if limit==0 or not camera or not validPosition(camera.Position) then
        for i=#result,1,-1 do result[i]=nil end
        return result
    end
    local n=0
    local ageWeight=math.max(0,math.min(1,config.stepAgeWeight))
    for i,event in ipairs(events) do
        local age=now-event.at
        if event~=excluded and event.sourceKind=="received_emitter" and age>=0 and age<lifetime and validPosition(event.position)
                and (not predicate or predicate(event,now)) then
            local distance=(event.position-camera.Position).Magnitude
            if distance>=6 and distance<=range then
                n=n+1
                local choice=pool[n]
                if not choice then choice={};pool[n]=choice end
                choice.event,choice.age,choice.distance,choice.order=event,age,distance,i
                choice.score=prioritize and ((1-ageWeight)*distance/math.max(1,range)+ageWeight*age/math.max(0.01,lifetime)) or 0
                result[n]=choice
            end
        end
    end
    for i=#result,n+1,-1 do result[i]=nil end
    table.sort(result,function(a,b)
        if a.score~=b.score then return a.score<b.score end
        if a.event.at~=b.event.at then return a.event.at>b.event.at end
        if a.distance~=b.distance then return a.distance<b.distance end
        local aId,bId=a.event.id or a.order,b.event.id or b.order
        return aId>bId
    end)
    limit=math.max(0,math.floor(limit))
    for i=#result,limit+1,-1 do result[i]=nil end
    return result
end
state.selectSoundSources=selectSoundSources
local function radarBasis(camera,previous)
    local cf=camera and camera.CFrame
    local look=cf and cf.LookVector
    local length=validPosition(look) and math.sqrt(look.X*look.X+look.Z*look.Z) or 0
    if length>0.001 then return Vector3.new(look.X/length,0,look.Z/length) end
    local right=cf and cf.RightVector
    length=validPosition(right) and math.sqrt(right.X*right.X+right.Z*right.Z) or 0
    if length>0.001 then return Vector3.new(right.Z/length,0,-right.X/length) end
    if validPosition(previous) then
        length=math.sqrt(previous.X*previous.X+previous.Z*previous.Z)
        if length>0.001 then return Vector3.new(previous.X/length,0,previous.Z/length) end
    end
    return Vector3.new(0,0,-1)
end
state.radarBasis=radarBasis
local function radarPoint(position,cameraPosition,forward,radius,range)
    if not validPosition(position) or not validPosition(cameraPosition) or range<=0 or radius<=0 then return nil end
    local delta=position-cameraPosition
    local rightX,rightZ=-forward.Z,forward.X
    local x=(delta.X*rightX+delta.Z*rightZ)/range
    local y=-(delta.X*forward.X+delta.Z*forward.Z)/range
    local fraction=math.sqrt(x*x+y*y)
    local clamped=fraction>1
    if clamped then x,y=x/fraction,y/fraction end
    return x*radius,y*radius,clamped,math.sqrt(delta.X*delta.X+delta.Z*delta.Z)
end
state.radarPoint=radarPoint
local function radarLayout(view,size,corner)
    local available=math.min(view.X-32,view.Y-90)
    if available<64 then return nil end
    local radius=math.max(64,math.min(size,available))*0.5
    local right=corner=="Bottom right" or corner=="Top right"
    local top=corner=="Top left" or corner=="Top right"
    local x=right and view.X-radius-16 or radius+16
    local y=top and radius+78 or view.Y-radius-32
    y=math.max(radius+28,math.min(view.Y-radius-24,y))
    return x,y,radius
end
state.radarLayout=radarLayout
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
local function clamp01(value) return math.max(0,math.min(1,value)) end
local function tweenSample(from,to,started,now,duration)
    local t=duration>0 and clamp01((now-started)/duration) or 1
    t=t*t*(3-2*t)
    return from+(to-from)*t
end
local function visibilitySample(cache,clear,showLive,now)
    local wanted=showLive and ((config.visibilityFade and not clear) and config.occludedOpacity or 1) or 0
    local wantedColor=clear and 1 or 0
    local duration=config.visibilityFade and math.max(0,config.visibilityFadeTime) or 0
    -- A newly received target is shown immediately. Only state changes fade.
    if not cache.fadeInitialized or duration==0 then
        cache.fadeInitialized=true
        cache.fadeFrom,cache.fadeGoal,cache.fadeAt=wanted,wanted,now
        cache.colorFrom,cache.colorGoal,cache.colorAt=wantedColor,wantedColor,now
    end
    local alpha=tweenSample(cache.fadeFrom,cache.fadeGoal,cache.fadeAt,now,duration)
    local color=tweenSample(cache.colorFrom,cache.colorGoal,cache.colorAt,now,duration)
    if wanted~=cache.fadeGoal then
        cache.fadeFrom,cache.fadeGoal,cache.fadeAt=alpha,wanted,now
    end
    if wantedColor~=cache.colorGoal then
        cache.colorFrom,cache.colorGoal,cache.colorAt=color,wantedColor,now
    end
    cache.visibilityAlpha=alpha
    return alpha,color
end
state.visibilitySample=visibilitySample
local function visibilityColor(blend)
    if not config.visibility then return config.enemyColor end
    local a,b=config.enemyColor,config.visibleColor
    return Color3.new(a.R+(b.R-a.R)*blend,a.G+(b.G-a.G)*blend,a.B+(b.B-a.B)*blend)
end
state.visibilityColor=visibilityColor
local function observeContact(previous,key,slot,root,head,now)
    if not validPosition(root) or not validPosition(head) then return nil end
    local contact=previous
    if not contact or contact.key~=key or not validPosition(contact.root) or not validPosition(contact.head) then
        return {key=key,slot=slot,root=root,head=head,at=now,motionBase=root,motionAt=now}
    end
    local dt=now-(contact.motionAt or contact.at)
    local observationDt=now-contact.at
    local jump=root-contact.root
    local horizontalJump=math.sqrt(jump.X*jump.X+jump.Z*jump.Z)
    local impossibleJump=jump.Magnitude>10 or (horizontalJump>1 and (observationDt<=0 or horizontalJump/observationDt>60))
    -- Reject large jumps immediately, even before the normal sampling window.
    if impossibleJump or observationDt<0 or dt<0 or dt>0.35 then
        contact.motionBase=root;contact.motionAt=now
        contact.direction=nil;contact.directionAt=nil;contact.motionSpeed=nil
    elseif dt>=0.1 then
        local delta=root-(contact.motionBase or contact.root)
        local horizontal=Vector3.new(delta.X,0,delta.Z)
        local speed=horizontal.Magnitude/dt
        contact.motionBase=root;contact.motionAt=now
        if delta.Magnitude<=10 and speed>0.001 and speed>=config.directionMinSpeed and speed<=60 then
            contact.direction=horizontal/horizontal.Magnitude
            contact.directionAt=now;contact.motionSpeed=speed
        else
            contact.direction=nil;contact.directionAt=nil;contact.motionSpeed=nil
        end
    end
    contact.root,contact.head,contact.at=root,head,now
    return contact
end
state.observeContact=observeContact
local function lastDirection(contact)
    local direction=contact.direction
    local age=contact.directionAt and contact.at-contact.directionAt
    if not direction or not validPosition(direction) or not age or age<0 or age>0.35 then return nil end
    local length=math.sqrt(direction.X*direction.X+direction.Z*direction.Z)
    if length<0.9 or length>1.1 or math.abs(direction.Y)>0.01 or (contact.motionSpeed or 0)<config.directionMinSpeed then return nil end
    return direction
end
state.lastDirection=lastDirection
local function rearBearing(position,camera)
    if not camera or not validPosition(position) then return nil end
    local delta=position-camera.Position
    local distance=delta.Magnitude
    if distance<6 then return nil end
    local forward=delta:Dot(camera.CFrame.LookVector)/distance
    if forward>=-0.1 then return nil end
    local side=delta:Dot(camera.CFrame.RightVector)/distance
    return math.max(-1,math.min(1,side)),-forward,distance
end
state.rearBearing=rearBearing
local function selectRear(list,lifetime,range,now,camera,stepsOnly,predicate)
    local ttl=math.min(lifetime,config.rearLifetime)
    for i=#list,1,-1 do
        local event=list[i]
        local age=now-event.at
        if event.sourceKind=="received_emitter" and (not stepsOnly or event.kind=="STEP") and age>=0 and age<ttl
                and (not predicate or predicate(event,now)) then
            local side,depth,distance=rearBearing(event.position,camera)
            if side and distance<=range then return event,side,depth,distance,age,ttl end
        end
    end
    return nil
end
state.selectRear=selectRear
local function keyNumber(value)
    if type(value)=="number" then return value end
    local ok,n=pcall(function() return value.Value end)
    return ok and type(n)=="number" and n or nil
end
state.keyNumber=keyNumber
local detailKeys={LeftAlt=keyNumber(Enum.KeyCode.LeftAlt) or 308,
    LeftControl=keyNumber(Enum.KeyCode.LeftControl) or 306,X=keyNumber(Enum.KeyCode.X) or 120}
local detailKeyLabels={LeftAlt="Left Alt",LeftControl="Left Control",X="X"}
local menuKey=keyNumber(Enum.KeyCode.RightShift) or 303
local stopKey=keyNumber(Enum.KeyCode.End) or 279
local function detailsRequested(held,active)
    return not config.holdDetails or (held==true and active~=false)
end
state.detailsRequested=detailsRequested
local function pollDetails()
    if not config.holdDetails then state.detailsHeld=false return true end
    local active=true
    if type(isrbxactive)=="function" then
        local ok,value=pcall(isrbxactive)
        active=ok and value==true
    end
    local held=false
    if active then
        -- Matcha expects a numeric enum value here, not an EnumItem wrapper.
        local ok,value=pcall(function() return Input:IsKeyDown(detailKeys[config.detailsKey] or detailKeys.LeftAlt) end)
        held=ok and value==true
        if not ok then
            state.inputPollErrors=state.inputPollErrors+1
            if state.inputPollErrors==1 then print("Nexus detail-key check:",value) end
        end
    end
    state.detailsHeld=held
    return detailsRequested(held,active)
end
state.pollDetails=pollDetails
local function focusOpacity(cache,focused,now)
    local wanted=(not config.focusMode or focused) and 1 or clamp01(config.unfocusedOpacity)
    local duration=config.focusMode and math.max(0,config.focusTransition) or 0
    if not cache.focusInitialized or duration==0 then
        cache.focusInitialized=true
        cache.focusFrom,cache.focusGoal,cache.focusAt=wanted,wanted,now
    end
    local alpha=tweenSample(cache.focusFrom,cache.focusGoal,cache.focusAt,now,duration)
    if cache.focusGoal~=wanted then cache.focusFrom,cache.focusGoal,cache.focusAt=alpha,wanted,now end
    return alpha
end
state.focusOpacity=focusOpacity
local function soundAssociation(position,now,lifetime,anchor)
    local nearest,evidence=math.huge,nil
    for _,contact in pairs(state.contacts) do
        local age=now-contact.at
        local point=contact[anchor]
        if age>=0 and age<=lifetime and validPosition(point) then
            local distance=(position-point).Magnitude
            if distance<nearest then
                nearest=distance
                evidence={key=contact.key,distance=distance,age=age}
            end
        end
    end
    return nearest,nearest<=10 and evidence or nil
end
local function setSoundEvidence(event,evidence)
    event.sourceKind="received_emitter"
    event.linked=evidence~=nil
    -- Evidence belongs to this sound sample; never attach it to a later rig position.
    event.association=evidence
end
local function soundConfidence(event)
    if not config.soundConfidence then return nil end
    if event.sourceKind~="received_emitter" then return "SOURCE UNVERIFIED / ID UNKNOWN",config.soundInferenceColor end
    local evidence=event.association
    if evidence then
        local kind=evidence.age<=0.35 and "ENEMY NEARBY?" or "LAST-SEEN NEARBY?"
        return string.format("SOURCE RECEIVED / %s / sample %.1fs old",kind,evidence.age),config.soundInferenceColor
    end
    return "SOURCE RECEIVED / ID UNKNOWN",config.soundSourceColor
end
state.soundConfidence=soundConfidence
local function soundMarkerText(event,distance,age,isStep,cameraPosition,details)
    if config.soundDetail=="Pins only" then return nil end
    local kind=isStep and event.kind or "SHOT"
    if details==false then return kind end
    if config.soundDetail=="Detailed" then
        local label=isStep and string.format("%s / %.0f studs / %.1fs",kind,distance,age)
            or string.format("SHOT / %s / %.0f studs / %.1fs",event.weapon,distance,age)
        local confidence,color=soundConfidence(event)
        return label..heightTag(event.position,cameraPosition),confidence,color
    end
    local label=string.format("%s %.0fst",kind,distance)
    if config.heightIndicators then
        local delta=event.position.Y-cameraPosition.Y
        if delta>6 then label=label.." UP" elseif delta< -6 then label=label.." DOWN" end
    end
    -- No extra source/age sentence in compact mode. Question marks always
    -- denote a proximity estimate, never a confirmed shooter identity.
    if config.soundConfidence and event.sourceKind=="received_emitter" and event.association then
        label=label..(event.association.age<=0.35 and " E?" or " LS?")
    end
    return label
end
state.soundMarkerText=soundMarkerText
state.featureControls={}
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
-- Sound emitters are anonymous. Hide close ally-path matches and ambiguous overlaps,
-- never treat a nearby sound as a confirmed player identity.
local footTeamFilter={}
function footTeamFilter.distance(position,root,kind)
    if not validPosition(position) or not validPosition(root) then return math.huge end
    local height=root.Y-position.Y
    local allowed=kind=="LADDER" and math.abs(height)<=4 or (kind~="LADDER" and height>=-1.25 and height<=5.5)
    if not allowed then return math.huge end
    local dx,dz=position.X-root.X,position.Z-root.Z
    return math.sqrt(dx*dx+dz*dz)
end
function footTeamFilter.record(key,position,now)
    if not validPosition(position) then return end
    local track=state.friendTracks[key]
    if not track or now<track.at then track={samples={}};state.friendTracks[key]=track end
    track.position,track.at=position,now
    local samples=track.samples
    local last=samples[#samples]
    if not last or now-last.at>=0.05 then samples[#samples+1]={position=position,at=now} end
    while #samples>32 or (#samples>0 and now-samples[1].at>1.6) do table.remove(samples,1) end
end
state.recordFriend=footTeamFilter.record
function footTeamFilter.enemyDistance(position,kind,at,now)
    local enemy=math.huge
    for _,contact in pairs(state.contacts) do
        local age=now-contact.at
        if age>=0 and age<=0.25 and math.abs(at-contact.at)<=0.25 then
            enemy=math.min(enemy,footTeamFilter.distance(position,contact.root,kind))
        end
    end
    return enemy
end
function footTeamFilter.friendly(position,kind,at,now,observedEnemy)
    local friend=math.huge
    -- Current positions are useful only for very recent samples, not old footprints.
    if now-at>=0 and now-at<=0.12 then
        for _,root in ipairs(state.friendPositions) do
            friend=math.min(friend,footTeamFilter.distance(position,root,kind))
        end
    end
    for _,track in pairs(state.friendTracks) do
        local previous
        for _,sample in ipairs(track.samples) do
            local dt=at-sample.at
            if dt>=-0.12 and dt<=0.35 then
                friend=math.min(friend,footTeamFilter.distance(position,sample.position,kind))
                if previous and sample.at-previous.at<=0.18 and sample.at>previous.at
                        and (sample.position-previous.position).Magnitude<=8 then
                    local a,b=previous.position,sample.position
                    local dx,dz=b.X-a.X,b.Z-a.Z
                    local length=dx*dx+dz*dz
                    if length>0.0001 then
                        local t=math.max(0,math.min(1,((position.X-a.X)*dx+(position.Z-a.Z)*dz)/length))
                        friend=math.min(friend,footTeamFilter.distance(position,a+(b-a)*t,kind))
                    end
                end
                previous=sample
            else previous=nil end
        end
        local dt=at-track.at
        if dt>=-0.12 and dt<=0.35 then
            friend=math.min(friend,footTeamFilter.distance(position,track.position,kind))
        end
    end
    if friend>3.5 then return false end
    -- Only distinctly closer, fresh enemy evidence can outweigh an ally-path match.
    local enemy=observedEnemy or footTeamFilter.enemyDistance(position,kind,at,now)
    return not (enemy+1<friend)
end
state.friendlyFoot=footTeamFilter.friendly
function footTeamFilter.allowed(event,now)
    -- Keep source-time evidence; later enemy movement cannot turn an accepted
    -- enemy-nearer sound into a teammate match at the old location.
    if event.footEnemyDistance==nil then
        event.footEnemyDistance=footTeamFilter.enemyDistance(event.position,event.kind,event.at,now)
    end
    if config.footHideAllies then
        if event.teammateExcluded then return false end
        if footTeamFilter.friendly(event.position,event.kind,event.at,now,event.footEnemyDistance) then
            event.teammateExcluded=true
            return false
        end
    end
    return not config.footEnemyOnly or event.linked==true
end
state.stepAllowed=footTeamFilter.allowed
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
        state.contacts = {}; state.ghosts = {}; state.shots = {};state.footsteps={};state.friendTracks={};state.latestBombCue=nil
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
            if config.visibility or config.visibilityFade or config.visibleOnly or config.lastSeenPolicy == "Line of sight loss" then
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
                        footTeamFilter.record(key,rp,now)
                        state.contacts[key] = nil
                    elseif isAlly then
                        stats.allies = stats.allies + 1
                        friends[#friends+1] = rp
                        footTeamFilter.record(key,rp,now)
                        state.contacts[key] = nil
                    elseif now < state.settleUntil then
                        stats.pending = stats.pending + 1
                    elseif distance <= config.range then
                        local clear = false
                        if params then
                            local hit = World:Raycast(camera.Position, hp - camera.Position,params)
                            clear = not hit or (hit.Instance and hit.Instance:IsDescendantOf(rig)) or false
                        end
                        local showLive = (not config.visibleOnly or clear) and (config.lastSeenPolicy~="Line of sight loss" or clear)
                        -- Visible-only memory must freeze too, never follow a hidden rig.
                        local canRemember = showLive and (config.lastSeenPolicy == "Replication loss" or clear)
                        if canRemember then
                            for previousKey, contact in pairs(state.contacts) do
                                if contact.slot==rig.Name and previousKey~=key then state.contacts[previousKey]=nil end
                            end
                            state.contacts[key] = observeContact(state.contacts[key],key,rig.Name,rp,hp,now)
                        end
                        if showLive or config.visibilityFade then
                            if showLive then live[key]=true end
                            local cached=state.rigCache[key]
                            if not cached then
                                cached={bones={},poseBones={},nextBonesAt=0,label="ENEMY  /  "..rig.Name}
                                state.rigCache[key]=cached
                            end
                            local quiet=showLive and sampleQuiet(cached,rp,now,distance) or false
                            if not showLive then cached.quiet=false end
                            if showLive and config.skeleton and now>=cached.nextBonesAt then
                                local bones={}
                                for j, pair in ipairs(skeletonPairs) do
                                    bones[j] = {rig:FindFirstChild(pair[1]), rig:FindFirstChild(pair[2])}
                                end
                                cached.bones=bones;cached.nextBonesAt=now+0.5
                            end
                            result[#result + 1] = {
                                head = head, root = root, bones = cached.bones, clear = clear, key=key,
                                showLive=showLive,
                                label = cached.label, distance = math.floor(distance) .. " studs",
                                quiet=quiet,speed=cached.speed or 0,motion=cached,
                            }
                            if showLive then
                                stats.enemies = stats.enemies + 1
                                if quiet then stats.quiet=stats.quiet+1 end
                                nearest = math.min(nearest, distance)
                            end
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
    for key,track in pairs(state.friendTracks) do if now-track.at>1.6 then state.friendTracks[key]=nil end end
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
        if focusStatus then
            local f=state.focusStats
            focusStatus:SetValue(config.focusMode and (f.selected.." / "..f.eligible.." received targets emphasized") or "Focus off","accent")
        end
        if detailsStatus then
            detailsStatus:SetValue(not config.holdDetails and "Configured details always visible"
                or (state.detailsShown and "Details held" or ((detailKeyLabels[config.detailsKey] or "Left Alt")..": hold for details")),"accent")
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
    local nearestEnemy,evidence=soundAssociation(position,now,5,"head")
    local nearestFriend=math.huge
    for _,pos in ipairs(state.friendPositions) do nearestFriend=math.min(nearestFriend,(position-pos).Magnitude) end
    if nearestFriend<9 and nearestFriend<=nearestEnemy+1 then return reject("ally") end
    if config.shotsEnemyOnly and nearestEnemy>10 then return reject("unlinked") end
    state.farthestShot=math.max(state.farthestShot,distance)
    -- An unlinked source is gunfire, not a confirmed enemy identity.
    for index,shot in ipairs(state.shots) do
        if now-shot.at>=0 and now-shot.at<0.3 and (shot.position-position).Magnitude<3 then
            shot.position=position;shot.at=now;shot.weapon=weapon
            setSoundEvidence(shot,evidence)
            -- A merged burst is the newest event too, even if its slot was old.
            table.remove(state.shots,index);state.shots[#state.shots+1]=shot
            state.shotEvents=state.shotEvents+1
            return true
        end
    end
    state.shotSequence=state.shotSequence+1
    local shot={position=position,weapon=weapon,at=now,id=state.shotSequence}
    setSoundEvidence(shot,evidence)
    state.shots[#state.shots+1]=shot
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
    local enemy,evidence=soundAssociation(position,now,1.5,"root")
    local observedEnemy=footTeamFilter.enemyDistance(position,kind,now,now)
    if config.footHideAllies and footTeamFilter.friendly(position,kind,now,now,observedEnemy) then return reject("ally") end
    if config.footEnemyOnly and enemy>10 then return reject("unlinked") end
    state.farthestFoot=math.max(state.farthestFoot,distance)
    -- Merge nearby recent steps; each update is an actual sound position,
    -- not a predicted player location. Expired markers never follow a rig.
    for index,step in ipairs(state.footsteps) do
        if now-step.at>=0 and now-step.at<0.65 and (step.position-position).Magnitude<6 then
            step.position=position;step.at=now;step.kind=kind;step.surface=surface
            step.footEnemyDistance=observedEnemy;step.teammateExcluded=nil
            setSoundEvidence(step,evidence)
            table.remove(state.footsteps,index);state.footsteps[#state.footsteps+1]=step
            state.footEvents=state.footEvents+1;return true
        end
    end
    state.footSequence=state.footSequence+1
    local step={position=position,at=now,kind=kind,surface=surface,id=state.footSequence,footEnemyDistance=observedEnemy}
    setSoundEvidence(step,evidence)
    state.footsteps[#state.footsteps+1]=step
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
    for _,step in ipairs(state.footsteps) do
        if now-step.at<=config.footSeconds then
            if footTeamFilter.allowed(step,now) then recentSteps[#recentSteps+1]=step
            else state.footRevalidated=state.footRevalidated+1 end
        end
    end
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
        if soundDisplayStatus then
            soundDisplayStatus:SetValue(string.format("%d shots / %d steps selected / %s",state.soundDisplayStats.shots,
                state.soundDisplayStats.footsteps,config.soundDetail),"accent")
        end
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
local function queueLabel(d,value,x,y,size,color,opacity,priority,key,secondary,secondaryValue,secondaryColor)
    d.Text=value;d.Size=size;d.Color=color;d.Transparency=opacity
    local secondSize=math.max(9,size-1)
    if secondary then
        secondary.Text=secondaryValue;secondary.Size=secondSize;secondary.Color=secondaryColor
        secondary.Transparency=opacity;secondary.Visible=false
    end
    if not config.declutter then
        d.Position=Vector2.new(x,y);d.Visible=true
        if secondary then secondary.Position=Vector2.new(x,y+size+3);secondary.Visible=true end
        return
    end
    d.Visible=false
    labelCount=labelCount+1
    local r=labelCache[labelCount]
    if not r then r={};labelCache[labelCount]=r end
    r.d,r.x,r.y,r.priority,r.key=d,x,y,priority,tostring(key)
    r.secondary,r.lineOffset=secondary,size+3
    -- Conservative bounds leave room for font bearings and fractional sizing.
    r.w=math.max(size, #value*size*0.65+6);r.h=size+4
    if secondary then
        r.w=math.max(r.w,#secondaryValue*secondSize*0.65+6)
        r.h=r.h+secondSize+3
    end
    labelOrder[labelCount]=r
end
local reservedHud={{},{},{},{}}
local function flushLabels(view)
    for i=#labelOrder,labelCount+1,-1 do labelOrder[i]=nil end
    if not config.declutter then
        state.labelStats={requested=0,shown=0,hidden=0,moved=0};return
    end
    local reserved={}
    if config.status then
        local r=reservedHud[1];r.px,r.py,r.w,r.h=12,12,380,28;reserved[#reserved+1]=r
    end
    if perfBack.Visible then
        local r=reservedHud[2];r.px,r.py,r.w,r.h=math.max(15,view.X-287),14,271,52;reserved[#reserved+1]=r
    end
    if bombHud.Visible or defuseHud.Visible then
        local r=reservedHud[3];r.px,r.py,r.w,r.h=view.X*0.5-170,65,340,68;reserved[#reserved+1]=r
    end
    if state.radarBounds then reserved[#reserved+1]=state.radarBounds end
    local shown,moved=layoutLabels(labelOrder,view,reserved,config.labelBudget,config.labelSpacing)
    for _,r in ipairs(labelOrder) do
        if r.placed then
            r.d.Position=Vector2.new(r.px+r.w*0.5,r.py);r.d.Visible=true
            if r.secondary then
                r.secondary.Position=Vector2.new(r.px+r.w*0.5,r.py+r.lineOffset)
                r.secondary.Visible=true
            end
        end
    end
    state.labelStats.requested=labelCount;state.labelStats.shown=shown
    state.labelStats.hidden=labelCount-shown;state.labelStats.moved=moved
end

local function segment(d, x1, y1, x2, y2, color, width, opacity)
    d.From = Vector2.new(x1, y1); d.To = Vector2.new(x2, y2)
    d.Color = color; d.Thickness = width or config.width
    d.Transparency = opacity or config.opacity; d.Visible = true
end
-- Cosmetic double-beat, independent of health, sound and network updates.
local function heartbeatSample(elapsed)
    local rate=math.max(40,math.min(140,config.heartbeatRate))
    local phase=(elapsed*rate/60)%1
    local first=(phase-0.12)/0.065
    local second=(phase-0.34)/0.085
    local beat=math.min(1,math.exp(-first*first)+0.6*math.exp(-second*second))
    return math.max(0.6,math.min(2.5,config.heartbeatRadius))*(1+0.14*beat),0.58+0.42*beat
end
state.heartbeatSample=heartbeatSample
local function drawGroundRing(e,center,camera,color,opacity,radius,width)
    if opacity<=0.01 or not validPosition(center) then return end
    if (center-camera.Position):Dot(camera.CFrame.LookVector)<=0.05 then return end
    local view=camera.ViewportSize
    for i,unit in ipairs(heartbeatUnit) do
        local point,onScreen=WorldToScreen(center+Vector3.new(unit.x*radius,0,unit.z*radius))
        local p=e.heartbeatPoints[i]
        p.x,p.y=point.X,point.Y
        p.visible=onScreen and p.x==p.x and p.y==p.y and p.x>=0 and p.x<=view.X and p.y>=0 and p.y<=view.Y
    end
    for i,p in ipairs(e.heartbeatPoints) do
        local q=e.heartbeatPoints[i%HEARTBEAT_SEGMENTS+1]
        if p.visible and q.visible then
            segment(e.heartbeat[i],p.x,p.y,q.x,q.y,color,width,opacity)
        end
    end
end
local function drawHeartbeat(e,rp,camera,color,alpha,radius,pulse,emphasis)
    if not config.heartbeat or alpha<=0.01 then return end
    -- Same posed foot baseline as the box; a filtered fade never follows hidden motion.
    local center=rp-Vector3.new(0,2.85,0)
    local opacity=alpha*math.max(0,math.min(1,config.heartbeatOpacity))*pulse
    drawGroundRing(e,center,camera,color,opacity,radius,math.max(1,1.4*emphasis))
end
local function soundPulseSample(age,lifetime)
    local duration=math.min(lifetime,math.max(0.2,math.min(1.2,config.worldPulseSeconds)))
    if age<0 or age>=duration or duration<=0 then return nil end
    local fraction=age/duration
    return fraction,config.opacity*0.85*(1-fraction)*(1-fraction)
end
state.soundPulseSample=soundPulseSample
local function drawSmallSoundPulse(e,event,age,lifetime,camera,isStep)
    local fraction,opacity=soundPulseSample(age,lifetime)
    if not fraction or not validPosition(event.position) then return end
    if isStep and event.kind~="LADDER" then
        -- Kontra's remote footsteps are already placed at the floor by its Blockcast.
        -- Freeze that received contact point; do not move it with an inferred player.
        local radius=math.max(0.4,math.min(1.6,config.worldStepRadius))*(0.65+fraction*0.7)
        drawGroundRing(e,event.position+Vector3.new(0,0.04,0),camera,config.footColor,opacity,radius,1.4)
    else
        local point,onScreen=WorldToScreen(event.position)
        local view=camera.ViewportSize
        if onScreen and point.X==point.X and point.Y==point.Y and point.X>=0 and point.X<=view.X and point.Y>=0 and point.Y<=view.Y then
            local size=isStep and 5 or math.max(3,math.min(10,config.worldShotSize))
            e.ring.Position=point;e.ring.Radius=size+fraction*4
            e.ring.Color=isStep and config.footColor or config.shotColor
            e.ring.Thickness=1.4;e.ring.Transparency=opacity;e.ring.Visible=true
        end
    end
end
local function drawLastDirection(e,contact,camera,alpha)
    if not config.lastSeenDirection then return false end
    local direction=lastDirection(contact)
    if not direction then return false end
    -- This short vector is only an orientation glyph at the frozen snapshot,
    -- not a predicted future position or a moving last-seen marker.
    local anchor,a=WorldToScreen(contact.root)
    local tip,b=WorldToScreen(contact.root+direction*4)
    if not a or not b then return false end
    local dx,dy=tip.X-anchor.X,tip.Y-anchor.Y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<1 then return false end
    dx,dy=dx/length,dy/length
    local size=math.max(14,math.min(40,config.directionSize))
    local x,y=anchor.X+dx*size,anchor.Y+dy*size
    segment(e.direction[1],anchor.X,anchor.Y,x,y,config.lastSeenColor,2,alpha)
    segment(e.direction[2],x,y,x-dx*7-dy*4,y-dy*7+dx*4,config.lastSeenColor,2,alpha)
    segment(e.direction[3],x,y,x-dx*7+dy*4,y-dy*7-dx*4,config.lastSeenColor,2,alpha)
    state.directionFrames=state.directionFrames+1
    return true
end
local function renderRear(camera,now)
    for _,e in ipairs(state.rearPool) do hide(e) end
    local selected=state.rearSelection
    selected.shot=nil;selected.step=nil
    if not config.rearSounds then return end
    local function show(slot,event,side,depth,distance,age,ttl,kind,color)
        if not event then return end
        local e=state.rearPool[slot]
        local view=camera.ViewportSize
        local size=math.max(8,math.min(20,config.rearSize))
        local length=math.sqrt(side*side+depth*depth)
        local dx,dy=side/length,depth/length
        local x=view.X*0.5+side*math.min(130,view.X*0.18)
        local y=view.Y-(slot==1 and 74 or 116)
        local alpha=config.opacity*math.min(1,(1-age/ttl)*2)
        e.arrow.PointA=Vector2.new(x+dx*size,y+dy*size)
        e.arrow.PointB=Vector2.new(x-dx*size*0.6-dy*size*0.6,y-dy*size*0.6+dx*size*0.6)
        e.arrow.PointC=Vector2.new(x-dx*size*0.6+dy*size*0.6,y-dy*size*0.6-dx*size*0.6)
        e.arrow.Color=color;e.arrow.Transparency=alpha;e.arrow.Visible=true
        if config.soundDetail~="Pins only" then
            local label=kind.." BEHIND"
            if state.detailsShown then label=label..string.format(" / %.0fst / %.1fs",distance,age) end
            queueLabel(e.label,label,x,y-size-18,11,color,alpha,7+slot,"rear:"..kind)
        end
        state.rearFrames=state.rearFrames+1
    end
    if config.gunshots and config.maximumShotPins>=1 then
        local event,side,depth,distance,age,ttl=selectRear(state.shots,config.shotSeconds,config.shotRange,now,camera,false)
        selected.shot=event
        show(1,event,side,depth,distance,age,ttl,"SHOT",config.shotColor)
    end
    if config.footsteps and config.maximumFootPins>=1 then
        local event,side,depth,distance,age,ttl=selectRear(state.footsteps,config.footSeconds,config.footRange,now,camera,true,footTeamFilter.allowed)
        selected.step=event
        show(2,event,side,depth,distance,age,ttl,"STEP",config.footColor)
    end
end
local function renderRadar(camera,shots,steps)
    hide(radar);state.radarBounds=nil
    state.radarStats.shots=0;state.radarStats.steps=0
    if config.soundDisplay~="Radar" and config.soundDisplay~="Both" then return end
    if not config.gunshots and not config.footsteps then return end
    local x,y,radius=radarLayout(camera.ViewportSize,config.radarSize,config.radarCorner)
    if not x then return end
    local forward=radarBasis(camera,state.radarForward)
    state.radarForward=forward
    local center=Vector2.new(x,y)
    radar.back.Position=center;radar.back.Radius=radius;radar.back.Transparency=config.opacity*0.9;radar.back.Visible=true
    local grid=RADAR_GRID
    radar.rim.Position=center;radar.rim.Radius=radius;radar.rim.Color=grid;radar.rim.Transparency=config.opacity*0.6;radar.rim.Visible=true
    radar.mid.Position=center;radar.mid.Radius=radius*0.5;radar.mid.Color=grid;radar.mid.Transparency=config.opacity*0.25;radar.mid.Visible=true
    segment(radar.axisH,x-radius+5,y,x+radius-5,y,grid,1,config.opacity*0.2)
    segment(radar.axisV,x,y-radius+5,x,y+radius-5,grid,1,config.opacity*0.2)
    radar.heading.PointA=Vector2.new(x,y-6);radar.heading.PointB=Vector2.new(x-4,y+4);radar.heading.PointC=Vector2.new(x+4,y+4)
    radar.heading.Color=WHITE;radar.heading.Transparency=config.opacity;radar.heading.Visible=true
    radar.title.Text="SOUND";radar.title.Position=Vector2.new(x,y-radius-20);radar.title.Color=WHITE
    radar.title.Transparency=config.opacity;radar.title.Visible=true
    radar.info.Text=string.format("%.0fst / %d shots / %d steps",config.radarRange,#shots,#steps)
    radar.info.Position=Vector2.new(x,y+radius+8);radar.info.Color=WHITE;radar.info.Transparency=config.opacity
    radar.info.Visible=state.detailsShown
    local bounds=state.radarBoundsCache
    bounds.px,bounds.py,bounds.w,bounds.h=x-radius-8,y-radius-24,radius*2+16,radius*2+44
    state.radarBounds=bounds
    for i,choice in ipairs(shots) do
        local dx,dy,clamped=radarPoint(choice.event.position,camera.Position,forward,radius-9,config.radarRange)
        if dx and radar.shots[i] then
            local d=radar.shots[i]
            local px,py=x+dx,y+dy
            d.PointA=Vector2.new(px,py-4);d.PointB=Vector2.new(px+4,py);d.PointC=Vector2.new(px,py+4);d.PointD=Vector2.new(px-4,py)
            d.Filled=not clamped;d.Color=config.shotColor
            d.Transparency=config.opacity*math.min(1,(1-choice.age/config.shotSeconds)*4);d.Visible=true
            state.radarStats.shots=state.radarStats.shots+1
        end
    end
    for i,choice in ipairs(steps) do
        local dx,dy,clamped=radarPoint(choice.event.position,camera.Position,forward,radius-9,config.radarRange)
        if dx and radar.steps[i] then
            local d=radar.steps[i]
            d.Position=Vector2.new(x+dx,y+dy);d.Radius=3.5;d.Filled=not clamped;d.Color=config.footColor
            d.Transparency=config.opacity*math.min(1,(1-choice.age/config.footSeconds)*2);d.Visible=true
            state.radarStats.steps=state.radarStats.steps+1
        end
    end
    state.radarFrames=state.radarFrames+1
end
local function edgeMarker(e, position, color, camera, label, opacity, priority, key, labelSize,confidence,confidenceColor)
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
    if label then
        queueLabel(e.label,label,tx-dx*25,ty-dy*25+14,labelSize,color,opacity,priority,key,
            confidence and e.confidence or nil,confidence,confidenceColor)
    end
end
local function pin(e, position, label, color, radius, opacity, arrows, camera, priority, key, minimumSize,confidence,confidenceColor)
    hide(e)
    local scale=distanceScale((position-camera.Position).Magnitude)
    radius=math.max(minimumSize or 7,radius*scale)
    local labelSize=math.max(minimumSize and 11 or 9,11*scale)
    local screen,visible=WorldToScreen(position)
    if visible then
        e.ring.Position=screen;e.ring.Radius=radius;e.ring.Color=color
        e.ring.Thickness=2;e.ring.Transparency=opacity;e.ring.Visible=true
        if label then
            local extra=confidence and labelSize+2 or 0
            queueLabel(e.label,label,screen.X,screen.Y-radius-19-extra,labelSize,color,opacity,priority,key,
                confidence and e.confidence or nil,confidence,confidenceColor)
        end
        segment(e.crossA,screen.X-4,screen.Y,screen.X+4,screen.Y,color,1)
        segment(e.crossB,screen.X,screen.Y-4,screen.X,screen.Y+4,color,1)
        e.crossA.Transparency=opacity;e.crossB.Transparency=opacity
    elseif arrows then
        edgeMarker(e,position,color,camera,label,opacity,priority,key,labelSize,confidence,confidenceColor)
    end
end
local function renderExtras(camera, now)
    local n=0
    if config.lastSeen then
        for _,contact in ipairs(state.ghosts) do
            if n>=#state.ghostPool then break end
            local age=now-contact.at
            local cache=state.rigCache[contact.key]
            local liveFade=cache and config.visibilityFade and cache.fadeGoal==0
                and now-cache.fadeAt<config.visibilityFadeTime and (cache.visibilityAlpha or 0)>0.01
            if age>=0 and age<config.lastSeenSeconds and not liveFade then
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
                        drawLastDirection(e,contact,camera,alpha)
                        local distance=(contact.root-camera.Position).Magnitude
                        queueLabel(e.label,state.detailsShown and string.format("LAST SEEN / %.1fs",age) or "LAST SEEN",top.X,top.Y-17,
                            math.max(9,11*distanceScale(distance)),config.lastSeenColor,alpha,40+age,contact.key)
                        state.ghostFrames=state.ghostFrames+1
                    end
                end
            end
        end
    end
    for i=n+1,#state.ghostPool do hide(state.ghostPool[i]) end
    renderRear(camera,now)
    local shotLimit=config.gunshots and math.max(0,math.min(#state.shotPool,math.floor(config.maximumShotPins)-(state.rearSelection.shot and 1 or 0))) or 0
    local stepLimit=config.footsteps and math.max(0,math.min(#state.footPool,math.floor(config.maximumFootPins)-(state.rearSelection.step and 1 or 0))) or 0
    local shots=selectSoundSources(state.shots,camera,now,config.shotSeconds,config.shotRange,shotLimit,
        state.rearSelection.shot,false,state.shotChoicePool,state.selectedShots)
    local steps=selectSoundSources(state.footsteps,camera,now,config.footSeconds,config.footRange,stepLimit,
        state.rearSelection.step,config.nearbyStepPriority,state.stepChoicePool,state.selectedSteps,footTeamFilter.allowed)
    renderRadar(camera,shots,steps)
    local worldSounds=config.soundDisplay~="Radar"
    local smallPulses=not worldSounds and config.worldSoundPulses
    n=0
    if worldSounds or smallPulses then
        for _,choice in ipairs(shots) do
            local shot,age,distance=choice.event,choice.age,choice.distance
            n=n+1
            local e=state.shotPool[n];hide(e)
            if smallPulses then
                drawSmallSoundPulse(e,shot,age,config.shotSeconds,camera,false)
            else
                -- Stay legible until the final quarter, then fade away.
                local opacity=config.opacity*math.min(1,(1-age/config.shotSeconds)*4)
                local label,confidence,confidenceColor=soundMarkerText(shot,distance,age,false,camera.Position,state.detailsShown)
                pin(e,shot.position,label,config.shotColor,config.shotPinSize+math.min(age,0.6)*14,
                    opacity,config.shotArrows,camera,10+age,"shot:"..tostring(shot.id),config.shotPinSize,confidence,confidenceColor)
            end
            state.shotFrames=state.shotFrames+1
        end
    end
    state.soundDisplayStats.shots=#shots+(state.rearSelection.shot and 1 or 0)
    for i=n+1,#state.shotPool do hide(state.shotPool[i]) end
    n=0
    if worldSounds or smallPulses then
        for _,choice in ipairs(steps) do
            local step,age,distance=choice.event,choice.age,choice.distance
            n=n+1
            local e=state.footPool[n];hide(e)
            if smallPulses then
                drawSmallSoundPulse(e,step,age,config.footSeconds,camera,true)
            else
                local fraction=age/config.footSeconds
                local alpha=config.opacity*math.min(1,(1-fraction)*2)
                local label,confidence,confidenceColor=soundMarkerText(step,distance,age,true,camera.Position,state.detailsShown)
                pin(e,step.position,label,config.footColor,config.footPinSize+fraction*13,
                    alpha,config.footArrows,camera,18+fraction,"step:"..tostring(step.id),config.footPinSize,confidence,confidenceColor)
                e.crossA.Visible=false;e.crossB.Visible=false
            end
            state.footFrames=state.footFrames+1
        end
    end
    state.soundDisplayStats.footsteps=#steps+(state.rearSelection.step and 1 or 0)
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
            if state.detailsShown then label=label.." / "..math.floor((position-camera.Position).Magnitude).." studs" end
            label=label..heightTag(position,camera.Position)
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
local function targetPose(target,now)
    local cache=target.motion
    if not cache then return nil end
    local rp=target.root.Parent and target.root.Position
    local hp=target.head.Parent and target.head.Position
    -- A culled/removed rig is dropped, not animated at invalid coordinates.
    if not validPosition(rp) or not validPosition(hp) then return nil end
    local showLive=target.showLive~=false and (not config.visibleOnly or target.clear)
        and (config.lastSeenPolicy~="Line of sight loss" or target.clear)
    if showLive then
        if not cache.poseRoot then cache.fadeInitialized=false end
        cache.poseRoot,cache.poseHead=rp,hp
        if config.skeleton then
            for j,pair in ipairs(target.bones) do
                local bone=cache.poseBones[j]
                if not bone then bone={};cache.poseBones[j]=bone end
                local p1=pair[1] and pair[1].Parent and pair[1].Position
                local p2=pair[2] and pair[2].Parent and pair[2].Position
                bone[1]=validPosition(p1) and p1 or nil
                bone[2]=validPosition(p2) and p2 or nil
            end
            for j=#target.bones+1,#cache.poseBones do
                cache.poseBones[j][1]=nil;cache.poseBones[j][2]=nil
            end
        else
            -- Re-enabling bones during a hide fade must not revive an old pose.
            for _,bone in ipairs(cache.poseBones) do bone[1]=nil;bone[2]=nil end
        end
    end
    local alpha,blend=visibilitySample(cache,target.clear,showLive,now)
    if not showLive then rp,hp=cache.poseRoot,cache.poseHead end
    if not validPosition(rp) or not validPosition(hp) or alpha<=0.01 then return nil end
    return rp,hp,config.opacity*alpha,visibilityColor(blend),cache.poseBones
end
state.targetPose=targetPose
local function prepareTargets(camera,now)
    local list=state.preparedTargets
    local n=0
    for _,target in ipairs(state.targets) do
        local rp,hp,alpha,color,bones=targetPose(target,now)
        local distance=rp and (rp-camera.Position).Magnitude
        if validPosition(rp) and validPosition(hp) and distance>=3.2 and distance<=config.range then
            n=n+1
            local e=list[n]
            if not e then e={};list[n]=e end
            e.target,e.rp,e.hp,e.baseAlpha,e.color,e.bones,e.distance=target,rp,hp,alpha,color,bones,distance
            e.eligible=target.showLive~=false and (not config.visibleOnly or target.clear)
                and (config.lastSeenPolicy~="Line of sight loss" or target.clear)
            e.focused=false;e.focusRank=0
        end
    end
    for i=#list,n+1,-1 do list[i]=nil end
    -- Stable keys break exact-distance ties; stale fade poses never displace live targets.
    table.sort(list,function(a,b)
        if a.eligible~=b.eligible then return a.eligible end
        if a.distance~=b.distance then return a.distance<b.distance end
        return a.target.key<b.target.key
    end)
    local selected,eligible=0,0
    local limit=math.max(2,math.min(3,math.floor(config.focusCount)))
    for _,e in ipairs(list) do
        if e.eligible then
            eligible=eligible+1
            if config.focusMode and selected<limit then
                selected=selected+1;e.focused=true;e.focusRank=selected
            end
        end
        e.alpha=e.baseAlpha*focusOpacity(e.target.motion,e.focused,now)
    end
    state.focusStats.selected=selected;state.focusStats.eligible=eligible
    return list
end
state.prepareTargets=prepareTargets
local function render(detailsOverride)
    state.frames = state.frames + 1
    labelCount=0
    local now=tick()
    -- The optional override is for bounded render tests, not a persistent input latch.
    if detailsOverride~=nil then state.detailsShown=detailsRequested(detailsOverride,true)
    else state.detailsShown=pollDetails() end
    local camera = state.camera
    if not config.enabled or not camera then hideAll() return end
    local camPos, view = camera.Position, camera.ViewportSize
    local used = 0
    local ringRadius,ringPulse=heartbeatSample(now-state.startedAt)
    local prepared=prepareTargets(camera,now)
    for _, entry in ipairs(prepared) do
        if used >= #state.pool then break end
        local target=entry.target
        local rp,hp,alpha,color,bones=entry.rp,entry.hp,entry.alpha,entry.color,entry.bones
        if validPosition(rp) and validPosition(hp) and (rp - camPos).Magnitude >= 3.2 then
            used = used + 1
            local e = state.pool[used]
            -- Clear every element before reuse; arrows cannot leave stale on-screen boxes.
            hide(e)
            local distance=entry.distance
            local scale=distanceScale(distance)
            local emphasis=config.focusMode and entry.focused and 1.15 or 1
            local lineWidth=math.max(1,config.width*scale*emphasis)
            local top, a = WorldToScreen(hp + Vector3.new(0, 0.7, 0))
            local bottom, b = WorldToScreen(rp - Vector3.new(0, 2.85, 0))
            drawHeartbeat(e,rp,camera,color,alpha,ringRadius,ringPulse,emphasis)
            local height = bottom.Y - top.Y
            if a and b and height > 8 and height < view.Y * 2 then
                local width = height * 0.48
                local x, y = top.X - width * 0.5, top.Y
                if config.box == "Corners" then
                    local cw, ch = width * 0.28, height * 0.18
                    segment(e.corners[1], x, y, x+cw, y, color,lineWidth,alpha)
                    segment(e.corners[2], x, y, x, y+ch, color,lineWidth,alpha)
                    segment(e.corners[3], x+width, y, x+width-cw, y, color,lineWidth,alpha)
                    segment(e.corners[4], x+width, y, x+width, y+ch, color,lineWidth,alpha)
                    segment(e.corners[5], x, y+height, x+cw, y+height, color,lineWidth,alpha)
                    segment(e.corners[6], x, y+height, x, y+height-ch, color,lineWidth,alpha)
                    segment(e.corners[7], x+width, y+height, x+width-cw, y+height, color,lineWidth,alpha)
                    segment(e.corners[8], x+width, y+height, x+width, y+height-ch, color,lineWidth,alpha)
                elseif config.box == "Full" then
                    e.box.Position = Vector2.new(x,y); e.box.Size = Vector2.new(width,height)
                    e.box.Color = color; e.box.Thickness = lineWidth
                    e.box.Transparency = alpha; e.box.Visible = true
                end
                local quiet=state.detailsShown and config.quietMovement and target.motion and target.motion.quiet or false
                local showLabel=config.labels and (state.detailsShown or not config.focusMode or entry.focused)
                local labelPriority=entry.focused and 16 or 20
                local mergeDistance=state.detailsShown and (showLabel or quiet) and config.declutter and config.mergeLabels and config.distance
                if showLabel or quiet then
                    local label=showLabel and (state.detailsShown and target.label or "ENEMY") or ""
                    if quiet then label=label..(label~="" and " / " or "").."QUIET MOVE?" end
                    if mergeDistance then label=label.." / "..math.floor(distance).." studs" end
                    queueLabel(e.label,label,top.X,y-17,math.max(quiet and 11 or 9,config.fontSize*scale),quiet and config.quietColor or color,
                        alpha,math.min(quiet and 17 or 20,labelPriority)+math.min(distance,2500)*0.003,target.key..":label")
                    if quiet then state.quietFrames=state.quietFrames+1 end
                end
                if state.detailsShown and config.distance and not mergeDistance then
                    queueLabel(e.distance,math.floor(distance).." studs",top.X,bottom.Y+4,math.max(9,10*scale),WHITE,
                        alpha,28+math.min(distance,2500)*0.003,target.key..":distance")
                end
                if config.tracers then segment(e.tracer,view.X*0.5,view.Y-6,bottom.X,bottom.Y,color,1,alpha) end
                if config.skeleton then
                    for j, pair in ipairs(bones) do
                        local p1, p2 = pair[1], pair[2]
                        if validPosition(p1) and validPosition(p2) then
                            local s1,v1 = WorldToScreen(p1); local s2,v2 = WorldToScreen(p2)
                            if v1 and v2 then segment(e.bones[j],s1.X,s1.Y,s2.X,s2.Y,color,math.max(1,config.skeletonWidth*scale*emphasis),alpha) end
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
                e.arrow.Color = color; e.arrow.Transparency = alpha; e.arrow.Visible = true
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
    renderExtras(camera,now)
    local showPerformance=config.performanceHud and state.detailsShown
    perfBack.Visible=showPerformance;perfLineA.Visible=showPerformance
    perfLineB.Visible=showPerformance;perfAccent.Visible=showPerformance
    if showPerformance then
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
        if readOk and string.find(raw,"Confirmed enemies only",1,true) then
            local decodedOk,data=pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
            local controls=decodedOk and type(data)=="table" and data.controls
            local oldKey="Footsteps/Footstep ESP/Confirmed enemies only/4"
            local newKey="Footsteps/Footstep ESP/Enemy-associated sounds only/4"
            if type(controls)=="table" and controls[newKey]==nil and type(controls[oldKey])=="boolean" then
                config.footEnemyOnly=controls[oldKey]
                if footStrictControl then footStrictControl:SetValue(config.footEnemyOnly,true) end
            end
        end
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

ui:CreateWindow({Title="Kontra Nexus",Subtitle="Ground step pulses & compact shot cues",GameName="Kontra",Width=780,Height=540,
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
state.featureControls.offscreen=main:AddToggle({Title="Off-screen arrows",Default=config.arrows,Callback=function(v) config.arrows=v end})
local details = visual:AddSection("Visibility and range","Only currently replicated positions are displayed.",{Column="right"})
details:AddToggle({Title="Color by line of sight",Default=config.visibility,Callback=function(v) config.visibility=v end})
state.featureControls.visibleOnly=details:AddToggle({Title="Visible targets only",Default=config.visibleOnly,Callback=function(v) config.visibleOnly=v end})
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
local fading=visual:AddSection("Visibility fade","Smooth opacity changes, without smoothing positions.",{Column="left"})
state.featureControls.fade=fading:AddToggle({Title="ESP visibility fade",Default=config.visibilityFade,Callback=function(v) config.visibilityFade=v end})
state.featureControls.fadeTime=fading:AddSlider({Title="Visibility transition",Min=0.05,Max=0.5,Step=0.01,Default=config.visibilityFadeTime,Suffix="s",Callback=function(v) config.visibilityFadeTime=v end})
state.featureControls.hiddenOpacity=fading:AddSlider({Title="Obscured opacity",Min=0,Max=100,Step=5,Default=config.occludedOpacity*100,Suffix="%",Callback=function(v) config.occludedOpacity=v/100 end})
fading:AddLabel({Title="Live positions",Description="New targets appear immediately. Boxes and bones fade together; Color by line of sight also blends colors. Enabling fade adds line-of-sight raycasts."})
fading:AddLabel({Title="When filtered out",Description="Visible-only and line-of-sight memory fade the last shown pose, not moving hidden positions. Removed or server-culled rigs disappear immediately."})
local focusing=visual:AddSection("Enemy focus","Nearest received live enemies, not last-seen or sound guesses.",{Column="left"})
state.featureControls.focus=focusing:AddToggle({Title="Enemy focus mode",Default=config.focusMode,Callback=function(v) config.focusMode=v end})
state.featureControls.focusCount=focusing:AddSlider({Title="Emphasized enemies",Min=2,Max=3,Step=1,Default=config.focusCount,Callback=function(v) config.focusCount=v end})
state.featureControls.focusDim=focusing:AddSlider({Title="Other enemy opacity",Min=5,Max=75,Step=5,Default=config.unfocusedOpacity*100,Suffix="%",Callback=function(v) config.unfocusedOpacity=v/100 end})
state.featureControls.focusTime=focusing:AddSlider({Title="Focus transition",Min=0.05,Max=0.3,Step=0.01,Default=config.focusTransition,Suffix="s",Callback=function(v) config.focusTransition=v end})
focusStatus=focusing:AddStatus({Title="Current focus",Default="Waiting for received enemies..."})
focusing:AddLabel({Title="No position delay",Description="Ranks current received positions every render. Boxes, bones, arrows and tracers share the same dimming. Focus adds a small line-weight emphasis without changing enemy colors."})
local hold=visual:AddSection("Hold for details","Minimal normally; hold a key for your configured information.",{Column="right"})
state.featureControls.hold=hold:AddToggle({Title="Hold for details",Default=config.holdDetails,Callback=function(v) config.holdDetails=v;state.detailsHeld=false end})
state.featureControls.detailsKey=hold:AddDropdown({Title="Details key",Options={"Left Alt","Left Control","X"},Default=detailKeyLabels[config.detailsKey] or "Left Alt",Callback=function(v)
    config.detailsKey=v=="Left Control" and "LeftControl" or (v=="X" and "X" or "LeftAlt")
    state.detailsHeld=false
end})
detailsStatus=hold:AddStatus({Title="Detail mode",Default="Left Alt: hold for details"})
hold:AddLabel({Title="Minimal overlay",Description="Focus enemies keep an ENEMY label; others keep dim geometry. Sounds stay STEP/SHOT without distance sentences. Hold reveals enabled distances, rig labels, configured sound detail, snapshot age and the performance HUD."})
hold:AddLabel({Title="Your toggles still apply",Description="Holding never enables disabled labels, distance, confidence or Pins-only sound text. Bomb state, countdown, HEARD and LAST SEEN warnings remain visible. RightShift and End are unchanged."})
hold:AddLabel({Title="Key release recovery",Description="The held key is polled each frame. Leaving the game window clears held details. Keys are not intercepted; choose one that does not conflict with your game controls."})

local heartbeat=visual:AddSection("Heartbeat ring","A small cosmetic pulse beneath received enemy rigs.",{Column="right"})
state.featureControls.heartbeat=heartbeat:AddToggle({Title="Heartbeat ring",Default=config.heartbeat,Callback=function(v) config.heartbeat=v end})
state.featureControls.heartbeatRadius=heartbeat:AddSlider({Title="Ring radius",Min=0.6,Max=2.5,Step=0.05,Default=config.heartbeatRadius,Suffix=" studs",Callback=function(v) config.heartbeatRadius=v end})
state.featureControls.heartbeatRate=heartbeat:AddSlider({Title="Heartbeat rate",Min=40,Max=140,Step=1,Default=config.heartbeatRate,Suffix=" bpm",Callback=function(v) config.heartbeatRate=v end})
state.featureControls.heartbeatOpacity=heartbeat:AddSlider({Title="Ring opacity",Min=10,Max=100,Step=5,Default=config.heartbeatOpacity*100,Suffix="%",Callback=function(v) config.heartbeatOpacity=v/100 end})
heartbeat:AddLabel({Title="Visual effect only",Description="The ring shares enemy colors, visibility fades and focus dimming. The beat is an animation, not a health or heartbeat measurement. It does not reveal server-hidden enemies."})

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
local confidence=intel:AddSection("Sound confidence","Received source positions and inferred associations are separate.",{Column="left"})
state.featureControls.confidence=confidence:AddToggle({Title="Sound confidence indicators",Default=config.soundConfidence,Callback=function(v) config.soundConfidence=v end})
state.featureControls.sourceColor=confidence:AddColorPicker({Title="Received-source text",Default=config.soundSourceColor,Callback=function(v) config.soundSourceColor=v end})
state.featureControls.inferenceColor=confidence:AddColorPicker({Title="Inferred-association text",Default=config.soundInferenceColor,Callback=function(v) config.soundInferenceColor=v end})
confidence:AddLabel({Title="SOURCE RECEIVED",Description="The position came from a sound emitter received by your client. It is the original sound location, not the player's current position."})
confidence:AddLabel({Title="ENEMY NEARBY? / LAST-SEEN NEARBY?",Description="Only a proximity estimate within 10 studs of a contact. The sample age is measured when the sound arrived. Neither label confirms who made it."})
confidence:AddLabel({Title="ID UNKNOWN",Description="No nearby enemy association. This does not make the sound position less reliable, and the source ring keeps its normal color and opacity. Applies to shots and footsteps."})
local presentation=intel:AddSection("Sound display","Less text, newest sounds first. Collection speed is unchanged.",{Column="right"})
state.featureControls.soundDetail=presentation:AddDropdown({Title="Sound label style",Options={"Compact","Detailed","Pins only"},Default=config.soundDetail,Callback=function(v) config.soundDetail=v end})
state.featureControls.shotLimit=presentation:AddSlider({Title="Maximum shot markers",Min=1,Max=24,Step=1,Default=config.maximumShotPins,Callback=function(v) config.maximumShotPins=v end})
state.featureControls.footLimit=presentation:AddSlider({Title="Maximum footstep markers",Min=1,Max=20,Step=1,Default=config.maximumFootPins,Callback=function(v) config.maximumFootPins=v end})
soundDisplayStatus=presentation:AddStatus({Title="Sound overlay",Default="Listening..."})
presentation:AddLabel({Title="Compact",Description="STEP/SHOT and distance only. UP/DOWN appears for a different floor. E? / LS? mean a nearby enemy / last-seen estimate, not identity. No suffix means identity unknown."})
presentation:AddLabel({Title="Detailed / Pins only",Description="Detailed restores weapon, age and received-source confidence lines. Pins only removes sound text, not source rings or edge arrows. Bomb labels are unaffected."})
presentation:AddLabel({Title="Confidence colors",Description="Received-source and inference text colors apply to the second line in Detailed mode. Compact mode keeps the normal footstep/gunshot color."})
local directions=intel:AddSection("Last-seen direction","Last observed horizontal movement, anchored to the stale snapshot.",{Column="left"})
state.featureControls.lastDirection=directions:AddToggle({Title="Last-seen direction arrows",Default=config.lastSeenDirection,Callback=function(v) config.lastSeenDirection=v end})
state.featureControls.directionSize=directions:AddSlider({Title="Direction arrow length",Min=14,Max=40,Step=1,Default=config.directionSize,Suffix=" px",Callback=function(v) config.directionSize=v end})
state.featureControls.directionSpeed=directions:AddSlider({Title="Minimum observed speed",Min=0.5,Max=6,Step=0.5,Default=config.directionMinSpeed,Suffix=" studs/s",Callback=function(v) config.directionMinSpeed=v end})
directions:AddLabel({Title="Observed, not predicted",Description="The arrow fades with LAST SEEN and never moves its old position forward. Stationary, tiny-jitter, stale, teleport and excessive-speed samples have no direction arrow. Last-seen markers must also be enabled."})
local rear=intel:AddSection("Rear sound indicator","At most one recent rear shot and one rear step.",{Column="right"})
state.featureControls.rear=rear:AddToggle({Title="Rear sound indicator",Default=config.rearSounds,Callback=function(v) config.rearSounds=v end})
state.featureControls.rearLifetime=rear:AddSlider({Title="Rear cue lifetime",Min=0.3,Max=2,Step=0.1,Default=config.rearLifetime,Suffix="s",Callback=function(v) config.rearLifetime=v end})
state.featureControls.rearSize=rear:AddSlider({Title="Rear cue size",Min=8,Max=20,Step=1,Default=config.rearSize,Suffix=" px",Callback=function(v) config.rearSize=v end})
rear:AddLabel({Title="Compact rear cues",Description="Orange SHOT BEHIND and cyan STEP BEHIND point toward received sources behind the camera. Hold details for distance/age; Pins only hides text. These are original sound locations, not confirmed enemies or live tracking."})
rear:AddLabel({Title="No duplicate pins",Description="The selected rear source replaces its usual sound marker and counts toward your existing marker limit. Disabled sound types, expired sources, range limits and team filters still apply. LAND/LADDER keep their ordinary markers."})
local radarControls=intel:AddSection("Sound radar","Camera-relative sound sources, not live player tracking.",{Column="left"})
state.featureControls.soundDisplay=radarControls:AddDropdown({Title="Sound overlay mode",Options={"Radar","World","Both"},Default=config.soundDisplay,Callback=function(v) config.soundDisplay=v end})
state.featureControls.radarSize=radarControls:AddSlider({Title="Radar diameter",Min=120,Max=220,Step=4,Default=config.radarSize,Suffix=" px",Callback=function(v) config.radarSize=v end})
state.featureControls.radarRange=radarControls:AddSlider({Title="Radar scale",Min=40,Max=500,Step=10,Default=config.radarRange,Suffix=" studs",Callback=function(v) config.radarRange=v end})
state.featureControls.radarCorner=radarControls:AddDropdown({Title="Radar corner",Options={"Bottom left","Bottom right","Top left","Top right"},Default=config.radarCorner,Callback=function(v) config.radarCorner=v end})
radarControls:AddLabel({Title="Read the radar",Description="Up is camera-forward. Cyan circles are movement sounds; orange diamonds are gunshots. It is a flat overhead view: height is not shown. Hollow edge marks are beyond the radar scale, not positions at the rim."})
radarControls:AddLabel({Title="One source set",Description="Radar mode can also show brief ground-step and small shot pulses. World/Both retain full-size labeled markers. Rear warnings stay separate, and existing source caps, filters and expiry still apply."})
radarControls:AddLabel({Title="Minimal normally",Description="Hold your details key for scale and source counts. Only received sounds are plotted; the radar cannot discover silent server-hidden players."})

local worldPulses=intel:AddSection("Small world pulses","Brief sound cues in the game world, alongside Radar mode.",{Column="right"})
state.featureControls.worldSoundPulses=worldPulses:AddToggle({Title="Small world pulses",Default=config.worldSoundPulses,Callback=function(v) config.worldSoundPulses=v end})
state.featureControls.worldPulseSeconds=worldPulses:AddSlider({Title="Pulse lifetime",Min=0.2,Max=1.2,Step=0.05,Default=config.worldPulseSeconds,Suffix="s",Callback=function(v) config.worldPulseSeconds=v end})
state.featureControls.worldStepRadius=worldPulses:AddSlider({Title="Step ground radius",Min=0.4,Max=1.6,Step=0.05,Default=config.worldStepRadius,Suffix=" studs",Callback=function(v) config.worldStepRadius=v end})
state.featureControls.worldShotSize=worldPulses:AddSlider({Title="Shot pulse size",Min=3,Max=10,Step=1,Default=config.worldShotSize,Suffix=" px",Callback=function(v) config.worldShotSize=v end})
worldPulses:AddLabel({Title="At the sound source",Description="Cyan rings expand on received foot-contact positions below the running player. Orange shot circles stay small at the received gunshot source. Ladder sounds use a small circle at their emitter. Nothing follows an inferred enemy after the sound."})
worldPulses:AddLabel({Title="Keep it clean",Description="Radar mode uses ring-only pulses without labels, crosshairs or extra arrows. The same source caps and team filters apply; the radar history can outlast the short pulse. World/Both keep their full markers."})


local movement=ui:AddTab({Title="Footsteps",Icon="target"})
local footControls=movement:AddSection("Footstep ESP","Cyan pulses at received movement-sound positions.",{Column="left"})
footControls:AddToggle({Title="Footstep ESP",Default=config.footsteps,Callback=function(v) config.footsteps=v;if not v then state.footsteps={} end end})
footControls:AddToggle({Title="Footstep edge arrows",Default=config.footArrows,Callback=function(v) config.footArrows=v end})
state.featureControls.footHideAllies=footControls:AddToggle({Title="Hide known teammates",Default=config.footHideAllies,Callback=function(v) config.footHideAllies=v end})
footStrictControl=footControls:AddToggle({Title="Enemy-associated sounds only",Default=config.footEnemyOnly,Callback=function(v) config.footEnemyOnly=v end})
footControls:AddToggle({Title="Landing and ladder sounds",Default=config.footLandings,Callback=function(v) config.footLandings=v end})
footControls:AddSlider({Title="Footstep lifetime",Min=0.5,Max=3,Step=0.1,Default=config.footSeconds,Suffix="s",Callback=function(v) config.footSeconds=v end})
footControls:AddSlider({Title="Footstep range",Min=10,Max=90,Step=5,Default=config.footRange,Suffix=" studs",Callback=function(v) config.footRange=v end})
footControls:AddSlider({Title="Footstep pulse size",Min=8,Max=18,Step=1,Default=config.footPinSize,Suffix=" px",Callback=function(v) config.footPinSize=v end})
footControls:AddColorPicker({Title="Footstep color",Default=config.footColor,Callback=function(v) config.footColor=v end})
footControls:AddToggle({Title="Above / below indicators",Default=config.heightIndicators,Callback=function(v) config.heightIndicators=v end})
footControls:AddLabel({Title="Teammate filtering",Description="Floor-aware matching uses short observed teammate paths, then rechecks existing steps before radar, world and rear rendering. Ambiguous teammate overlaps are hidden. Unknown sounds can still belong to either team; Enemy-associated sounds only removes unlinked sources too."})
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
local priority=movement:AddSection("Nearby-step priority","Prefer nearby recent movement when the marker budget is crowded.",{Column="left"})
state.featureControls.stepPriority=priority:AddToggle({Title="Nearby-step priority",Default=config.nearbyStepPriority,Callback=function(v) config.nearbyStepPriority=v end})
state.featureControls.priorityFreshness=priority:AddSlider({Title="Freshness weight",Min=0,Max=80,Step=5,Default=config.stepAgeWeight*100,Suffix="%",Callback=function(v) config.stepAgeWeight=v/100 end})
priority:AddLabel({Title="Distance plus recency",Description="Default weighting is 65% proximity and 35% freshness. Old sources still expire normally. Priority changes which markers survive the cap; it adds no reveal delay. Off restores newest-first."})
priority:AddLabel({Title="Shared limits",Description="Radar and ordinary pins use the same selected sources. The rear-step warning keeps its reserved slot. Optional LAND/LADDER sounds share the remaining movement-source budget."})

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
session:AddLabel({Title="Enemy health / armor",Description="Not available through the current Matcha bindings. Enemy rigs have no Humanoid or readable HP, and player armor cannot be safely linked to anonymous rig slots. No fake full-health bars or damage-subtraction estimates are shown."})
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

local function handleInput(input)
    local key=keyNumber(input and input.KeyCode)
    if key==menuKey then
        state.open=not state.open; if state.open then ui:Show() else ui:Hide() end
    elseif key==stopKey then
        config.enabled=false; state.open=false; hideAll(); ui:Hide()
        state.detailsHeld=false;state.detailsShown=false
    end
end
state.handleInput=handleInput
state.connections.input=Input.InputBegan:Connect(handleInput)
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
ui:Notify({Title="Nexus restarted",Content="Teammate steps now use recent paths and are filtered again before radar, world and rear cues. RightShift: menu.",Type="success",Duration=4})
print("kontra-nexus cleanly restarted. Floor-aware teammate-path filtering and stored-step revalidation enabled. Enemy HP/armor remains unavailable through current bindings; no guessed bars are displayed.")
