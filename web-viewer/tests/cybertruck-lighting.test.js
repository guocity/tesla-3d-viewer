import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createShowroomAnimation } from '../src/showroom-animation.js';

test('Cybertruck defaults to DRL and swaps running/brake emitters without overlap', () => {
  const previous={document:globalThis.document,requestAnimationFrame:globalThis.requestAnimationFrame,cancelAnimationFrame:globalThis.cancelAnimationFrame};
  const element=()=>({dataset:{},children:[],attributes:{},append(c){this.children.push(c);},replaceChildren(){this.children=[];},setAttribute(k,v){this.attributes[k]=v;}});
  const list=element();
  globalThis.document={hidden:false,createElement:element};globalThis.requestAnimationFrame=()=>1;globalThis.cancelAnimationFrame=()=>{};
  try {
    const names=['DRL2','Headlights_Trunk2','Brake_Lights_Trunk2','Brake_Lights_Left2','Brake_Lights_Right2','DRL_Rear_Left2','DRL_Rear_Right2','Left_Turn_Signal_Front2','Right_Turn_Signal_Front2','Headlights_Side_Left2','Headlights_Side_Right2'];
    const identity=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
    const rest=new Uint8Array(names.length*20);for(let i=0;i<names.length;i++)new DataView(rest.buffer).setInt16(i*20,10000,true);
    const part={name:'LightRed',rest,current:rest.slice()};
    const controller=createShowroomAnimation({ready:true,upload(){},reset(){}},{dataset:{},querySelector:s=>s==='.motion-switches'?list:element()});
    controller.bind({normalize:identity,quant:[1,1,1],nodes:names.map(name=>({name,parent:-1,matrix:identity})),segments:names.map((_,node)=>({node,material:'LightRed',first:node,count:1})),animations:[]},[part]);
    const drl=list.children.find(b=>b.dataset.clip==='DRLAnimation');
    const brake=list.children.find(b=>b.dataset.clip==='BrakeLightsAnimation');
    const visible=()=>{controller.refresh();return names.map((_,i)=>new DataView(part.current.buffer).getInt16(i*20,true)!==0);};
    assert.deepEqual(visible(),[true,true,false,false,false,true,true,false,false,false,false]);
    brake.onclick();assert.deepEqual(visible(),[false,false,true,true,true,false,false,false,false,false,false]);
    assert.equal(drl.attributes['aria-checked'],'false');assert.equal(brake.attributes['aria-checked'],'true');
    drl.onclick();assert.deepEqual(visible(),[true,true,false,false,false,true,true,false,false,false,false]);
    drl.onclick();assert.deepEqual(visible(),[false,false,true,true,true,false,false,false,false,false,false]);
    controller.dispose();
  } finally {Object.assign(globalThis,previous);}
});
