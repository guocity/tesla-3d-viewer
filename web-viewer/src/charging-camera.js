// A charge-port transition is a one-time camera action. Any real input
// immediately cancels it and returns control to the orbit controller.
export function createChargeCamera({bridge,getInstance,onState=()=>{}}) {
  const cancel=()=>bridge.cancelCameraTransition?.();
  const interrupt=event=>{if(event.isTrusted)cancel();};
  document.addEventListener('pointerdown',interrupt,true);
  document.addEventListener('wheel',interrupt,true);
  return {
    focus(point){
      if (!bridge.focusChargePort) return Promise.resolve('unavailable');
      onState('focusing');
      return new Promise(resolve=>{
        const started=bridge.focusChargePort(point,state=>{onState(state||'charge-port');resolve(state||'charge-port');},getInstance?.());
        if(!started){onState('free');resolve('unavailable');}
      });
    },
    cancel,
  };
}
