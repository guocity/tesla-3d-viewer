async page => {
 await page.setViewportSize({width:1200,height:800});const results=[];
 for(const id of ['cybertruck','bayberry','modely_high','models_plaid']){
  await page.goto('http://127.0.0.1:5174/?vehicle='+id);await page.bringToFront();
  const b=page.locator('.tesla-charge-hotspot');await b.waitFor({state:'visible',timeout:45000});
  await page.evaluate(()=>{window.__chargeFrames=[];const start=performance.now();function frame(){const b=document.querySelector('.tesla-charge-hotspot');window.__chargeFrames.push({t:performance.now()-start,...b.dataset});if(performance.now()-start<5000)requestAnimationFrame(frame);}requestAnimationFrame(frame);});
  await b.click();await page.waitForFunction(()=>document.querySelector('.tesla-charge-hotspot').dataset.view==='charge-port',null,{timeout:10000});
  const focused=JSON.parse(await b.getAttribute('data-camera-eye'));
  await page.mouse.move(570,420);await page.mouse.down();await page.mouse.move(680,430,{steps:12});await page.mouse.up();
  await page.waitForTimeout(100);const rotated=JSON.parse(await b.getAttribute('data-camera-eye'));
  if(Math.hypot(...rotated.map((x,i)=>x-focused[i]))<.5)throw Error(id+' camera did not rotate freely');
  await page.waitForTimeout(400);const released=JSON.parse(await b.getAttribute('data-camera-eye'));
  if(Math.hypot(...released.map((x,i)=>x-rotated[i]))>.1)throw Error(id+' camera snapped back');
  await page.waitForFunction(()=>document.querySelector('.tesla-charge-hotspot').dataset.connection==='1.000',null,{timeout:15000});
  const state=await b.evaluate(e=>({...e.dataset}));if(state.hasCable!=='true')throw Error(id+' cable missing');
  const frames=await page.evaluate(()=>window.__chargeFrames);if(frames.some(f=>f.view==='focusing'&&Number(f.portOpen)>0))throw Error(id+' port opened before camera release');
  await page.screenshot({path:'/Users/m4air/Documents/github/android_apk/tesla-3d-viewer/evidence/'+id+'-charging-free-orbit.png'});
  results.push({id,sequence:'camera then port then cable',rotation:'free, no snap',cable:state.hasCable});
 }
 return results;
}
