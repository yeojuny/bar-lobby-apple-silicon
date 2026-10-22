-- Private r39 official tank benchmark controller; never installed in ordinary profiles.
-- Accepted exact-frame startup: early pause acknowledgement, then one engine step at a time.
-- The selected game's official dbg_benchmark.lua owns the seeded synced workload.
-- Source: https://github.com/beyond-all-reason/Beyond-All-Reason/blob/433a460ac108c510374abdc9af5b44e3b9fe406f/luarules/gadgets/dbg_benchmark.lua
function widget:GetInfo()
  return {name='Metal4 r39 Official Benchmark Controller', author='private acceptance', layer=100000, enabled=true, handler=true}
end

local COMMAND='luarules benchmark armbull armbull 80 8 1400'
local STOP_COMMAND='luarules benchmark'
local FRAMES=900
local MAX_SAMPLES=30000
local started, lastPoll, lastHeartbeat, lastForceStart
local lastID, note='', 'starting'
local draws, ready, paused, ultraRequested, ultraVerified=0,false,false,false,false
local qualityRequestedAt, qualityAfterDraws, qualityError, qualityPending, startupFrame
local targetFrame,pauseRequestFrame=240,180
local commanderPrepared=false
local pauseRequestedAt,pauseAckFrame,lastObservedFrame,stepExpected,stepRequestedAt
local stepCount,stableUpdates=0,0
local settleDraws,settleAt
local qualification, qualStage, qualStart, qualDraws, qualLastDraw
local benchmark, resultWritten, finishAt
local uiFontCheck=false
local glSamples, glSamplesError
local expectedUltra={
  bloomdeferred=true, bloomdeferred_quality=3, ssao=true, ssao_quality=3,
  mapedgeextension=true, lighteffects=true, lighteffects_screenspaceshadows=4,
  lighteffects_nanoparticlelights=true, distortioneffects=true, snow=true,
  particles=40000, decalsgl4=true, decals=true, shadowslider=6, grass=true,
  losrange=true, attackrange_numrangesmult=1, cusgl4=true, water=2,
  advmapshading=true,
}

local function seconds(a,b) return Spring.DiffTimers(a,b) end
local function now() return Spring.GetTimer() end
local function config()
  return {MSAA=Spring.GetConfigInt('MSAA',-1), MSAALevel=Spring.GetConfigInt('MSAALevel',-1),
    MinSampleShadingRate=Spring.GetConfigFloat('MinSampleShadingRate',-1),
    VSync=Spring.GetConfigInt('VSync',-99), VSyncGame=Spring.GetConfigInt('VSyncGame',-99)}
end
local function gameSpeedSnapshot()
  local requested,actual,isPaused=Spring.GetGameSpeed()
  return {requested=requested,actual=actual,paused=isPaused==true}
end
local function mapEdgeState()
  local value=WG.options and WG.options.getOptionValue and WG.options.getOptionValue('mapedgeextension')
  local voidWater,voidGround
  if gl.GetMapRendering then
    local ok,v=pcall(gl.GetMapRendering,'voidWater');if ok then voidWater=v end
    ok,v=pcall(gl.GetMapRendering,'voidGround');if ok then voidGround=v end
  end
  local known=widgetHandler and widgetHandler.knownWidgets and widgetHandler.knownWidgets['Map Edge Extension']
  local order=widgetHandler and widgetHandler.orderList and widgetHandler.orderList['Map Edge Extension']
  local exception=Game.mapName=='Seths Ravine Remake 1.3.1'
    and (voidWater==true or voidGround==true) and (value==false or value==0.5)
    and (not known or known.active==false)
  return {wanted=true,actual=value,voidWater=voidWater,voidGround=voidGround,
    widgetActive=known and known.active or false,widgetOrder=order,exceptionApplied=exception}
end
local function optionSnapshot()
  local out={};if not WG.options or not WG.options.getOptionValue then return out end
  for key in pairs(expectedUltra) do out[key]=WG.options.getOptionValue(key) end
  for _,key in ipairs({'preset','vsync','limitoffscreenfps','limitidlefps','msaa','fogdiaglines','camera'}) do
    out[key]=WG.options.getOptionValue(key)
  end
  return out
