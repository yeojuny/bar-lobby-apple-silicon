import {hasAcknowledgedMeasuredQuit} from "file:///Users/yeojun/Desktop/BAR-AppleSilicon-App/tools/lib/r92-measurement-ack-boundary.mjs";
// Three selected runtimes, one previously qualified Seths benchmark each.
// Derived from Run95: preserve hidden launch, isolated clones/cache, pins and cleanup.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn,execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import net from 'node:net';
import {createRequire} from 'node:module';
const require=createRequire("file:///Users/yeojun/Desktop/BAR-AppleSilicon-App/tools/run-metal4-r42-seths-lowpower-hidden-trial.mjs"),gate=require('./lib/run94-current-content-gate.cjs');
const gameExitEvent=(rows,pid)=>rows.find(e=>e.event==='owned-engine-exit'&&e.childPid===pid);
import {cacheInventory,stageShaderCache} from 'file:///Users/yeojun/Desktop/BAR-AppleSilicon-App/tools/lib/run94-mvk-acceptance-cache.mjs';
import {cleanupPrivateTrialCaches} from 'file:///Users/yeojun/Desktop/BAR-AppleSilicon-App/tools/lib/run94-private-trial-cache-cleanup.mjs';
const here=path.dirname(fileURLToPath("file:///Users/yeojun/Desktop/BAR-AppleSilicon-App/tools/run-metal4-r42-seths-lowpower-hidden-trial.mjs")),root=path.dirname(here);
const fixture='/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/validation/v104-three-candidate-performance-20261020/4-C-metal3';
const [planPath,grantPath]=process.argv.slice(2);
if(process.argv.length!==4||!path.isAbsolute(planPath||'')||!path.isAbsolute(grantPath||'')||path.dirname(planPath)!==fixture||path.dirname(grantPath)!==fixture)throw Error('Exact private plan and grant required');
const hashInput=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const plan=JSON.parse(fs.readFileSync(planPath)),grant=JSON.parse(fs.readFileSync(grantPath)),planSHA=hashInput(planPath);
const lane='lobby',mode=grant.cacheMode,role=plan.benchmarkRole,strictHidden=true;
if(plan.schema!=='v104-three-candidate-4-C-metal3-v1'||grant.schema!=='v104-three-candidate-4-C-metal3-v1-grant'||!grant.authorized||grant.planSha256!==planSHA||grant.strictHiddenOnly!==true||grant.visibleFallbackAllowed!==false||grant.maximumGameSessions!==1||!['parent','r41','r42'].includes(role)||mode!=='single'||grant.lane!=='lobby'||!Number.isFinite(Date.parse(grant.expiresAt))||Date.parse(grant.expiresAt)<=Date.now()||Date.parse(grant.expiresAt)>Date.now()+3600000)throw Error('Exact unexpired benchmark grant required');
if(typeof plan.nativeMetal4!=='boolean'||plan.benchmark?.command!=='luarules benchmark armbull armbull 80 8 1400'||plan.benchmark?.frames!==900)throw Error('Exact backend and qualified bounded workload required');
if(JSON.stringify(plan.sequence)!==JSON.stringify(['lobby:single'])||plan.sequence[grant.sessionOrdinal-1]!==lane+':'+mode)throw Error('Exact single-session role required');
const selectedLane=plan.lanes.lobby;plan.engine=selectedLane.engine;plan.engineVersion=selectedLane.engine.version;
plan.hiddenWindowGuard=selectedLane.guard;
const qualification=plan.hiddenQualification;
if(!qualification?.preflight||hashInput(qualification.preflight.path)!==qualification.preflight.sha256||qualification.guardSha256!==plan.hiddenWindowGuard.sha256||qualification.sdlSha256!==plan.sdlSha256)throw Error('Current hidden preflight identity drift');
const preflight=JSON.parse(fs.readFileSync(qualification.preflight.path));
if(preflight.status!=='actual-sdl-dummy-hidden-fullscreen-contract-passed'||preflight.guardSha256!==qualification.guardSha256||preflight.sdlLibrarySha256!==qualification.sdlSha256)throw Error('Current SDL hidden preflight failed');
// Retired old full-game receipt is not claimed as current qualification.
// Actual current native hidden creation and draw progression remain mandatory before measurement.
const app=plan.app.app,executable=path.join(app,'Contents/MacOS/BAR');
const validationRoot=path.join(fixture,'sessions');fs.mkdirSync(validationRoot,{recursive:true});
const previous=[];for(const n of fs.readdirSync(validationRoot)){const f=path.join(validationRoot,n,'execution-receipt.json');if(fs.existsSync(f)){const r=JSON.parse(fs.readFileSync(f));if(r.planSha256===planSHA)previous.push({...r,receiptFile:f});}}
if(previous.length!==grant.sessionOrdinal-1||previous.some(r=>r.status!=='completed-not-promoted'||!r.protectedInputsUnchanged||r.remainingOwnedProcesses?.length)||new Set(previous.map(r=>r.sessionOrdinal)).size!==previous.length)throw Error('Previous bounded benchmark session incomplete or failed');
fs.writeFileSync(grantPath+'.consumed.json',JSON.stringify({planSHA,lane,mode,sessionOrdinal:grant.sessionOrdinal,at:new Date().toISOString()})+'\n',{flag:'wx'});
const run=path.join(validationRoot,'lobby-no-native-hook-'+Date.now());fs.mkdirSync(run,{mode:0o700});
const state=path.join(run,'state'),data=path.join(state,'data'),assets=path.join(run,'assets'),events=path.join(run,'events.jsonl');
fs.writeFileSync(events,'',{flag:'wx'});
const nodePort=19971,rendererPort=19973;
const config={app,state,assets,events,windowBorderless:0,allowNativeWindow:false,
 strictHiddenWindow:true,guardLibrary:plan.hiddenWindowGuard.path,guardSha256:plan.hiddenWindowGuard.sha256,
 presentationOverrides:[],privateFixtureFiles:[],map:plan.map,menu:plan.menu,nativeMetal4:plan.nativeMetal4,disableAsyncWait:plan.disableAsyncWait};
