// A charge-port transition is a one-time camera action. Any real input
// immediately cancels it and returns control to the orbit controller.
export function createChargeCamera({bridge,onState=()=>{}}) {
  const cancel=()=>bridge.cancelCameraTransition();
  const interrupt=event=>{if(event.isTrusted)cancel();};
  document.addEventListener('pointerdown',interrupt,true);
  document.addEventListener('wheel',interrupt,true);
  return {
    focus(point){
      onState('focusing');
      return bridge.focusChargePort(point,state=>onState(state||'charge-port'));
    },
    cancel,
  };
}
