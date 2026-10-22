// The authored N shortcut belongs to Garage's first keyboard focus target.
// HTML controls take focus away from Rive; keyInput silently ignores N without
// this target even when the state machine is loaded and playing.
export function toggleSceneAppearance(instance) {
  const machine = instance?.animator?.stateMachines.find(m => m.stateMachine.name === 'Garage')?.instance;
  if (!machine || !machine.hasFocusNodes()) return false;
  machine.clearFocus();
  if (!machine.focusNext()) return false;
  let accepted = false;
  try {
    // Clear a stale held key, then deliver a fresh press across an advance.
    machine.keyInput(78, 0, false, false);
    machine.advanceAndApply(1 / 60);
    accepted = machine.keyInput(78, 0, true, false);
    machine.advanceAndApply(1 / 60);
  } finally {
    machine.keyInput(78, 0, false, false);
    machine.advanceAndApply(1 / 60);
    machine.clearFocus();
  }
  instance.play('Garage');
  return accepted;
}
