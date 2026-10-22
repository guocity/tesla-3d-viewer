// Run with playwright-cli run-code against the running viewer.
async page => {
  await page.setViewportSize({width:440,height:800});
  await page.locator('#rive-stage[data-ready=true]').waitFor({timeout:60000});
  await page.waitForTimeout(1500);
  const cdp=await page.context().newCDPSession(page);
  const eye=async()=>JSON.parse(await page.locator('.tesla-charge-hotspot').getAttribute('data-camera-eye'));
  const heading=p=>Math.atan2(p[0],p[2]);
  const results=[];
  try {
    await cdp.send('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:1});
    for(const dx of [150,-150]) {
      const before=await eye();
      await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:200,y:400}]});
      for(let i=1;i<=15;i++) {
        await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:200+dx*i/15,y:400}]});
        await page.waitForTimeout(30);
      }
      await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
      await page.waitForTimeout(200);
      const after=await eye(),rotation=Math.atan2(Math.sin(heading(after)-heading(before)),Math.cos(heading(after)-heading(before)));
      if(Math.abs(rotation)<.5||Math.sign(rotation)===Math.sign(dx))throw Error('Finger drag did not rotate the camera in the expected direction');
      results.push({dx,degrees:rotation*180/Math.PI});
      await page.waitForTimeout(300);
      const drift=heading(await eye())-heading(after);
      if(drift<.001||drift>.03)throw Error('Expected slow steady orbit after release, got '+drift);
    }
    return results;
  } finally {
    await cdp.send('Emulation.setTouchEmulationEnabled',{enabled:false});
    await cdp.detach();
  }
}