end
local function qualityCheck()
  local c=config()
  if c.MSAA~=0 or c.MSAALevel~=0 then return false,'quality-error-required-aa-off' end
  if WG.options and WG.options.getOptionValue and (WG.options.getOptionValue('msaa')~=1 or WG.options.getOptionValue('fogdiaglines')~=0) then return false,'quality-error-defaults' end
  if Spring.GetCameraState().name~='spring' then return false,'quality-error-spring-camera' end
  if c.VSync~=0 or c.VSyncGame~=0 then return false,'quality-error-required-vsync0' end
  if not WG.options or not WG.options.getOptionValue then return false,'quality-error-options-api' end
  if WG.options.getOptionValue('vsync')~=1 or WG.options.getOptionValue('limitoffscreenfps')~=false
    or WG.options.getOptionValue('limitidlefps')~=false then return false,'quality-error-benchmark-options' end
  local edge=mapEdgeState()
  for key,want in pairs(expectedUltra) do
    if WG.options.getOptionValue(key)~=want and not (key=='mapedgeextension' and edge.exceptionApplied) then
      return false,'quality-error-ultra-'..key
    end
  end
  if not WG.ssao or WG.ssao.getPreset()~=3 or not WG.bloomdeferred or WG.bloomdeferred.getPreset()~=3 then
    return false,'quality-error-active-ultra-effects'
  end
  -- DrawScreen may be bound to a resolved UI target, so GL_SAMPLES is recorded
  -- as scoped evidence and is not treated as the main game's sample count.
  return true
end
local function qualityStep()
  if ultraVerified or qualityError then return end
  if not WG.options or not WG.options.applyOptionValue or not WG.options.getOptionValue then return end
  if not ultraRequested then
    -- Official Options initializes the API before populating the preset list in DrawScreen.
    if WG.options.getOptionValue('preset')==nil then return end
    WG.options.applyOptionValue('preset',5)
    WG.options.applyOptionValue('msaa',1)
    WG.options.applyOptionValue('fogdiaglines',0)
    WG.options.applyOptionValue('camera',3)
    -- The published applyOptionValue wrapper calls tonumber(value), so bool false
    -- must go through the official Options chat action rather than that wrapper.
    -- Limit idle FPS disabled through the private widget-order preferences before init.
    -- LimitIdleFps is set to zero in the private engine configuration.
    WG.options.applyOptionValue('vsync',1)
    ultraRequested=true;qualityRequestedAt=now();qualityAfterDraws=draws+3
    return
  end
  if draws<qualityAfterDraws or seconds(now(),qualityRequestedAt)<1 then return end
  local ok,why=qualityCheck()
  if ok then ultraVerified=true;qualityPending=nil
  else qualityPending=why;if seconds(now(),qualityRequestedAt)>8 then qualityError=why end end
end

local function jsonString(s)
  s=tostring(s or '')
  return '"'..s:gsub('[%z\1-\31\\"]',function(c)
    if c=='\\' then return '\\\\' elseif c=='"' then return '\\"' end
    return string.format('\\u%04x',string.byte(c))
  end)..'"'
