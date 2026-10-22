// These are distinct authored emitter meshes, including two overlapping strips
// across the tailgate. Only one rear-light mode may be visible at a time.
export function cybertruckLampClips(nodes) {
  if (!nodes.some(n => n.name === 'Brake_Lights_Trunk2') || !nodes.some(n => n.name === 'Headlights_Trunk2')) return [];
  return [
    { name:'DRLAnimation', defaultOn:true, meshes:['DRL2','Headlights_Trunk2','DRL_Rear_Left2','DRL_Rear_Right2'] },
    { name:'LeftSignalAnimation', defaultOn:false, blink:true, meshes:['Left_Turn_Signal_Front2'] },
    { name:'RightSignalAnimation', defaultOn:false, blink:true, meshes:['Right_Turn_Signal_Front2'] },
    { name:'FrontSignalOverlaysAnimation', defaultOn:false, hiddenControl:true, meshes:['Headlights_Side_Left2','Headlights_Side_Right2'] },
    { name:'BrakeLightsAnimation', defaultOn:false, meshes:['Brake_Lights_Trunk2','Brake_Lights_Left2','Brake_Lights_Right2'] },
  ].map(({meshes,...mode}) => ({
    ...mode, exclusiveGroup:['DRLAnimation','BrakeLightsAnimation'].includes(mode.name)?'cybertruck-rear-lights':undefined, duration:1, alwaysApply:true,
    tracks:nodes.filter(n=>meshes.includes(n.name)).map(n=>({
      target:`${n.name}:scale`, type:'value', interpolation:1,
      times:[0,1], values:[[0,0,0],n.restS.toArray()],
    })),
  }));
}
