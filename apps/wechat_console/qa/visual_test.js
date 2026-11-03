/* Real WXML/WXSS via a DOM adapter. This is layout/demo QA, not WeChat runtime. */
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path');
const assert=require('node:assert/strict');
(async()=>{
  const errors=[],out=__dirname;
  const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
  try{
    const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
    page.on('pageerror',e=>errors.push(e.message));
    await page.goto('file:///'+path.join(out,'preview.html').replace(/\\/g,'/'));await page.waitForTimeout(200);
    assert.equal(await page.evaluate(()=>previewPage.data.demo),true);
    assert.equal(await page.getByText('板内自主导航',{exact:true}).count(),0);
    await page.getByRole('button',{name:'启用本次控制'}).click();await page.waitForTimeout(150);
    assert.equal(await page.evaluate(()=>previewPage.data.armed),true);
    await page.evaluate(()=>previewPage.touchStart({currentTarget:{dataset:{dir:'F'}}}));
    assert.equal(await page.evaluate(()=>previewPage.client.state.direction),'F');
    await page.evaluate(()=>previewPage.touchEnd());assert.equal(await page.evaluate(()=>previewPage.client.state.direction),'S');
    await page.screenshot({path:path.join(out,'drive-phone.png')});
    for(const tab of ['map','vision','connect']){
      await page.evaluate(tab=>previewPage.selectTab({currentTarget:{dataset:{tab}}}),tab);await page.waitForTimeout(150);await page.evaluate(()=>window.scrollTo(0,0));
      assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'horizontal overflow '+tab);
      await page.screenshot({path:path.join(out,tab+'-phone.png')});
    }
    await page.evaluate(()=>previewPage.selectTab({currentTarget:{dataset:{tab:'map'}}}));await page.waitForTimeout(150);
    await page.evaluate(()=>previewPage.send('nav.preview',{goal:[17,17]}));
    assert.ok(await page.evaluate(()=>previewPage.client.state.map.route.length>10));
    await page.evaluate(()=>previewPage.send('nav.start'));await page.waitForTimeout(100);
    await page.evaluate(()=>previewPage.onHide());assert.equal(await page.evaluate(()=>previewPage.client.armed),false);
    await page.evaluate(()=>previewPage.onShow());assert.equal(await page.evaluate(()=>previewPage.client.armed),false);
    // Compact phone: check responsive width on all four tabs.
    await page.setViewportSize({width:320,height:700});
    for(const tab of ['drive','map','vision','connect']){await page.evaluate(tab=>previewPage.selectTab({currentTarget:{dataset:{tab}}}),tab);await page.waitForTimeout(100);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'320px overflow '+tab);}
    assert.deepEqual(errors,[]);console.log('PASS layout: four tabs at 390px and 320px, no horizontal overflow');
    console.log('PASS demo: explicit arm, press/release, route preview, hide/return does not resume');
    fs.writeFileSync(path.join(out,'visual_result.json'),JSON.stringify({scope:'WXML/WXSS DOM-adapter layout and demo only',wechat_runtime_tested:false,physical_phone_tested:false,hardware_connected:false,viewport_widths:[390,320],page_errors:errors,passed:true},null,2));
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
