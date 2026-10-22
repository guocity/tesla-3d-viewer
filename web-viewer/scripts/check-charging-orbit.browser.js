// Start the viewer at phone size before loading, without any preceding keyboard
// commands or desktop session. Verify rendered camera movement, not just events.
async page => {
  const cdp=await page.context().newCDPSession(page),previous=page.viewportSize();
  try {
    await page.setViewportSize({width:390,height:844});
    await cdp.send('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:5});
    await cdp.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:2,mobile:true});
    const url=new URL(page.url());url.search='?vehicle=cybertruck';
    await page.goto(url.href,{waitUntil:'domcontentloaded'});
    await page.locator('.scene-appearance:not(:disabled)').waitFor({timeout:45000});
    const button=page.locator('.tesla-charge-hotspot');
    const eye=async()=>JSON.parse(await button.getAttribute('data-camera-eye'));
    await button.waitFor({state:'visible'});
    const box=await button.boundingBox();
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:1,x:box.x+box.width/2,y:box.y+box.height/2}]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    await page.waitForFunction(()=>document.querySelector('.tesla-charge-hotspot').dataset.view==='charge-port',null,{timeout:12000});
    await page.waitForFunction(()=>document.querySelector('.tesla-charge-hotspot').dataset.connection==='1.000');
    await page.screenshot({path:'evidence/charging-phone-fresh.png',scale:'css'});
    const before=await eye();
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:1,x:150,y:350}]});
    for(let i=1;i<=12;i++){
      await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{id:1,x:150+i*6,y:350}]});
      await page.waitForTimeout(25);
    }
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    await page.waitForTimeout(100);const after=await eye();
    if(Math.hypot(...after.map((v,i)=>v-before[i]))<.3)throw Error('Fresh-phone touch did not rotate the charging car');
    const zoomBefore=Number(await button.getAttribute('data-camera-zoom'));
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:1,x:130,y:350},{id:2,x:230,y:350}]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{id:1,x:100,y:350},{id:2,x:260,y:350}]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    await page.waitForTimeout(100);
    if(Number(await button.getAttribute('data-camera-zoom'))>=zoomBefore*.9)throw Error('Pinch did not zoom the car');
    if(await button.getAttribute('aria-pressed')!=='true')throw Error('Orbit disconnected charging');
    if(await page.locator('.charge-tooltip').count())throw Error('Charging tooltip is still present');
    return {freshPhone:'390x844',chargingView:'one transition',rotation:'actual camera position changed',pinch:'zoomed while charging',tooltip:'removed'};
  } finally {
    await cdp.send('Emulation.setTouchEmulationEnabled',{enabled:false});
    await cdp.send('Emulation.clearDeviceMetricsOverride');await cdp.detach();
    if(previous)await page.setViewportSize(previous);
  }
}
