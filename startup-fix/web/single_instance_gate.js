(function (root) {
'use strict';
// Hold one Godot userfs writer for the complete engine lifetime.
// One stable resource name across paths, query strings and game revisions.
const SAVE_LOCK = 'godot-game:exclusive-userfs:/userfs';

function createSingleInstanceGate({
  locks, secure, start, onState = () => {}, lockName = SAVE_LOCK,
}) {
  let phase = 'idle';
  let outcome = null;
  const notify = (next, detail) => {
    phase = next;
    // Presentation exceptions must never unwind the lock-holding callback.
    try { onState(next, detail); } catch (_) { /* Keep the safety boundary. */ }
  };

  function requestStart() {
    if (!['idle', 'blocked'].includes(phase)) return outcome;
    let finishOutcome;
    outcome = new Promise(resolve => { finishOutcome = resolve; });
    const result = code => finishOutcome({ code });
    notify('checking');
    if (!secure || !locks || typeof locks.request !== 'function') {
      notify('unsupported');
      result('unsupported');
      return outcome;
    }
    let acquired = false;
    try {
      const released = locks.request(lockName,
        { mode: 'exclusive', ifAvailable: true }, lock => {
          if (!lock) {
            notify('blocked');
            result('blocked');
            return;
          }
          acquired = true;
          let exited = false;
          let releaseAfterExit;
          const lifetime = new Promise(resolve => { releaseAfterExit = resolve; });
          // Only the trusted engine onExit callback can release this promise.
          // No UI button, visibility event, elapsed timer, or failure does so.
          const onExit = code => {
            if (exited) return;
            exited = true;
            notify('exited', code);
            result('exited');
            releaseAfterExit();
          };
          const failed = error => {
            if (exited) return;
            // Startup may already have mounted IDBFS or spawned engine work.
            // Without an onExit receipt, reload/close is the safe recovery.
            notify('failed-held', error);
            result('failed-held');
          };
          notify('starting');
          try {
            Promise.resolve(start({ onExit })).then(() => {
              if (exited) return;
              notify('running');
              result('started');
            }, failed);
          } catch (error) { failed(error); }
          // startGame resolves at startup, not shutdown. Hold separately.
          return lifetime;
        });
      Promise.resolve(released).catch(error => {
        // Never retry by starting unlocked. This should be unreachable after
        // acquisition unless some other same-origin code uses unsafe steal.
        notify(acquired ? 'lock-lost' : 'unavailable', error);
        result(acquired ? 'lock-lost' : 'unavailable');
      });
    } catch (error) {
      notify('unavailable', error);
      result('unavailable');
    }
    return outcome;
  }

  return { requestStart, get phase() { return phase; } };
}

const api = Object.freeze({ SAVE_LOCK, createSingleInstanceGate });
if (typeof module === 'object' && module.exports) module.exports = api;
else root.GodotSingleInstance = api;
}(globalThis));