const owned=new Set(),ownedIdentity=new Map();let launcher,watcher,stopGuard=false,failure=null;
const deadline=Date.now()+400000;
let gamePid,measuredQuitRequestID=null;let launchAt,gameSpawnAt,readyAt,benchmarkStartAt,benchmarkFinishAt;
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const record=value=>{fs.appendFileSync(events,JSON.stringify({at:Date.now(),...value})+'\n');console.log(JSON.stringify(value));};
const receipt={role,benchmarkRole:role,app,run,mesaGitSha1:plan.mesaGitSha1,strictHiddenWindow:true,
 promotionAllowed:false,nativeMetal4Requested:plan.nativeMetal4,powerContract:{source:plan.power.source,lowPowerMode:plan.power.lowPowerMode,thermalStateRecorded:true,periodicIntervalMs:15000,settingsChanged:false},powerObservations:[],lane,cacheMode:mode,maximumTotalAttempts:1,sessionOrdinal:grant.sessionOrdinal,planSha256:grant.planSha256,startedAt:new Date().toISOString()};
let lastPowerCheck=0;
function checkPower(label){
 const sample={label,atUTC:new Date().toISOString(),passed:false};
 try{
  sample.battery=execFileSync('/usr/bin/pmset',['-g','batt'],{encoding:'utf8',timeout:3000,maxBuffer:65536});
  const raw=execFileSync('/usr/bin/osascript',['-l','JavaScript','-e',
   'ObjC.import("Foundation");const p=$.NSProcessInfo.processInfo;JSON.stringify({isLowPowerModeEnabled:Boolean(p.isLowPowerModeEnabled),thermalState:Number(p.thermalState)});'],{encoding:'utf8',timeout:3000,maxBuffer:65536});
  const value=JSON.parse(raw);Object.assign(sample,value);
  sample.passed=sample.battery.includes("'"+plan.power.source+"'")&&value.isLowPowerModeEnabled===plan.power.lowPowerMode;
  if(!sample.passed)throw Error('Recorded power source or Low Power Mode changed');
  sample.awakeAssertions=execFileSync('/usr/bin/pmset',['-g','assertions'],{encoding:'utf8',timeout:3000,maxBuffer:65536});
  sample.displayAwakeProtectionPassed=/PreventUserIdleDisplaySleep\s+[1-9]/.test(sample.awakeAssertions)&&sample.awakeAssertions.includes('(caffeinate)');
  if(!sample.displayAwakeProtectionPassed)throw Error('Temporary display-awake assertion disappeared');
 }catch(error){sample.error=String(error);throw error;}
 finally{sample.finishedAtUTC=new Date().toISOString();receipt.powerObservations.push(sample);lastPowerCheck=Date.now();record({event:'power-observation',...sample});}
}
function inventory(app){
 const rows={};function visit(dir,prefix=''){for(const name of fs.readdirSync(dir).sort()){const relative=prefix?prefix+'/'+name:name,file=path.join(dir,name),st=fs.lstatSync(file),mode=st.mode&0o777;
 if(st.isDirectory()){rows[relative]={type:'directory',mode};visit(file,relative);}else if(st.isSymbolicLink())rows[relative]={type:'link',mode,target:fs.readlinkSync(file)};else if(st.isFile())rows[relative]={type:'file',mode,size:st.size,sha256:hash(file)};else throw Error('Special app input');}}visit(app);return rows;
}
function checkPins(){
 if(hash(plan.scene.path)!==plan.scene.sha256||hash(plan.controller.path)!==plan.controller.sha256)throw Error('Scene/controller pin changed');
 if(hash(plan.appAsar.path)!==plan.appAsar.sha256||plan.appAsar.path!==path.join(app,'Contents/Resources/app.asar'))throw Error('Launcher asar pin changed');
 if(hash(plan.contentFiles.path)!==plan.contentFiles.sha256)throw Error('Content manifest pin changed');
 for(const [relative,pin]of Object.entries(plan.inputPins))if(hash(pin.path)!==pin.sha256)throw Error('Input changed: '+relative);
 if(digest(JSON.stringify(inventory(app)))!==plan.app.inventorySha256)throw Error('Selected app inventory changed');
 for(const pin of plan.protectedApps){if(digest(JSON.stringify(inventory(pin.app)))!==pin.inventorySha256)throw Error('Protected app changed: '+pin.app);}
 if(hash(plan.hiddenWindowGuard.path)!==plan.hiddenWindowGuard.sha256)throw Error('Hidden guard changed');
 if(plan.acceptanceBootstrap.path!=="/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/validation/v104-three-candidate-performance-20261020/metal-bootstrap.cjs"||plan.qualifiedAdapters.lobby.path!=="/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/validation/v104-three-candidate-performance-20261020/benchmark-bootstrap.cjs")throw Error('Exact derived runtime wrapper/base adapter required');
 for(const entry of [...(plan.executionFiles||[]),plan.hiddenQualification.preflight,plan.qualifiedAdapters.lobby,plan.acceptanceBootstrap,plan.authorization,plan.sourceAudit])if(hash(entry.path)!==entry.sha256)throw Error('Execution tool pin changed');
 for(const pin of plan.sharedRuntime)if(hash(pin.path)!==pin.sha256)throw Error('Shared runtime pin changed');
 const sdl=plan.sharedRuntime.find(p=>p.path.endsWith('/sdl3/lib/libSDL3.0.dylib'));
 if(!sdl||sdl.sha256!==plan.sdlSha256)throw Error('Selected packaged SDL differs from qualification');
}
function ps(){return execFileSync('/bin/ps',['-axo','pid=,command='],{encoding:'utf8'}).split('\n').map(line=>{const m=line.match(/^\s*(\d+)\s+(.+)$/);return m?{pid:Number(m[1]),command:m[2]}:null;}).filter(Boolean);}
function discover(){
 const all=ps();
 if(fs.existsSync(events))for(const line of fs.readFileSync(events,'utf8').trim().split('\n')){try{const e=JSON.parse(line);if(['owned-child','owned-version-check','owned-content-checksum'].includes(e.event)&&Number.isInteger(e.childPid)){
 const p=all.find(p=>p.pid===e.childPid);if(p&&(p.command.startsWith(executable+' ')||p.command.startsWith(app+'/Contents/Resources/bundled-assets/engine/')||(p.command.startsWith('./spring ')&&p.command.includes(data)&&e.enginePath===path.dirname(plan.engine.path)))){owned.add(p.pid);if(!ownedIdentity.has(p.pid))ownedIdentity.set(p.pid,p.command);}}}catch{}}
 return all.filter(p=>owned.has(p.pid)&&ownedIdentity.get(p.pid)===p.command);
}
async function rpcSocket(url){
  const ws=new WebSocket(url),pending=new Map();let sequence=0;const queued=[];const listeners=[];
  await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
  ws.onmessage=event=>{const m=JSON.parse(event.data);if(m.id){const p=pending.get(m.id);if(!p)return;pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(JSON.stringify(m.error))):p.resolve(m.result);}else{queued.push(m);for(const handler of [...listeners])handler();}};
  ws.onclose=()=>{for(const p of pending.values()){clearTimeout(p.timer);p.reject(Error('Owned inspector channel closed'));}pending.clear();};
  return {
    call(method,params={},timeout=60000){return new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>{pending.delete(id);reject(Error('Inspector timeout: '+method));},timeout);pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params}));});},
    event(method,timeout=15000){return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{const n=listeners.indexOf(check);if(n>=0)listeners.splice(n,1);reject(Error('No inspector event: '+method));},timeout);function check(){const i=queued.findIndex(x=>x.method===method);if(i<0)return;clearTimeout(timer);const n=listeners.indexOf(check);if(n>=0)listeners.splice(n,1);resolve(queued.splice(i,1)[0].params);}listeners.push(check);check();});},
    close(){ws.close();},
  };
}
async function targets(port,timeout=20000){const deadline=Date.now()+timeout;while(Date.now()<deadline){if(failure)throw failure;try {const r=await fetch(`http://127.0.0.1:${port}/json/list`,{signal:AbortSignal.timeout(1500)});const value=await r.json();if(value.length)return value;}catch{}await delay(150);}throw Error('Inspector did not open: '+port);}
async function attachBootstrap(port,expectedPid){
  const list=await targets(port);const target=list.find(t=>t.webSocketDebuggerUrl);if(!target)throw Error('No owned Node inspector');
  const rpc=await rpcSocket(target.webSocketDebuggerUrl);
  await rpc.call('Debugger.enable');await rpc.call('Runtime.runIfWaitingForDebugger');
  const paused=await rpc.event('Debugger.paused');
  const who=await rpc.call('Debugger.evaluateOnCallFrame',{callFrameId:paused.callFrames[0].callFrameId,expression:'({pid:process.pid,execPath:process.execPath})',returnByValue:true});
  if(who.result?.value?.pid!==expectedPid||who.result?.value?.execPath!==executable||!owned.has(expectedPid))throw Error('Foreign inspector refused');
  const expression=`(()=>{const c=${JSON.stringify(config)};const result=require(${JSON.stringify("/Users/yeojun/Desktop/BAR-AppleSilicon-App/artifacts/validation/v104-three-candidate-performance-20261020/metal-bootstrap.cjs")})(c);const cp=require("node:child_process"),fs=require("node:fs"),p=require("node:path"),s=cp.spawn;cp.spawn=function(command,args=[],options={}){if(p.basename(command)==="spring"&&!args.some(a=>a==="--version"||a==="--sync-version")){const e=options.env||process.env;const thread=e.GALLIUM_THREAD??null,debug=e.ZINK_DEBUG??null;if(thread!==null&&["0","false","no"].includes(String(thread).toLowerCase()))throw Error("Renderpass parser threading disabled");if(debug&&String(debug).split(",").some(t=>["rp","norp","msaaopt","rploads","rpstores"].includes(t.trim())))throw Error("Unexpected renderpass override");fs.appendFileSync(c.events,JSON.stringify({at:Date.now(),pid:process.pid,event:"renderpass-runtime-policy",galliumThread:thread,zinkDebug:debug,policy:"driver-default"})+"\\n");}return s.call(this,command,args,options);};require("node:module").syncBuiltinESMExports();return result;})()`;
  const result=await rpc.call('Debugger.evaluateOnCallFrame',{callFrameId:paused.callFrames[0].callFrameId,expression,returnByValue:true});
  if(result.exceptionDetails)throw Error('Bootstrap failed: '+JSON.stringify(result.exceptionDetails));
  record({event:'inspector-bootstrap',port,result:result.result?.value});
  await rpc.call('Debugger.resume');rpc.close();
}
async function renderer(expression,timeout=120000){
  const list=await targets(rendererPort,30000);const target=list.find(t=>t.type==='page'&&decodeURIComponent(t.url).startsWith('file://'+app+'/Contents/Resources/'));
  if(!target)throw Error('Candidate app renderer identity mismatch');
  const rpc=await rpcSocket(target.webSocketDebuggerUrl);
  try {const result=await rpc.call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true},timeout);if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result?.value;}finally{rpc.close();}
}
const observedLogSizes=new Map();
function guardFatalLog(){
 for(const name of ['infolog.txt','stack-game.stderr.log']){
  const filename=path.join(data,name);if(!fs.existsSync(filename))continue;
  const size=fs.statSync(filename).size,previous=observedLogSizes.get(filename)||0;
  if(size===previous)continue;
  const start=Math.max(0,(size<previous?0:previous)-512);
  if(size-start>262144)throw Error('Owned log grew beyond bounded read: '+name);
  const buffer=Buffer.alloc(size-start),fd=fs.openSync(filename,'r');let count;
  try{count=fs.readSync(fd,buffer,0,buffer.length,start);}finally{fs.closeSync(fd);}
  observedLogSizes.set(filename,start+count);
  const fatal=buffer.toString('utf8',0,count).split('\n').find(line=>/\[barwidgets\.lua\] Error:|Error in (?:widget|CallIn)|\b(?:SIGBUS|SIGSEGV|SIGILL|SIGABRT)\b|Experimental native Metal 4 encoding failed:|VK_ERROR_DEVICE_LOST/.test(line));
  if(fatal)throw Error('Owned engine/runtime failure: '+fatal.slice(0,500));
 }
}
let foregroundChecks=0;
function guardForeground(){
 if(fs.existsSync(plan.screenStopPath))throw Error('Whole-run screen guard stopped the benchmark');
 if(!strictHidden)return;
 const output=execFileSync('/usr/bin/osascript',['-l','JavaScript','-e',
  'ObjC.import("AppKit");const a=$.NSWorkspace.sharedWorkspace.frontmostApplication;const p=a.executableURL;JSON.stringify({pid:Number(a.processIdentifier),path:p?ObjC.unwrap(p.path):""});'],{encoding:'utf8',timeout:2000});
 const front=JSON.parse(output),pid=front.pid;if(!Number.isInteger(pid)||pid<1||typeof front.path!=='string')throw Error('Foreground monitor unavailable');
 foregroundChecks++;
 if(owned.has(pid)||front.path.startsWith(app+'/')){
  if(plan.allowOwnedLobbyForeground===true&&plan.historicalLobbyFullscreen===true&&pid===launcher?.pid&&ownedIdentity.get(pid)&&front.path===executable)return;
  throw Error('Owned non-Lobby capture process became foreground; stopping');
 }
}

