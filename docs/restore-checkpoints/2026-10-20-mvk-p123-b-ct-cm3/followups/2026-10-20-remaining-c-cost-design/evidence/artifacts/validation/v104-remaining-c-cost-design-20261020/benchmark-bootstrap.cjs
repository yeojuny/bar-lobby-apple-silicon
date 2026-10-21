// Private Run95 stack benchmark adapter; Lobby only, hidden native window only.
module.exports = function install(config) {
  const strictHidden = config.strictHiddenWindow === true;
  if(config.allowNativeWindow !== true && !strictHidden) throw Error('Explicit capture mode required');
  if(strictHidden && config.allowNativeWindow === true) throw Error('Hidden capture cannot allow a visible window');
  const fs = require('node:fs');
  const path = require('node:path');
  const child = require('node:child_process');
  const crypto = require('node:crypto');
  const electron = require('electron');
  const append = value => fs.appendFileSync(config.events, JSON.stringify({at:Date.now(),pid:process.pid,...value})+'\n');
  const fixed = {BAR_STATE_PATH:config.state,BAR_ASSETS_PATH:config.assets};
  const environment = {...process.env,...fixed};
  process.env = new Proxy(environment, {set(target,key,value) {target[key] = key in fixed ? fixed[key] : String(value);return true;}});
  electron.app.setActivationPolicy('prohibited');
  electron.app.on('ready', () => electron.app.setActivationPolicy('prohibited'));
  if (electron.app.dock) electron.app.dock.hide = () => {};
  electron.app.on('web-contents-created', (_,contents) => contents.setAudioMuted(true));
  for (const method of ['show','showInactive','focus','restore','maximize','setFullScreen','flashFrame']) {
    electron.BrowserWindow.prototype[method] = function () {};
  }
  electron.shell.openExternal = async () => {throw Error('External application opening is disabled for this background test');};
  function privateWindowSettings() {
    const filename = path.join(config.state,'data/springsettings.cfg');
    if (fs.realpathSync(path.dirname(filename)) !== path.join(config.state,'data') || fs.lstatSync(filename).isSymbolicLink()) throw Error('Non-private settings refused');
    const wanted = {Fullscreen:0,WindowBorderless:0,XResolutionWindowed:1512,YResolutionWindowed:950,WindowPosX:80,WindowPosY:80,Sound:0,MSAA:0,MSAALevel:-1,VSync:0,VSyncGame:0};
    const lines=fs.readFileSync(filename,'utf8').split(/\r?\n/).filter(line=>!Object.keys(wanted).some(key=>new RegExp('^\\s*'+key+'\\s*=').test(line)));
    fs.writeFileSync(filename,lines.join('\n')+'\n'+Object.entries(wanted).map(([k,v])=>`${k} = ${v}`).join('\n')+'\n');
  }
  const gatePath='/Users/yeojun/Desktop/BAR-AppleSilicon-App/tools/lib/run94-current-content-gate.cjs';
  const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
  if(config.scenario!=='stack-benchmark'||!strictHidden||config.allowNativeWindow!==false)throw Error('Exclusive hidden stack benchmark scope required');
  if(process.execPath!==path.join(config.app,'Contents/MacOS/BAR')||fs.realpathSync(config.state)!==config.state||fs.realpathSync(config.assets)!==config.assets)throw Error('Actual owned app/private directories required');
  if(sha(fs.readFileSync(gatePath))!==config.contentGateSha256||sha(fs.readFileSync(config.contentManifest))!==config.contentManifestSha256)throw Error('Pinned current content gate/manifest changed');
  const gate=require(gatePath),content=JSON.parse(fs.readFileSync(config.contentManifest));
  // Preserve the already verified private benchmark tag indexes across downloader refresh.
  // Actual package/pool bytes and all original content gates remain unchanged.
  gate.tags(config.assets,content);
  const fixedIndexes=[...new Set(content.tags.map(t=>t.relative))].map(relative=>{
    const filename=path.join(config.assets,relative);
    if(!filename.startsWith(config.assets+'/rapid/')||fs.realpathSync(filename)!==filename)throw Error('Non-private rapid index refused');
    return {relative,filename,bytes:fs.readFileSync(filename)};
  });

  if(content.maxBytes-content.baseBytes!==8*1024*1024||content.maxFiles-content.baseFiles!==128)throw Error('Exact bounded growth contract required');
  const engine=path.join(config.app,'Contents/Resources/bundled-assets/engine',config.engineVersion,'spring');
  if(!/^[a-f0-9]{64}$/.test(config.engineSha256||'')||sha(fs.readFileSync(engine))!==config.engineSha256)throw Error('Exact native Lobby engine pin required');
  if(sha(require('original-fs').readFileSync(path.join(config.app,'Contents/Resources/app.asar')))!==config.appAsarSha256)throw Error('Actual installed launcher pin differs');
  if(config.presentationOverrides?.length||config.privateFixtureFiles?.length||config.sensorProbeSuffix)throw Error('No presentation, probe or private fixture override in benchmark');
  function privatePins(){
    const wanted='LuaUI/Widgets/gui_run95_stack_benchmark.lua';
    if(config.privateBenchmarkFiles?.length!==1||config.privateBenchmarkFiles[0].relative!==wanted)throw Error('Only the performance controller is permitted');
    const target=path.join(config.state,'data',wanted);
    if(fs.realpathSync(target)!==target||sha(fs.readFileSync(target))!==config.privateBenchmarkFiles[0].sha256)throw Error('Private benchmark controller drift');
  }
  privatePins();
  let nativeSpawns=0;
  const originalSpawn=child.spawn;
  child.spawn=function (command,args=[],options={}) {
    args=[...args];options={...options,env:{...(options.env||process.env)}};
    const binary=path.basename(command);
    if(binary==='spring' && args.includes('--calc-checksum')){if(path.resolve(options.cwd||process.cwd(),command)!==engine||args.length!==5||args[0]!=='--write-dir'||args[1]!==path.join(config.state,'data')||args[2]!=='--isolation'||args[3]!=='--calc-checksum'||![config.map,config.game,config.menu].includes(args[4]))throw Error('Unpinned checksum preflight refused');const h=originalSpawn.call(this,command,args,options);append({event:'owned-content-checksum',childPid:h.pid,command,args,enginePath:options.cwd});return h;}
    append({event:'private-spawn-entry',command,args,nativeSpawns});
    if(binary==='spring' && args.length===1 && (args[0]==='--version'||args[0]==='--sync-version')){const h=originalSpawn.call(this,command,args,options);append({event:'owned-version-check',childPid:h.pid,args});return h;}
    const helper=command===process.execPath && args.includes('--bar-chobby-loopback-helper');
    if(helper)throw Error('Chobby helper forbidden in actual Lobby-only scope');
    if(binary==='pr-downloader'){
      const allowed=[config.game,'byar:test'];
      if(!command.startsWith(config.app+'/Contents/Resources/bundled-assets/engine/')||args.length!==4||args[0]!=='--filesystem-writepath'||args[1]!==config.assets||args[2]!=='--download-game'||!allowed.includes(args[3]))throw Error('Unbounded downloader refused');
      gate.tags(config.assets,content);gate.budget(config.assets,content);
      // Fixed benchmark content: resolve the exact selected version, never the moving tag.
      const requested=args[3];args[3]=config.game;
      append({event:'pinned-game-download',requested,resolved:args[3]});
    }
    if(binary==='spring'&&path.resolve(options.cwd||process.cwd(),command)!==engine)throw Error('Different native engine refused');
    if (binary==='spring' && !args.some(a=>a==='--version'||a==='--sync-version')) {
      privatePins();if(nativeSpawns++!==0)throw Error('One actual graphical Lobby game only');
      const script=path.join(config.state,'data/script.txt');
      if(args.length!==4||args[0]!=='--write-dir'||args[1]!==path.join(config.state,'data')||args[2]!=='--isolation'||args[3]!==script||sha(fs.readFileSync(script))!==config.startScriptSha256)throw Error('Exact actual launchScript arguments required');
      append({event:'pre-native-staged-official-checkpoint',...gate.verify(config.assets,content,{phase:'staged-official'})});
      const writeIndex=args.indexOf('--write-dir');
      if (writeIndex<0 || args[writeIndex+1]!==path.join(config.state,'data')) throw Error('Non-private engine write path refused');
      if (!path.resolve(options.cwd||'',command).startsWith(config.app+'/')) throw Error('Non-bundled engine refused');
      if (args.some(arg=>arg==='--fullscreen'||arg.startsWith('--fullscreen='))) throw Error('Fullscreen flag refused');
      privateWindowSettings();
      args.unshift('--window');
      if(strictHidden){
        if(!config.guardLibrary || !config.guardSha256 || crypto.createHash('sha256').update(fs.readFileSync(config.guardLibrary)).digest('hex')!==config.guardSha256)
          throw Error('Hidden-window guard identity mismatch');
        const windowLog=path.join(config.state,'data','hidden-window-events.jsonl');
        fs.writeFileSync(windowLog,'',{flag:'wx'});
        Object.assign(options.env,{DYLD_INSERT_LIBRARIES:config.guardLibrary,
          BAR_BG_ENGINE_PATH:path.resolve(options.cwd||'',command),BAR_BG_WINDOW_LOG:windowLog,
          SDL_MAC_BACKGROUND_APP:'1',SDL_WINDOW_ACTIVATE_WHEN_SHOWN:'0',SDL_WINDOW_ACTIVATE_WHEN_RAISED:'0'});

      }
    }
    if (binary==='spring') Object.assign(options.env, {
      ...fixed, SDL_WINDOW_ACTIVATE_WHEN_SHOWN:strictHidden?'0':'1',
      SDL_WINDOW_ACTIVATE_WHEN_RAISED:'0', SDL_VIDEO_MAC_FULLSCREEN_SPACES:'1',
      ALSOFT_DRIVERS:'null',
    });
    if(!strictHidden || binary!=='spring' || args.some(a=>a==='--version'||a==='--sync-version')) delete options.env.DYLD_INSERT_LIBRARIES;
    delete options.env.BAR_ACCEPTANCE_APP_ROOT;
    delete options.env.BAR_ACCEPTANCE_GUARD_LOG;
    if(binary==='spring' && !strictHidden) delete options.env.SDL_MAC_BACKGROUND_APP;
    if(helper) throw Error('Unexpected Chobby helper in bounded Lobby capture');
    const processHandle=originalSpawn.call(this,command,args,options);
    if (binary==='spring' || binary==='pr-downloader') append({event:'owned-child',childPid:processHandle.pid,helper,downloader:binary==='pr-downloader',command,args,enginePath:options.cwd,nativeGuardInjected:strictHidden&&binary==='spring',overlayPath:options.env.SPRING_DATADIR||options.env.SPRING_DATADIRS||null});
    if(binary==='spring')processHandle.once('exit',(code,signal)=>append({event:'owned-engine-exit',childPid:processHandle.pid,code,signal}));
    if(binary==='pr-downloader'){
      const timer=setTimeout(()=>{append({event:'download-timeout-stop',childPid:processHandle.pid});processHandle.kill('SIGKILL');},60000);
      processHandle.once('exit',(code,signal)=>{
        clearTimeout(timer);
        if(code===0&&!signal){
          for(const index of fixedIndexes){
            if(fs.realpathSync(index.filename)!==index.filename)throw Error('Private rapid index replaced with link');
            const before=sha(fs.readFileSync(index.filename)),after=sha(index.bytes);
            if(before!==after)fs.writeFileSync(index.filename,index.bytes);
            append({event:'pinned-rapid-index-restored',relative:index.relative,beforeSha256:before,afterSha256:after,changed:before!==after});
          }
          gate.tags(config.assets,content);gate.budget(config.assets,content);
        }
        append({event:'owned-downloader-exit',childPid:processHandle.pid,code,signal});
      });
    }
    return processHandle;
  };
  require('node:module').syncBuiltinESMExports();
  append({event:'bootstrap-installed',state:config.state,assets:config.assets,helper:process.argv.includes('--bar-chobby-loopback-helper')});
  return {pid:process.pid,policy:'prohibited',state:config.state};
};
