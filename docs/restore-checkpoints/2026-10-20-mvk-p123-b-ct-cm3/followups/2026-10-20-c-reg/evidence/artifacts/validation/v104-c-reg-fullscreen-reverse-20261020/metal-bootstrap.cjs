// Private r39 official benchmark wrapper: exact backend, diagnostics OFF, existing hidden guards.
module.exports=function(config){
 const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),child=require('node:child_process');
 const sha=b=>crypto.createHash('sha256').update(b).digest('hex'),helper=process.argv.includes('--bar-chobby-loopback-helper');
 if(typeof config.nativeMetal4!=='boolean'||config.stackLane!=='lobby'||!config.strictHiddenWindow||config.allowNativeWindow!==false)throw Error('Exact Run95 stack hidden lane');
 if(config.disableAsyncWait!==true)throw Error('Exact authorized local submit wait OFF required');
 const base=path.join(__dirname,'benchmark-bootstrap.cjs');
 if(sha(fs.readFileSync(base))!==config.stackQualifiedAdapterSha256)throw Error('Qualified adapter drift');
 const result=require(base)(config),guarded=child.spawn;
 const data=path.join(config.state,'data'),runtime=path.join(config.app,'Contents/Resources/bundled-assets/runtime');
 for(const pin of config.sharedRuntimePins){if(!pin.path.startsWith(runtime+'/')||fs.realpathSync(pin.path)!==pin.path||sha(fs.readFileSync(pin.path))!==pin.sha256)throw Error('Runtime drift');}
 const append=e=>fs.appendFileSync(config.events,JSON.stringify({at:Date.now(),pid:process.pid,...e})+'\n');
 child.spawn=function(command,args=[],options={}){
  if(path.basename(command)==='spring' && args.includes('--calc-checksum'))return guarded.call(this,command,args,options);
  if(path.basename(command)==='spring' && args.length===1 && (args[0]==='--version'||args[0]==='--sync-version'))return guarded.call(this,command,args,options);
  if(path.basename(command)!=='spring'||args.some(a=>a==='--version'||a==='--sync-version'))return guarded.call(this,command,args,options);
  const env={...(options.env||process.env)},removedDiagnosticKeys=[];
  for(const key of Object.keys(env))if(/^(?:MTL_DEBUG|MTL_SHADER_VALIDATION|MTL_CAPTURE)/.test(key)||['METAL_DEVICE_WRAPPER_TYPE','VK_INSTANCE_LAYERS','VK_LOADER_LAYERS_ENABLE','VK_LAYER_ENABLES','VK_LAYER_SETTINGS_PATH'].includes(key)){removedDiagnosticKeys.push(key);delete env[key];}
  if(env.ZINK_DEBUG||env.GALLIUM_THREAD||env.MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS)throw Error('Inherited submit/debug override prohibited');
  const policy={BAR_ZINK_MVK_DISABLE_ASYNC_WAIT:config.disableAsyncWait?'1':'0',MVK_CONFIG_USE_METAL4:config.nativeMetal4?'1':'0',MVK_CONFIG_LOG_LEVEL:'3',
   MVK_CONFIG_METAL4_PREPASS:'1',MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS:'0',
   MVK_CONFIG_METAL4_STATS:'0',MVK_CONFIG_METAL4_QUEUE_STATS:'0',MVK_CONFIG_BACKEND_COST_STATS:'0',
   MVK_CONFIG_METAL4_FUSED_RESTART:'0',MVK_CONFIG_TRACE_VULKAN_CALLS:'0',MVK_CONFIG_PERFORMANCE_TRACKING:'0'};
  Object.assign(env,policy);options={...options,env};
  const icd=path.join(runtime,'moltenvk-pr2746/MoltenVK_icd.json');
  const required={XDG_CACHE_HOME:path.join(data,'cache',config.nativeMetal4?'metal4':'metal3'),VK_DRIVER_FILES:icd,VK_ICD_FILENAMES:icd,DYLD_LIBRARY_PATH:['sdl3/lib','mesa-zink/lib','vulkan-loader/lib','moltenvk-pr2746/lib'].map(p=>path.join(runtime,p)).join(path.delimiter)};
  if(Object.entries(required).some(([k,v])=>env[k]!==v)||env.MESA_SHADER_CACHE_DIR||env.MESA_SHADER_CACHE_DISABLE)throw Error('Unexpected cache/runtime environment');
  append({event:'stack-private-cache-route',nativeMetal4:env.MVK_CONFIG_USE_METAL4,helper,cache:required.XDG_CACHE_HOME,icd,mode:config.stackCacheMode,diagnosticsOff:true,policy,removedDiagnosticKeys,argumentBuffers:env.MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS??null,synchronousQueueSubmits:env.MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS??null});
  if(helper)throw Error('Chobby helper forbidden in Lobby benchmark');
  const handle=guarded.call(this,command,args,options);
  if(config.stackLane==='lobby'){
   if(!handle.stderr)throw Error('Actual lobby stderr pipe missing');
   const filename=path.join(data,'stack-game.stderr.log');fs.writeFileSync(filename,'',{flag:'wx'});let bytes=0;
   handle.stderr.on('data',b=>{bytes+=b.length;if(bytes>16*1024*1024){append({event:'stack-stderr-budget-stop',childPid:handle.pid});handle.kill('SIGTERM');return;}fs.appendFileSync(filename,b);});
  }
  return handle;
 };
 require('node:module').syncBuiltinESMExports();return result;
};