function eventRows(){return fs.existsSync(events)?fs.readFileSync(events,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse):[];}
function status(){const f=path.join(data,'LuaUI/Config/v104-performance-status.txt');if(!fs.existsSync(f))return null;const s={unit:[]};for(const line of fs.readFileSync(f,'utf8').split('\n')){const i=line.indexOf('=');if(i<0)continue;const k=line.slice(0,i),v=line.slice(i+1);if(k==='unit')s.unit.push(v);else s[k]=v;}return s;}
async function until(predicate,timeout,label){const end=Date.now()+timeout;while(Date.now()<end){if(failure)throw failure;const result=predicate();if(result)return result;await delay(200);}throw Error('Timeout: '+label);}
async function request(action,timeout=15000){
 const id=crypto.randomUUID();fs.writeFileSync(path.join(data,'LuaUI/Config/v104-performance-request.txt'),id+'|'+action+'|\n');
 return until(()=>{
   const s=status();if(s?.id!==id)return null;
   if(s.note?.startsWith('command-failed'))throw Error(s.note);
   return s.note!=='settling'?s:null;
 },timeout,action);
}
let contentManifest;
async function stage(){
 for(const dir of ['config','data/LuaUI/Widgets','data/LuaUI/Include','data/LuaUI/Config','data/LuaMenu/Widgets','data/LuaMenu/Config'])fs.mkdirSync(path.join(state,dir),{recursive:true,mode:0o700});
 for(const name of ['maps','pool','packages','rapid'])fs.mkdirSync(path.join(assets,name),{recursive:true,mode:0o700});
 for(const [relative,pin]of Object.entries(plan.inputPins))if(relative.startsWith('state/'))fs.copyFileSync(pin.path,path.join(run,relative));
 const lobbyConfig=path.join(state,'config/settings.json');
 if(state!==path.join(run,'state')||fs.realpathSync(state)!==state||fs.realpathSync(lobbyConfig)!==lobbyConfig)throw Error('Non-private Lobby settings refused');
 const lobbyStat=fs.lstatSync(lobbyConfig);
 if(!lobbyStat.isFile()||lobbyStat.nlink!==1)throw Error('Shared Lobby settings refused');
 const lobbySettings=JSON.parse(fs.readFileSync(lobbyConfig,'utf8'));
 if(!lobbySettings||typeof lobbySettings!=='object'||Array.isArray(lobbySettings))throw Error('Invalid private Lobby settings');
 const lobbyFullscreenBefore=lobbySettings.fullscreen;
 lobbySettings.fullscreen=false;
 fs.writeFileSync(lobbyConfig,JSON.stringify(lobbySettings,null,2)+'\n');
 if(JSON.parse(fs.readFileSync(lobbyConfig,'utf8')).fullscreen!==false)throw Error('Private hidden Lobby fullscreen disabled');
 receipt.privateLobbyWindowSettings={fullscreenBefore:lobbyFullscreenBefore,fullscreenAfter:false,appliedBeforeAppLaunch:true,foregroundAllowed:false};
 const content=JSON.parse(fs.readFileSync(plan.contentFiles.path)),staged=[],cloneGroups=new Map(),renamedClones=[];
 for(const entry of content.files){
  gate.regular(entry.path);if(fs.statSync(entry.path).size!==entry.bytes||hash(entry.path)!==entry.sha256)throw Error('Current content source pin drift: '+entry.relative);
  const target=path.resolve(assets,entry.relative);if(!target.startsWith(assets+'/')||entry.relative.split('/').some(p=>p==='.'||p==='..'))throw Error('Unsafe staged content destination');
  const destination=path.dirname(target);fs.mkdirSync(destination,{recursive:true});
  if(fs.existsSync(target))throw Error('Private content destination already exists');
  // Node's forced reflink is ENOSYS on this host. Reuse the native APFS clone
  // route already used by the qualified Run94 visual/sensor hosts.
  if(path.basename(entry.path)!==path.basename(target))renamedClones.push([entry.path,target]);
  else{if(!cloneGroups.has(destination))cloneGroups.set(destination,[]);cloneGroups.get(destination).push(entry.path);}
  const {path:source,...pin}=entry;staged.push(pin);
 }
 for(const [destination,sources]of cloneGroups)for(let i=0;i<sources.length;i+=100)execFileSync('/bin/cp',['-c','-P',...sources.slice(i,i+100),destination],{timeout:30000,stdio:'pipe'});
 for(const [source,target]of renamedClones)execFileSync('/bin/cp',['-c','-P',source,target],{timeout:30000,stdio:'pipe'});
 contentManifest={schema:'run94-current-content-pins-v1',files:staged.filter(p=>!p.relative.startsWith('rapid/')),tags:content.tags,selectedSdps:content.selectedSdps,menuAlias:content.menuAlias,baseBytes:content.baseBytes,baseFiles:content.baseFiles,maxBytes:content.maxBytes,maxFiles:content.maxFiles};
 const manifestPath=path.join(run,'content-pins.json');fs.writeFileSync(manifestPath,JSON.stringify(contentManifest));
 record({event:'staged-current-official-content-checkpoint',...gate.verify(assets,contentManifest,{phase:'staged-official'})});
 Object.assign(config,{scenario:'stack-benchmark',engineSha256:plan.engine.sha256,engineVersion:plan.engineVersion,appAsarSha256:plan.appAsar.sha256,game:plan.game,startScriptSha256:plan.scene.sha256,contentManifest:manifestPath,contentManifestSha256:hash(manifestPath),contentGateSha256:hash(path.join(here,'lib/run94-current-content-gate.cjs'))});
 fs.copyFileSync(plan.controller.path,path.join(data,'LuaUI/Widgets/gui_run95_stack_benchmark.lua'));
 config.privateBenchmarkFiles=[{relative:'LuaUI/Widgets/gui_run95_stack_benchmark.lua',sha256:plan.controller.sha256}];
 Object.assign(config,{stackLane:lane,stackCacheMode:mode,stackQualifiedAdapterSha256:plan.qualifiedAdapters.lobby.sha256,sharedRuntimePins:plan.sharedRuntime});
 receipt.cache={directory:path.join(data,'cache',plan.nativeMetal4?'metal4':'metal3','mesa_shader_cache'),...stageShaderCache({mode:'cold',destination:path.join(data,'cache',plan.nativeMetal4?'metal4':'metal3','mesa_shader_cache')})};
 const cfg=path.join(data,'springsettings.cfg'),overrides={AdvMapShading:1,Fullscreen:1,WindowBorderless:0,XResolution:1512,YResolution:950,XResolutionWindowed:1512,YResolutionWindowed:982,WindowPosX:0,WindowPosY:0,Sound:0,BARGraphicsTraceOnce:0,BARGraphicsCaptureOnce:0,BARGraphicsObserverOnce:0,MSAA:0,MSAALevel:-1,VSync:0,VSyncGame:0,LimitIdleFps:0};
 fs.writeFileSync(cfg,fs.readFileSync(cfg,'utf8').split('\n').filter(l=>!Object.keys(overrides).some(k=>new RegExp('^\\s*'+k+'\\s*=').test(l))).join('\n')+'\n'+Object.entries(overrides).map(([k,v])=>k+' = '+v).join('\n')+'\n');
}
function requireBenchmarkResult(value,requestId){
 if(value?.schema!==1||value.status!=='complete'||value.error||value.requestId!==requestId||value.frameTarget!==900||value.officialCommand!==plan.benchmark.command||value.map!==plan.map||value.quality?.ultraVerified!==true||value.quality?.config?.MSAA!==0||value.quality?.config?.MSAALevel!==0||value.quality?.config?.VSync!==0||value.quality?.config?.VSyncGame!==0||value.qualification?.pass!==true||value.benchmark?.simulationFrames!==900||value.benchmark?.startFrame!==240||value.benchmark?.endFrame!==1140||!(value.benchmark?.drawIntervals?.count>0))throw Error('Official benchmark result identity/quality/frames differ');
 if(value.resolution?.width!==plan.expectedDrawable.width||value.resolution?.height!==plan.expectedDrawable.height)throw Error('Actual benchmark drawable changed');
 if(value.camera?.name!=='spring'||value.camera?.mode!==2)throw Error('Actual Spring camera missing');
}

