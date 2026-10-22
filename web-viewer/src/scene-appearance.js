// Deliver the authored N command across an advance boundary. Sending down and
// up in the same frame loses the press before the Garage script samples it.
export function toggleSceneAppearance(instance) {
  const machine = instance?.animator?.stateMachines.find(m => m.stateMachine.name === 'Garage')?.instance;
  if (!machine) return false;
  const handled = machine.keyInput(78, 0, true, false);
  try {
    machine.advanceAndApply(1 / 60);
  } finally {
    machine.keyInput(78, 0, false, false);
  }
  instance.play('Garage');
  return handled;
}
