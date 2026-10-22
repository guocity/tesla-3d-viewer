// Run against a running viewer: playwright-cli -s=mobile-check run-code "$(cat scripts/check-mobile.browser.js)"
async page => {
  const context=page.context(), mobile=page, previousViewport=page.viewportSize();
  const cdp=await context.newCDPSession(mobile);
  await cdp.send('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:5});
  async function viewport(width,height){
    await mobile.setViewportSize({width,height});
    await cdp.send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:2,mobile:true});
  }
  async function tap(locator){
    await locator.scrollIntoViewIfNeeded();const r=await locator.boundingBox();
    if(!r)throw Error('Missing mobile touch target');
    const x=r.x+r.width/2,y=r.y+r.height/2;
    await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});
    await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  }
  const results=[];
  try {
    await mobile.bringToFront();
    const base=page.url().startsWith('http')?new URL(page.url()):new URL('http://127.0.0.1:5174/');base.search='?vehicle=cybertruck';
    await mobile.goto(base.href,{waitUntil:'domcontentloaded'});
    await mobile.locator('.scene-appearance:not(:disabled)').waitFor({timeout:30000});

    async function swipe(x,y,dx,dy) {
      await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});
      for(let step=1;step<=10;step++){await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:x+dx*step/10,y:y+dy*step/10}]});await mobile.waitForTimeout(25);}
      await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    }
    async function bounds(selector) {
      const bad=await mobile.locator(selector).evaluateAll(elements=>elements.filter(e=>e.getBoundingClientRect().width>0).flatMap(e=>{
        const r=e.getBoundingClientRect();return r.left<-.5||r.right>innerWidth+.5||r.top<-.5||r.bottom>innerHeight+.5?[`${e.className}: ${JSON.stringify(r.toJSON())}`]:[];
      }));
      if(bad.length)throw Error('Off-screen mobile UI: '+bad.join(';'));
    }
    for(const [width,height] of [[320,568],[360,800],[390,844],[430,932],[844,390],[768,1024]]) {
      await viewport(width,height);
      await mobile.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
      await bounds('.vehicle-selector,.tesla-bottom,.tesla-bottom button,.model-trigger');
      const bar=await mobile.locator('.tesla-bottom button').evaluateAll(buttons=>buttons.filter(b=>b.getBoundingClientRect().width>0).map(b=>({label:b.getAttribute('aria-label'),r:b.getBoundingClientRect().toJSON()})));
      if(bar.length!==4)throw Error(`Expected one row of four functional mobile buttons, got ${bar.length}`);
      if(bar.some(b=>b.r.height<44||b.r.width<44)||Math.max(...bar.map(b=>b.r.y+b.r.height/2))-Math.min(...bar.map(b=>b.r.y+b.r.height/2))>2)throw Error(`Mobile toolbar ${width}x${height}: ${JSON.stringify(bar)}`);
      await tap(mobile.locator('.model-trigger'));
      await bounds('.model-menu');
      if(await mobile.locator('input:not([readonly])').count())throw Error('Viewer must not open the keyboard');
      const list=await mobile.locator('.model-options').boundingBox();
      await swipe(list.x+list.width/2,list.y+list.height-8,0,-Math.max(20,list.height-16));
      if(await mobile.locator('.model-options').evaluate(e=>e.scrollTop)<=0)throw Error('Car list did not scroll by touch');
      await tap(mobile.locator('.model-close'));
      await tap(mobile.locator('#animation-mode'));
      await bounds('.showroom-motion');
      await tap(mobile.locator('[data-clip="RoofLightbarAnimation"]'));
      if(await mobile.locator('[data-clip="RoofLightbarAnimation"]').getAttribute('aria-checked')!=='true')throw Error('Mobile vehicle switch failed');
      await tap(mobile.locator('[data-clip="RoofLightbarAnimation"]'));
      await tap(mobile.locator('.showroom-motion [data-close]'));
      const quality=mobile.locator('[data-settings]'), previous=await quality.textContent();
      await tap(quality);
      if(await quality.textContent()===previous||await mobile.locator('.tesla-display-settings').count())throw Error('Quality must toggle directly without a popup');
      await tap(quality);
      results.push(`${width}x${height}: layout, one-row toolbar, touch menus, no keyboard, scroll, controls`);
    }
    await viewport(390,844);
    await tap(mobile.locator('.scene-appearance'));
    if(await mobile.locator('.scene-appearance').getAttribute('aria-pressed')!=='true')throw Error('Touch day/night failed');
    await tap(mobile.locator('.scene-appearance'));
    const hotspot=mobile.locator('.tesla-charge-hotspot');
    await tap(hotspot);
    await mobile.waitForFunction(()=>document.querySelector('.tesla-charge-hotspot').dataset.connection==='1.000',null,{timeout:15000});
    await mobile.waitForFunction(()=>document.querySelector('.tesla-charge-hotspot').dataset.view==='charge-port');
    const eye=async()=>JSON.parse(await hotspot.getAttribute('data-camera-eye'));
    const moved=(a,b)=>Math.hypot(...a.map((v,i)=>v-b[i]))>.3;
    let before=await eye();
    await mobile.screenshot({path:'evidence/mobile-charging-full-cable.png',scale:'css'});
    before=await eye();
    await swipe(160,400,70,-30);
    await mobile.waitForTimeout(150);
    if(!moved(before,await eye()))throw Error('Native canvas touch drag did not rotate the car');
    await tap(hotspot);
    await mobile.waitForFunction(()=>{const d=document.querySelector('.tesla-charge-hotspot').dataset;return d.connection==='0.000'&&d.portOpen==='0.000';},null,{timeout:15000});
    await mobile.screenshot({path:'evidence/mobile-phone-verified.png',scale:'css'});
    await tap(mobile.locator('.model-trigger'));await mobile.screenshot({path:'evidence/mobile-menu-verified.png',scale:'css'});

    return {screens:results,touch:'toolbar charging tap, canvas rotation, disconnect, quality toggle, and day/night passed'};
  } finally {
    await cdp.send('Emulation.setTouchEmulationEnabled',{enabled:false});
    await cdp.send('Emulation.clearDeviceMetricsOverride');
    await cdp.detach();
    if(previousViewport)await mobile.setViewportSize(previousViewport);
  }
}