try{
 checkPower('preflight');
 for(const port of [nodePort,rendererPort])await new Promise((resolve,reject)=>{const server=net.createServer();server.once('error',()=>reject(Error('Owned inspector port occupied')));server.listen(port,'127.0.0.1',()=>server.close(resolve));});
 checkPins();execFileSync('/usr/bin/codesign',['--verify','--deep','--strict',app],{timeout:30000,stdio:'pipe'});
 if(ps().some(p=>/\/(BAR|spring)(?:\s|$)/.test(p.command)))throw Error('Existing BAR process; leaving it untouched');
 guardForeground();
 const preparationStarted=Date.now();await stage();receipt.preparationMs=Date.now()-preparationStarted;
 const out=fs.openSync(path.join(run,'launcher.stdout.log'),'wx'),err=fs.openSync(path.join(run,'launcher.stderr.log'),'wx');
 const env={...process.env,BAR_STATE_PATH:state,BAR_ASSETS_PATH:assets,ALSOFT_DRIVERS:'null',BAR_METAL_BACKEND:plan.nativeMetal4?'METAL4':'METAL3'};delete env.DYLD_INSERT_LIBRARIES;delete env.SDL_MAC_BACKGROUND_APP;
 checkPower('before-launch');
 launchAt=Date.now();launcher=spawn(executable,[`--inspect-brk=127.0.0.1:${nodePort}`,`--remote-debugging-port=${rendererPort}`,'--remote-debugging-address=127.0.0.1','--use-mock-keychain'],{cwd:run,stdio:['ignore',out,err],env});fs.closeSync(out);fs.closeSync(err);owned.add(launcher.pid);await until(()=>{const p=ps().find(p=>p.pid===launcher.pid);if(p){ownedIdentity.set(p.pid,p.command);return true;}},2000,'owned launcher');record({event:'app-started',role,pid:launcher.pid});
 watcher=(async()=>{let lastDraws=-1,lastDrawAt=Date.now(),lowSince=0;while(!stopGuard){await delay(1000);if(stopGuard)break;try{
  if(Date.now()>deadline)throw Error('Bounded benchmark deadline');discover();guardForeground();guardFatalLog();if(Date.now()-lastPowerCheck>=15000)checkPower('periodic');
  for(const [file,max]of [[events,8*1024*1024],...['launcher.stdout.log','launcher.stderr.log'].map(n=>[path.join(run,n),8*1024*1024]),...['infolog.txt','stack-game.stderr.log'].map(n=>[path.join(data,n),16*1024*1024])])if(fs.existsSync(file)&&fs.statSync(file).size>max)throw Error('Bounded owned log byte cap: '+path.basename(file));
  const s=status();if(gamePid&&s&&!hasAcknowledgedMeasuredQuit(s,measuredQuitRequestID,receipt.benchmark?.status==='complete')){const n=Number(s.draws);if(n>lastDraws){lastDraws=n;lastDrawAt=Date.now();}if(Date.now()-lastDrawAt>12000)throw Error('Actual draw progression stalled');if(Number(s.frame)>0&&Number(s.fps)<2){lowSince ||= Date.now();if(Date.now()-lowSince>5000)throw Error('Actual FPS below finite bound');}else lowSince=0;}
 }catch(e){failure=e;record({event:'owned-safety-stop',message:String(e)});for(const p of discover())try{process.kill(p.pid,'SIGTERM');}catch{}await delay(500);for(const p of discover())try{process.kill(p.pid,'SIGKILL');}catch{}break;}}})();
 await attachBootstrap(nodePort,launcher.pid);
 // Wait for two stable read-only ready observations before the one launch action.
 { const end=Date.now()+30000;let previous=null,stable=0;
   while(Date.now()<end){
     try{const q=await renderer('({ready:document.readyState,api:typeof window.game?.launchScript,url:location.href})',5000);
       if(q.ready==='complete'&&q.api==='function'&&q.url===previous)stable++;else stable=0;
       previous=q.url;if(stable>=2)break;
     }catch(e){if(!String(e).includes('Execution context was destroyed'))throw e;stable=0;previous=null;}
     await delay(1000);
   }
   if(stable<2)throw Error('Stable read-only Lobby readiness unavailable');
 }
 await renderer(`window.game.launchScript(${JSON.stringify(fs.readFileSync(plan.scene.path,'utf8'))},${JSON.stringify(plan.game)},${JSON.stringify(plan.engineVersion)}).then(()=>"game-loaded")`);
 const native=await until(()=>eventRows().find(e=>e.event==='owned-child'&&e.nativeGuardInjected&&!e.args?.some(a=>a==='--version'||a==='--sync-version')&&!e.args?.includes('--menu')),30000,'actual Lobby graphical game PID');gamePid=native.childPid;gameSpawnAt=native.at;
 const ready=await until(()=>{const s=status();if(s?.qualityError&&s.qualityError!=='none')throw Error('Controller quality failure: '+s.qualityError);if(s?.note?.startsWith('quality-error')||s?.note?.startsWith('command-failed'))throw Error(s.note);const resultPath=path.join(data,'LuaUI/Config/v104-performance-result.json');if(fs.existsSync(resultPath)){try{const result=JSON.parse(fs.readFileSync(resultPath));if(result.status==='failed'||result.status==='timeout')throw Error('Controller result before ready: '+(result.error||result.status));}catch(e){if(e instanceof SyntaxError)return null;throw e;}}return s?.note==='fixed-scene-paused'?s:null;},150000,'fixed frame 240 ready');readyAt=Date.now();record({event:'fixed-scene-ready',status:ready});
 if(Number(ready.frame)!==240||ready.ultra!=='verified'||ready.qualification!=='complete'||Number(ready.width)!==plan.expectedDrawable.width||Number(ready.height)!==plan.expectedDrawable.height||ready.map!==plan.map||ready['config.MSAA']!=='0'||ready['config.MSAALevel']!=='0'||ready['config.VSync']!=='0'||ready['config.VSyncGame']!=='0')throw Error('Benchmark ready scene/Ultra/AA/VSync request/viewport differs');
 receipt.timing={preparationMs:receipt.preparationMs,launchToReadyMs:readyAt-launchAt,nativeSpawnToReadyMs:readyAt-gameSpawnAt,launchAt,gameSpawnAt,readyAt};
 const mapped=execFileSync('/usr/sbin/lsof',['-p',String(gamePid),'-Fn'],{encoding:'utf8',timeout:5000,maxBuffer:4*1024*1024});const mappedNames=new Set(mapped.split('\n').filter(l=>l.startsWith('n')).map(l=>l.slice(1)));const requiredLibraries=plan.sharedRuntime.filter(p=>p.path.endsWith('.dylib'));if(requiredLibraries.some(p=>!mappedNames.has(p.path)))throw Error('Actual loaded runtime library path differs: '+JSON.stringify(requiredLibraries.filter(p=>!mappedNames.has(p.path)).map(p=>p.path)));receipt.loadedRuntimeLibraries={verified:true,libraries:requiredLibraries};
 const guardEvents=fs.readFileSync(path.join(data,'hidden-window-events.jsonl'),'utf8').trim().split('\n').map(JSON.parse);if(!guardEvents.some(x=>x.pid===gamePid&&x.event==='created-hidden-verified'))throw Error('Actual native window hidden creation unverified');receipt.hiddenWindowEvents=guardEvents;
 const fullEvents=guardEvents.filter(e=>e.event==='fullscreen-enabled-hidden'||e.event==='fullscreen-disabled-hidden'),fullEvent=fullEvents.at(-1);
 if(!fullEvent||fullEvent.event!=='fullscreen-enabled-hidden'||!(fullEvent.flags&1)||!(fullEvent.flags&8))throw Error('Actual SDL fullscreen intent and hidden state unverified');
 const nativeLog=fs.readFileSync(path.join(data,'infolog.txt'),'utf8');
 const fullModes=[...nativeLog.matchAll(/cfgFullScreen=(\d)/g)];
 const safeViews=[...nativeLog.matchAll(/macOS safe viewport\] window=(\d+)x(\d+) view=<(-?\d+),(-?\d+) (\d+)x(\d+)>/g)];
 const lastView=safeViews.at(-1);
 if(fullModes.at(-1)?.[1]!=='1'||!lastView||Number(lastView[5])!==1512||Number(lastView[6])!==950)throw Error('Engine fullscreen safe viewport unverified');
 receipt.fullscreenMode={gameFullscreen:true,SDLFullscreen:true,SDLHidden:true,window:{width:Number(lastView[1]),height:Number(lastView[2])},viewport:{width:Number(lastView[5]),height:Number(lastView[6])},nativePresentation:'SDL defers native display/Space transition while hidden',logEvidence:lastView[0]};

 const log=fs.readFileSync(path.join(data,'infolog.txt'),'utf8');if(!log.includes('infologVersionTags:engine='+plan.engineVersion+',game='+plan.game+',')||!log.includes('map='+plan.map))throw Error('Actual engine/game/map mismatch');
 if(!/\[CUS GL4\] Ready/.test(log))throw Error('CUS GL4 route missing');
 const exactMSAA=log.match(/\[MacSDL3EGL::TryChooseExactConfig\] configured=0 requested=0 selected=0 sampleBuffers=0[^\n]*/);
 if(!exactMSAA)throw Error('Actual EGL AA-Off config proof missing');receipt.msaaConfigEvidence=exactMSAA[0];
 const vsyncLines=[...log.matchAll(/\[VSync::SetInterval\] interval=([-+]?\d+) \(([^)]+)\)/g)];
 if(!vsyncLines.length||vsyncLines.at(-1)[1]!=='0'||vsyncLines.at(-1)[2]!=='disabled')throw Error('Last engine VSync request is not interval=0 disabled');
 receipt.vsync={requested:0,engineLogLast:vsyncLines.at(-1)[0],sourceInference:'Mesa Kopper initializes swap interval 0, which selects Vulkan immediate present when supported; MoltenVK applies present mode to CAMetalLayer. Actual present mode remains unobserved.'};
 guardFatalLog();
 if(log.includes('gui_run95_luavbo_layout_validation.lua')||log.includes('run95-vbo-request.txt'))throw Error('Unrelated VBO fixture present in performance trial');
 checkPower('before-benchmark');
 const begin=await request('benchmark');if(!['benchmark-starting','benchmark-running'].includes(begin.note))throw Error('Benchmark command refused');benchmarkStartAt=Date.now();
 const resultPath=path.join(data,'LuaUI/Config/v104-performance-result.json');const result=await until(()=>{try{return JSON.parse(fs.readFileSync(resultPath));}catch{return null;}},220000,'official gadget benchmark result');benchmarkFinishAt=Date.now();requireBenchmarkResult(result,begin.id);await until(()=>{const s=status();return s?.note==='benchmark-complete'&&s.result==='written'?s:null;},5000,'benchmark completion status');receipt.benchmark=result;receipt.benchmarkEvidence={path:resultPath,sha256:hash(resultPath)};receipt.timing.hostBenchmarkElapsedMs=benchmarkFinishAt-benchmarkStartAt;checkPower('after-benchmark');

 receipt.postMeasurementFixtures='excluded_from_existing_performance_only_scope';
  measuredQuitRequestID=crypto.randomUUID();fs.writeFileSync(path.join(data,'LuaUI/Config/v104-performance-request.txt'),measuredQuitRequestID+'|quit|\n');const exit=await until(()=>{const e=gameExitEvent(eventRows(),gamePid);return e&&!discover().some(p=>p.pid===gamePid)?e:null;},15000,'native game exit callback and PID absence');if(exit.code!==0||exit.signal)throw Error('Native game exited abnormally');receipt.gracefulQuit=true;
 receipt.lobbyReturn=await renderer('({ready:document.readyState,api:typeof window.game?.launchScript,url:location.href})',15000);if(receipt.lobbyReturn.ready!=='complete'||receipt.lobbyReturn.api!=='function')throw Error('Actual Electron postgame readiness missing');
 receipt.status='completed-not-promoted';
}catch(e){receipt.status='failed';receipt.error=String(e);console.error(receipt.error);process.exitCode=1;}

