// Run with: playwright-cli -s=viewer-check run-code "$(cat scripts/check-viewer.browser.js)"
// The browser must already be open on the local viewer.
async page => {
  const url = new URL(page.url());
  url.search = '?vehicle=cybertruck';
  await page.setViewportSize({width:1100,height:760});
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
  await page.locator('.showroom-motion [data-close]').click();
  await page.locator('.tesla-charge-hotspot').click({force:true});
  await page.waitForFunction(()=>document.querySelector('.tesla-charge-hotspot').dataset.connection==='1.000',null,{timeout:15000});
  await page.screenshot({path:'evidence/cybertruck-charging-verified.png',scale:'css'});
  await page.locator('.tesla-charge-hotspot').click({force:true});
  await page.waitForFunction(()=>{const s=document.querySelector('.tesla-charge-hotspot').dataset;return s.connection==='0.000'&&s.portOpen==='0.000';},null,{timeout:15000});
  await page.locator('.model-trigger').click();
  const images=await page.locator('.model-thumbnail img').evaluateAll(imgs=>imgs.map(i=>({loaded:i.complete&&i.naturalWidth>=480,src:i.getAttribute('src')})));
  if(images.length!==12 || images.some(i=>!i.loaded))throw Error('Vehicle studio thumbnails failed to load');
  await page.screenshot({path:'evidence/vehicle-picker-studio-verified.png',scale:'css'});
  return {appearance:results,nightPreservedAcrossVehicleChange:true,charging:'connected and disconnected',roofBar:'off by default',studioImages:images.length};
}
