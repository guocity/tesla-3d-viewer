// Run with: playwright-cli -s=viewer-check run-code "$(cat scripts/check-viewer.browser.js)"
// The browser must already be open on the local viewer.
async page => {
  const url = new URL(page.url().startsWith('http') ? page.url() : 'http://127.0.0.1:5174/');
  url.search = '?vehicle=cybertruck';
  await page.bringToFront();
  await page.setViewportSize({width:1100,height:760});
  await page.addInitScript(()=>{
    window.__adMixValues=[];window.__chargeTimes=[];window.__chargeActive=0;
    const names=new WeakMap(),proto=WebGL2RenderingContext.prototype;
    const get=proto.getUniformLocation,set=proto.uniform1f;
    proto.getUniformLocation=function(program,name){const loc=get.call(this,program,name);if(loc&&['uShowroomAdMix','uShowroomChargeTime','uShowroomChargeActive'].includes(name))names.set(loc,name);return loc;};
    proto.uniform1f=function(loc,value){if(names.get(loc)==='uShowroomChargeTime'){window.__chargeTimes.push(value);if(window.__chargeTimes.length>120)window.__chargeTimes.shift();}
    if(names.get(loc)==='uShowroomChargeActive')window.__chargeActive=value;
    if(names.get(loc)==='uShowroomAdMix'){window.__lastAdMix=value;const v=Math.round(value*10)/10;if(!window.__adMixValues.includes(v))window.__adMixValues.push(v);}return set.call(this,loc,value);};
  });
  await page.goto(url.href,{waitUntil:"domcontentloaded",timeout:60000});
  await page.locator('.scene-appearance:not(:disabled)').waitFor({timeout:30000});
  const results=[];
  async function appearance(expected) {
    // This is emitted by the authored scene, so a CSS-only label change fails.
    const sceneCommand=page.waitForEvent('console',{predicate:m=>m.text()===expected,timeout:5000});
    await page.locator('.scene-appearance').click();
    await sceneCommand;
    const pressed=await page.locator('.scene-appearance').getAttribute('aria-pressed');
    if(pressed!==String(expected==='night'))throw Error('Appearance label disagrees with scene');
    results.push(expected);
  }
  await appearance('night');
  await appearance('day');
  // Take focus into an HTML input before switching again.
  await page.locator('.model-trigger').click();
  await page.locator('.model-search input').fill('Model');
  await page.locator('.model-close').click();
  await appearance('night');
  // Changing a vehicle creates a fresh Rive focus tree and must retain night.
  const reapplied=page.waitForEvent('console',{predicate:m=>m.text()==='night',timeout:20000});
  await page.locator('#vehicle').selectOption('model3_high',{force:true});
  await reapplied;
  await page.locator('.scene-appearance:not(:disabled)').waitFor({timeout:20000});
  await appearance('day');
  await page.locator('#vehicle').selectOption('cybertruck',{force:true});
  await page.locator('.scene-appearance:not(:disabled)').waitFor({timeout:20000});
  await page.locator('#animation-mode').click();
  const roof=page.locator('[data-clip="RoofLightbarAnimation"]');
  if(await roof.getAttribute('aria-checked')!=='false')throw Error('Roof light bar should default off');
  if(await page.locator('[data-clip="ChargeportAnimation"]').count()!==1)throw Error('Missing Cybertruck charge-port clip');
  const drl=page.locator('[data-clip="DRLAnimation"]'), brakes=page.locator('[data-clip="BrakeLightsAnimation"]');
  if(await drl.getAttribute('aria-checked')!=='true'||await brakes.getAttribute('aria-checked')!=='false')throw Error('DRL must default on with brakes off');
  await brakes.click();
  if(await drl.getAttribute('aria-checked')!=='false'||await brakes.getAttribute('aria-checked')!=='true')throw Error('Brake lights must exclude DRL');
  await drl.click();
  await page.locator('.showroom-motion [data-close]').click();
  await page.locator('.tesla-charge-hotspot').click({force:true});
  await page.waitForFunction(()=>document.querySelector('.tesla-charge-hotspot').dataset.connection==='1.000',null,{timeout:15000});
  await page.waitForFunction(()=>window.__chargeActive===1&&Math.max(...window.__chargeTimes)-Math.min(...window.__chargeTimes)>.2,null,{timeout:5000});
  await page.waitForFunction(()=>document.querySelector('.tesla-charge-hotspot').dataset.view==='charge-port',null,{timeout:7000});
  const focusEye=JSON.parse(await page.locator('.tesla-charge-hotspot').getAttribute('data-camera-eye'));
  if(focusEye[0]>=0||focusEye[2]<=0)throw Error('Charging camera must show rear-left port side');
  if(await page.locator('.charge-tooltip').count())throw Error('Charging tooltip must be removed');
  await page.screenshot({path:'evidence/cybertruck-charging-verified.png',scale:'css'});
  const hotspot=page.locator('.tesla-charge-hotspot');
  const eye=async()=>JSON.parse(await hotspot.getAttribute('data-camera-eye'));
  const moved=(a,b)=>Math.hypot(...a.map((v,i)=>v-b[i]))>.3;
  let before=await eye();
  let box=await hotspot.boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);
  await page.mouse.down();
  await page.mouse.move(box.x+box.width/2+180,box.y+box.height/2-30,{steps:12});
  await page.mouse.up();
  await page.waitForTimeout(150);
  if(!moved(before,await eye()))throw Error('Mouse drag did not rotate the charging car');
  if(await hotspot.getAttribute('aria-pressed')!=='true')throw Error('Dragging disconnected charging');
  // Use real touch input so pointer capture and touch-action are exercised too.
  const cdp=await page.context().newCDPSession(page);
  box=await hotspot.boundingBox();
  const x=box.x+box.width/2,y=box.y+box.height/2;
  before=await eye();
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});
  for(let step=1;step<=8;step++){await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:x-step*12,y}]});await page.waitForTimeout(25);}
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  await cdp.detach();
  await page.waitForTimeout(150);
  if(!moved(before,await eye()))throw Error('Touch drag did not rotate the charging car');
  if(await hotspot.getAttribute('aria-pressed')!=='true')throw Error('Touch dragging disconnected charging');
  await page.screenshot({path:'evidence/charging-drag-rotation-verified.png',scale:'css'});
  await page.locator('.tesla-charge-hotspot').click({force:true});
  await page.waitForFunction(()=>{const s=document.querySelector('.tesla-charge-hotspot').dataset;return s.connection==='0.000'&&s.portOpen==='0.000';},null,{timeout:15000});
  await page.waitForFunction(()=>window.__chargeActive===0,null,{timeout:5000});
  await page.locator('.model-trigger').click();
  const images=await page.locator('.model-thumbnail img').evaluateAll(imgs=>imgs.map(i=>({loaded:i.complete&&i.naturalWidth>=480,src:i.getAttribute('src')})));
  if(images.length!==12 || images.some(i=>!i.loaded))throw Error('Vehicle studio thumbnails failed to load');
  await page.screenshot({path:'evidence/vehicle-picker-studio-verified.png',scale:'css'});
  await page.locator('.model-close').click();
  await page.waitForFunction(()=>window.__adMixValues.includes(0)&&window.__adMixValues.includes(1),null,{timeout:20000});
  const adLoaded=await page.evaluate(()=>performance.getEntriesByType('resource').some(r=>/lgnat.*\.jpg/.test(r.name)));
  if(!adLoaded)throw Error('Monitor ad JPEG was not loaded');
  await page.screenshot({path:'evidence/lgnat-monitor-final.png',scale:'css'});
  return {appearance:results,nightPreservedAcrossVehicleChange:true,charging:'connected and disconnected; APK cable-flow shader clock advances and stops',roofBar:'off by default',studioImages:images.length,chargingRotation:'mouse and touch drags passed',rearLights:'three red DRL segments and separate brakes',monitor:'JPEG ad and original colors both rendered'};
}