end
local function json(v)
  local t=type(v)
  if t=='nil' then return 'null' end
  if t=='boolean' then return v and 'true' or 'false' end
  if t=='number' then return (v==v and v~=math.huge and v~=-math.huge) and string.format('%.12g',v) or 'null' end
  if t=='string' then return jsonString(v) end
  if t~='table' then return jsonString(tostring(v)) end
  local isArray=true;local count=0;local max=0
  for k in pairs(v) do count=count+1;if type(k)~='number' or k<1 or k%1~=0 then isArray=false else max=math.max(max,k) end end
  if isArray and max==count then
    local out={};for i=1,count do out[i]=json(v[i]) end
    return '['..table.concat(out,',')..']'
  end
  local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
  local out={};for _,k in ipairs(keys) do out[#out+1]=jsonString(k)..':'..json(v[k]) end
  return '{'..table.concat(out,',')..'}'
end
local function writeResult(data)
  if resultWritten then return end
  local f=io.open('LuaUI/Config/v104-performance-result.json','w')
  if not f then qualityError='result-write-failed';return end
  f:write(json(data),'\n');f:close();resultWritten=true
end
local function cameraSnapshot()
  local c=Spring.GetCameraState() or {};local out={}
  for k,v in pairs(c) do if type(k)=='string' and (type(v)=='number' or type(v)=='string') then out[k]=v end end
  return out
end
local function status()
  local f=io.open('LuaUI/Config/v104-performance-status.txt','w');if not f then return end
  local w,h=Spring.GetViewGeometry()
  f:write('id=',lastID,'\nnote=',note,'\nframe=',Spring.GetGameFrame(),'\ndraws=',draws,
    '\nfps=',string.format('%.6g',Spring.GetFPS()),'\nwidth=',w,'\nheight=',h,
    '\nmap=',tostring(Game.mapName),'\nultra=',ultraVerified and 'verified' or 'pending',
    '\nqualification=',qualStage or 'pending','\nresult=',resultWritten and 'written' or 'pending',
    '\nqualityError=',qualityError or 'none','\nqualityPending=',qualityPending or 'none','\n')
  f:write('fixture.contract=metal4-exact-frame240-v1\nfixture.expectedFrame=',targetFrame,
    '\nfixture.pauseRequestFrame=',pauseRequestFrame,'\nfixture.pauseAckFrame=',pauseAckFrame or -1,
    '\nfixture.stepCount=',stepCount,'\nfixture.actualPaused=',tostring(select(3,Spring.GetGameSpeed())==true),
    '\nfixture.readyFrame=',startupFrame or -1,'\n')
  local c=config();for k,v in pairs(c) do f:write('config.',k,'=',tostring(v),'\n') end
  f:write('glSamples=',tostring(glSamples or 'unavailable'),'\nglSamplesError=',tostring(glSamplesError or 'none'),'\n')
  local edge=mapEdgeState()
  for k,v in pairs(edge) do f:write('mapEdge.',k,'=',tostring(v),'\n') end
  if benchmark then f:write('benchmarkStart=',benchmark.startFrame,'\nbenchmarkTarget=',benchmark.targetFrame,'\n') end
  f:close()
end
local function sortedStats(values)
  local n=#values;if n<1 then return {count=0} end
  local a={};local sum,slow33,slow50,slow100=0,0,0,0
  for i=1,n do local v=values[i];a[i]=v;sum=sum+v
    if v>33 then slow33=slow33+1 end;if v>50 then slow50=slow50+1 end;if v>100 then slow100=slow100+1 end
  end
  table.sort(a)
  local function pct(p) return a[math.max(1,math.ceil(n*p))] end
  return {count=n,meanMs=sum/n,meanFPS=1000*n/sum,p50Ms=pct(.5),p95Ms=pct(.95),p99Ms=pct(.99),
    over33Ms=slow33,over50Ms=slow50,over100Ms=slow100}
end
local function beginQualification()
  qualification={stages={}};qualStage='off-before';qualStart=now();qualDraws=draws;qualLastDraw=nil
  note='qualification-off-before'
end
local function nextQualification()
  local t=now();local elapsed=seconds(t,qualStart)
  local stage={stage=qualStage,seconds=elapsed,draws=draws-qualDraws,fps=(draws-qualDraws)/elapsed}
  if qualStage=='on' then stage.frameIntervals=sortedStats(qualification.onSamples or {});qualification.onSamples=nil end
  qualification.stages[#qualification.stages+1]=stage
  if qualStage=='off-before' then qualStage='on'
  elseif qualStage=='on' then qualStage='off-after'
  else
    qualStage='complete'
    local before,enabled,after=qualification.stages[1].fps,qualification.stages[2].fps,qualification.stages[3].fps
    qualification.pass=enabled>3 and enabled>=0.5*math.min(before,after)
    if not qualification.pass then qualityError='qualification-sampler-overhead' end
    if qualityError then note=qualityError else ready=true;note='fixed-scene-paused' end
    return
  end
  qualStart=t;qualDraws=draws;qualLastDraw=nil;note='qualification-'..qualStage
end
-- Read only already-maintained special timers at two boundaries; do not enable
-- the engine profiler, request frame arrays, or add per-frame timing hooks.
local function existingProfilerSnapshot()
  local t=now();local rows={};local names=Spring.GetProfilerRecordNames()
  local count=math.min(#names,512)
  for i=1,count do
    local total=Spring.GetProfilerTimeRecord(names[i],false)
    if type(total)=='number' then rows[names[i]]=total end
  end
  return {totalMilliseconds=rows,namesAvailable=#names,namesRead=count,readCostMs=seconds(now(),t)*1000,
    scope='existing inclusive engine special-timer wall time; nested entries overlap; GPU/fence waits may be included'}
end
local function finishBenchmark()
  if not benchmark or benchmark.stopped then return end
  benchmark.profilerFinish=existingProfilerSnapshot()
  benchmark.stopped=true;benchmark.endFrame=Spring.GetGameFrame();benchmark.endTimer=now()
  benchmark.gameSpeedEnd=gameSpeedSnapshot()
  Spring.SendCommands(STOP_COMMAND) -- Official gadget toggles off and prints its independent native report.
  finishAt=now();note='benchmark-stopping'
end
local function finalResult(reason)
  local w,h=Spring.GetViewGeometry();local c=config()
  local b=benchmark or {}
  writeResult({schema=1,status=reason or 'complete',requestId=b.requestId or lastID,
    officialSource='https://github.com/beyond-all-reason/Beyond-All-Reason/blob/433a460ac108c510374abdc9af5b44e3b9fe406f/luarules/gadgets/dbg_benchmark.lua',
    officialCommand=COMMAND,seed=7654321,frameTarget=FRAMES,
    workload={unitTypeOwn='armbull',unitTypeOpponent='armbull',populationThresholdPerTeam=80,
      replenishBatchPerTeam=8,replenishEverySimulationFrames=3,placementSpan=1400,
      rampIncluded=true,populationThresholdIsNotHardCap=true,requestedSimulationSpeed=1},
    fixture={contract='metal4-exact-frame240-v1',expectedFrame=targetFrame,
      pauseRequestFrame=pauseRequestFrame,pauseAckFrame=pauseAckFrame,stepCount=stepCount,
      readyFrame=startupFrame},
    map=Game.mapName,game=Game.gameName,gameVersion=Game.gameVersion,
    engineVersion=Engine and Engine.versionFull or nil,
    resolution={width=w,height=h},camera=b.camera or cameraSnapshot(),
    quality={ultraPreset=5,ultraVerified=ultraVerified,optionsVerified=20,config=c,
      optionValues=optionSnapshot(),mapEdge=mapEdgeState(),pendingReason=qualityPending,
      glSamples=glSamples,glSamplesScope='DrawScreen current framebuffer; resolved UI targets may report 0 or 1',
      glSamplesConfirmed4=glSamples==4,glSamplesError=glSamplesError},
    qualification=qualification,
    benchmark={startFrame=b.startFrame,endFrame=b.endFrame,
      simulationFrames=(b.endFrame and b.startFrame) and b.endFrame-b.startFrame or nil,
      wallSeconds=(b.endTimer and b.activeTimer) and seconds(b.endTimer,b.activeTimer) or nil,
      drawIntervals=sortedStats(b.samples or {}),unitCounts=b.unitCounts or {},
      gameSpeed={requested=1,atRequest=b.gameSpeedAtRequest,start=b.gameSpeedStart,finish=b.gameSpeedEnd},
      existingProfiler={start=b.profilerStart,finish=b.profilerFinish},
      nativeReport='independent infolog benchmark output'},
    error=qualityError})
end
local function fail(why)
  if qualityError then return end
  qualityError=tostring(why);note=qualityError
  if benchmark and not benchmark.stopped then finishBenchmark() end
  finalResult('failed')
end
local function beginBenchmark(id)
  assert(ready and paused and select(3,Spring.GetGameSpeed())==true and ultraVerified
    and qualStage=='complete','fixed Ultra scene is not ready')
  assert(not benchmark,'benchmark already started')
  local gadget=VFS.LoadFile('luarules/gadgets/dbg_benchmark.lua',VFS.ZIP_ONLY)
  assert(gadget and #gadget==20856,'selected official benchmark gadget bytes differ from audited archive')
  assert(UnitDefNames.armbull,'official armbull definition absent')
  assert(Game.mapName and Game.mapName:lower():find('seths ravine remake',1,true),'wrong benchmark map')
  local ok,why=qualityCheck();assert(ok,why)
  local frame=Spring.GetGameFrame();assert(frame==240,'fixed startup frame changed')
  benchmark={requestId=id,startFrame=frame,targetFrame=frame+FRAMES,startTimer=now(),camera=cameraSnapshot(),samples={},unitCounts={}}
  lastID=id;ready=false;note='benchmark-starting'
  -- Require the fixture's existing requested speed1 while acknowledged paused.
  -- Actual speed may fall below it under load and is recorded independently.
  benchmark.gameSpeedAtRequest=gameSpeedSnapshot()
  Spring.SendCommands(COMMAND)
  -- Official unsynced gadget centers the camera over the map with a 0.75s transition.
  -- Its seeded workload is armed while paused, then advances exactly 900 sim frames.
  benchmark.unpauseAt=now();benchmark.lastUnitAt=now()
end
local function execute(id,action)
  if action=='capture' then assert(resultWritten and benchmark and benchmark.stopped,'capture-before-measurement');lastID=id;note='capture-requested';status();Spring.SendCommands('screenshot png');return end
  if action=='uicheck' then assert(resultWritten and benchmark.stopped,'UI check before measurement');assert(WG.ssao and WG.ssao.getPreset and WG.ssao.setPreset,'SSAO API missing');local preset=WG.ssao.getPreset();assert(preset==3,'SSAO preset drift');WG.ssao.setPreset(preset);uiFontCheck=true;lastID=id;note='ui-check-requested';status();return end
  if action=='status' then lastID=id;status();return end
  if action=='quit' then lastID=id;note='quit-requested';status();Spring.SendCommands('quitforce');return end
  if action=='benchmark' then beginBenchmark(id);status();return end
  error('unknown-action-'..tostring(action))
end

function widget:Initialize() started=now();lastPoll=started;lastHeartbeat=started;lastForceStart=-10 end
function widget:DrawScreen()
  draws=draws+1
  if uiFontCheck then gl.Color(0,0,0,0.85);gl.Rect(16,390,1080,530);gl.Color(1,1,1,1);gl.Text('Font 16px: Latin 한글 中 😀',32,490,16,'o');gl.Text('Font 33px: Latin 한글 中 😀',32,440,33,'o') end
  if Spring.GetGameFrame()>=240 and not glSamples and not glSamplesError and type(gl.GetNumber)=='function' then
    local ok,value=pcall(gl.GetNumber,0x80A9) -- GL_SAMPLES for the current draw framebuffer.
    if ok and type(value)=='number' then glSamples=value else glSamplesError=tostring(value) end
  elseif type(gl.GetNumber)~='function' then glSamplesError='gl.GetNumber-unavailable' end
  local t=Spring.GetTimerMicros()
  if qualStage=='on' then
    if qualLastDraw then
      local a=qualification.onSamples or {};qualification.onSamples=a
      if #a<1500 then a[#a+1]=Spring.DiffTimers(t,qualLastDraw,true,true) end
    end
    qualLastDraw=t
  end
  if benchmark and benchmark.unpaused and not benchmark.stopped then
    if benchmark.lastDraw then
      local a=benchmark.samples
      if #a>=MAX_SAMPLES then fail('sample-limit-exceeded')
      else a[#a+1]=Spring.DiffTimers(t,benchmark.lastDraw,true,true) end
    end
    benchmark.lastDraw=t
  end
end
local function gameFrame(frame)
  if qualityError then return end
  if frame==30 then Spring.SendCommands('cheat 1') end
  if frame==60 and not commanderPrepared then
    -- A stable owned commander prevents early game-over before the official workload.
    local def=UnitDefNames.armcom
    assert(def,'armcom-definition-absent')
    local x,z=Game.mapSizeX*0.35,Game.mapSizeZ*0.35
    local y=Spring.GetGroundHeight(x,z)
    Spring.SendCommands(string.format('give armcom 0 @%.0f,%.0f,%.0f',x,y,z))
    commanderPrepared=true
  end
  if not benchmark then
    if frame==pauseRequestFrame and commanderPrepared and not pauseRequestedAt then
      pauseRequestedAt=now();lastObservedFrame=frame
      Spring.SendCommands('pause 1')
    end
    assert(frame<=targetFrame,'Exact frame240 overshoot')
  elseif not benchmark.stopped then
    if benchmark.unpaused and frame>benchmark.startFrame and not benchmark.gameSpeedStart then
      benchmark.gameSpeedStart=gameSpeedSnapshot()
    end
    if frame>=benchmark.targetFrame then finishBenchmark() end
  end
end
-- A pause request is not proof gs->paused has changed. Wait for ACK, then
-- send exactly one ordinary engine step and await its exact +1 frame ACK.
local function freezeStep()
  if benchmark or not pauseRequestedAt then return end
  local t=now()
  local frame=Spring.GetGameFrame()
  local actualPaused=select(3,Spring.GetGameSpeed())==true
  assert(frame>=lastObservedFrame,'Exact frame moved backward')
  assert(frame<=targetFrame,'Exact frame240 overshoot')
  lastObservedFrame=frame
  if paused then
    assert(actualPaused and frame==targetFrame,'Acknowledged exact frame240 changed')
    return
  end
  if not pauseAckFrame then
    assert(seconds(t,pauseRequestedAt)<=10,'Pause acknowledgment timeout')
    if not actualPaused then return end
    pauseAckFrame=frame
  else
    assert(actualPaused,'Unexpected unpause during exact-frame preparation')
  end
  if stepExpected then
    assert(frame==stepExpected or frame==stepExpected-1,'Single-step advanced other than exactly one frame')
    if frame~=stepExpected then
      assert(seconds(t,stepRequestedAt)<=5,'Single-step acknowledgment timeout')
      return
    end
    stepExpected=nil;stepRequestedAt=nil;stepCount=stepCount+1
  end
  if frame<targetFrame then
    assert(stepCount<targetFrame-pauseRequestFrame,'Single-step count exceeded exact-frame bound')
    stepExpected=frame+1;stepRequestedAt=t
    Spring.SendCommands('singlestep')
    return
  end
  if not settleDraws then
    Spring.SelectUnitArray({},false)
    Spring.SendCommands('viewspring')
    local x,z=Game.mapSizeX/2,Game.mapSizeZ/2
    Spring.SetCameraState({px=x,py=math.max(0,Spring.GetGroundHeight(x,z)),pz=z,dist=2400,rx=2.75,ry=0,rz=0,name="spring",mode=2},0)
    settleDraws=draws;settleAt=t;stableUpdates=1
    return
  end
  stableUpdates=stableUpdates+1
  if stableUpdates>=3 and draws>=settleDraws+2 and seconds(t,settleAt)>=0.1 and ultraVerified then
    paused=true;startupFrame=frame;note='fixed-scene-quality-pending'
  end
end
function widget:GameFrame(frame)
  local ok,err=pcall(gameFrame,frame)
  if not ok then fail('quality-error-fixture-'..tostring(err)) end
end
function widget:Update()
  local t=now();local elapsed=seconds(t,started)
  if elapsed>300 then
    if not resultWritten then qualityError=qualityError or 'timeout-300s';finalResult('timeout') end
    status();Spring.SendCommands('quitforce');return
  end
  if Spring.GetGameFrame()<=0 and elapsed-lastForceStart>=5 then
    lastForceStart=elapsed;Spring.SendCommands('forcestart')
  end
  qualityStep()
  if not qualityError then
    local ok,err=pcall(freezeStep)
    if not ok then fail('quality-error-fixture-'..tostring(err)) end
  end
  if qualityError and not resultWritten then finalResult('failed') end
  if paused and ultraVerified and select(3,Spring.GetGameSpeed())==true and not qualStage and not qualityError then
    beginQualification()
  end
  if qualStage and qualStage~='complete' and seconds(t,qualStart)>=3 then nextQualification() end
  if benchmark and not benchmark.stopped then
    if seconds(t,benchmark.unpauseAt)>=1 and not benchmark.unpaused then
      local speed=gameSpeedSnapshot()
      if not speed.paused or Spring.GetGameFrame()~=targetFrame then
        fail('quality-error-benchmark-paused-frame-changed')
      elseif speed.requested~=1 then
        if seconds(t,benchmark.unpauseAt)>5 then fail('quality-error-speed1-ack-timeout') end
      else
        benchmark.profilerStart=existingProfilerSnapshot()
        benchmark.unpaused=true;benchmark.activeTimer=t;benchmark.lastDraw=nil;benchmark.camera=cameraSnapshot()
        Spring.SendCommands('pause 0');note='benchmark-running'
      end
    end
    if seconds(t,benchmark.lastUnitAt)>=1 then
      benchmark.lastUnitAt=t
      local u=Spring.GetAllUnits()
      benchmark.unitCounts[#benchmark.unitCounts+1]={second=seconds(t,benchmark.startTimer),frame=Spring.GetGameFrame(),count=#u,gameSpeed=gameSpeedSnapshot()}
    end
    if Spring.GetGameFrame()>=benchmark.targetFrame then finishBenchmark() end
  elseif benchmark and benchmark.stopped and finishAt and not resultWritten and seconds(t,finishAt)>=1 then
    finalResult('complete');note='benchmark-complete'
  end
  if seconds(t,lastPoll)>=0.2 then
    lastPoll=t
    local f=io.open('LuaUI/Config/v104-performance-request.txt','r')
    if f then
      local line=f:read(1024);f:close()
      if line and #line<1024 then
        local id,action=line:match('^([%w%-]+)|([%w%-]+)|')
        if id and id~=lastID then
          local ok,err=pcall(execute,id,action)
          if not ok then lastID=id;fail('command-failed-'..tostring(err)) end
        end
      end
    end
  end
  if seconds(t,lastHeartbeat)>=1 then
    lastHeartbeat=t
    if benchmark and not benchmark.stopped then local ok,why=qualityCheck();if not ok then fail(why) end end
    status()
  end
end