finally{
 stopGuard=true;if(watcher)await watcher;
 if(failure){receipt.status='failed';receipt.error=String(failure);process.exitCode=1;}
 for(const p of discover())try{process.kill(p.pid,'SIGTERM');}catch{}await delay(1000);for(const p of discover())try{process.kill(p.pid,'SIGKILL');}catch{}await delay(300);
 const remaining=discover();receipt.remainingOwnedProcesses=remaining;
 try{
  if(remaining.length)throw Error('Runtime cache evidence requires all owned processes closed');
  guardFatalLog();
  const driverLog=path.join(data,'stack-game.stderr.log'),text=fs.readFileSync(driverLog,'utf8');
  const uuids=[...text.matchAll(/pipelineCacheUUID:\s*([0-9a-fA-F-]{36})/g)].map(m=>m[1].toLowerCase());
  if(!uuids.length||uuids.some(u=>u.slice(0,8)!==plan.mvkGitRev))throw Error('Actual game MoltenVK cache UUID missing/different');
  receipt.runtimeUUID={prefix:plan.mvkGitRev,uuids:[...new Set(uuids)],driverLog:{path:driverLog,sha256:hash(driverLog)}};
  const nativeQueues=[...text.matchAll(/Native Metal 4 command backend active on queue ([^\n]+)\./g)];
  const nativeCompleted=[...text.matchAll(/Native Metal 4 queue [^\n]+ retired (\d+) completed submissions\./g)].map(m=>Number(m[1]));
  if(plan.nativeMetal4){
   if(!nativeQueues.length||!nativeCompleted.length||nativeCompleted.some(n=>!Number.isSafeInteger(n))||nativeCompleted.reduce((a,b)=>a+b,0)<=0)throw Error('Actual native Metal4 queue completion proof missing');
   receipt.nativeMetal4={requested:true,activeQueues:nativeQueues.length,completedSubmissions:nativeCompleted,proved:true};
  }else{
   if(nativeQueues.length||nativeCompleted.length)throw Error('Pinned legacy comparison unexpectedly selected native Metal4');
   receipt.nativeMetal4={requested:false,activeQueues:0,proved:false,legacyParentIdentityVerified:role==='parent'};
  }
  if(/\[mvk-(?:metal4-(?:queue-)?stats|backend-cost)/.test(text))throw Error('Unexpected runtime performance diagnostics during ordinary benchmark');
  const routes=eventRows().filter(e=>e.event==='stack-private-cache-route');
  if(routes.length!==1||routes[0].nativeMetal4!==(plan.nativeMetal4?'1':'0')||routes[0].diagnosticsOff!==true)throw Error('Actual benchmark runtime environment proof missing');
  if(routes[0].policy.BAR_ZINK_MVK_DISABLE_ASYNC_WAIT!==(plan.disableAsyncWait?'1':'0'))throw Error('Actual wait policy differs');
  receipt.runtimeEnvironment=routes[0];
  const nativeLog=path.join(data,'infolog.txt'),native=fs.readFileSync(nativeLog,'utf8');
  if(receipt.status==='completed-not-promoted'&&(!native.includes('Starting Benchmark')||!native.includes('Benchmark complete')||!/Sim \d+ frames/.test(native)||!/Draw \d+ frames/.test(native)))throw Error('Official native benchmark report missing');
  receipt.officialNativeReport={present:native.includes('Benchmark complete'),nativeLog:{path:nativeLog,sha256:hash(nativeLog)}};
  const mesaIds=[...native.matchAll(/GL_VERSION=[^\n]*Mesa[^\n]*\(git-([0-9a-fA-F]{8,40})\)/g)]
    .map(m=>m[1].toLowerCase());
  if(mesaIds.some(id=>id!==plan.mesaGitSha1.slice(0,id.length))||!receipt.loadedRuntimeLibraries?.verified)
    throw Error('Actual game Mesa build identity or Zink/MoltenVK path differs');
  receipt.mesaRuntimeBuildID={expected:plan.mesaGitSha1,observed:[...new Set(mesaIds)],
   nativeLog:{path:nativeLog,sha256:hash(nativeLog)}};
  receipt.cache.after=cacheInventory(receipt.cache.directory);if(!receipt.cache.after.entries.length)throw Error('No persisted private Mesa shader cache');
 }catch(e){receipt.status='failed';receipt.cacheError=String(e);process.exitCode=1;}
 try{if(!remaining.length&&fs.existsSync(assets)&&['maps','pool','packages','rapid'].every(n=>fs.existsSync(path.join(assets,n))))receipt.cleanup=cleanupPrivateTrialCaches({run,validationRoot,remainingOwnedProcesses:0});}catch(e){receipt.status='failed';receipt.cleanupError=String(e);process.exitCode=1;}
 try{checkPins();receipt.protectedInputsUnchanged=true;}catch(e){receipt.status='failed';receipt.protectedInputsUnchanged=false;receipt.protectionError=String(e);process.exitCode=1;}
 if(remaining.length){receipt.status='failed';process.exitCode=1;}
 try{checkPower('post-exit');receipt.powerConditionsPassed=true;}catch(e){receipt.status='failed';receipt.powerConditionsPassed=false;receipt.powerError=String(e);process.exitCode=1;}
 if(receipt.powerObservations.some(s=>!s.passed))receipt.powerConditionsPassed=false;
 receipt.foregroundChecks=foregroundChecks;
 if(strictHidden && fs.existsSync(path.join(data,'hidden-window-events.jsonl')))
   receipt.hiddenWindowEvents=fs.readFileSync(path.join(data,'hidden-window-events.jsonl'),'utf8').trim().split('\n').filter(Boolean).map(line=>JSON.parse(line));
 receipt.finishedAt=new Date().toISOString();fs.writeFileSync(path.join(run,'execution-receipt.json'),JSON.stringify(receipt,null,2)+'\n',{flag:'wx'});console.log(JSON.stringify({role,status:receipt.status,run,error:receipt.error,protectedInputsUnchanged:receipt.protectedInputsUnchanged,remaining:remaining.length}));
}
