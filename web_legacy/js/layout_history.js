window.SLIME = window.SLIME || {};

(() => {
  function createLayoutHistory(limit = 120) {
    const state = {
      past: [],
      future: []
    };

    return {
      clear() {
        state.past = [];
        state.future = [];
      },
      canUndo() {
        return state.past.length > 0;
      },
      canRedo() {
        return state.future.length > 0;
      },
      push(beforeSnapshot) {
        state.past.push(beforeSnapshot);
        if (state.past.length > limit) {
          state.past.shift();
        }
        state.future = [];
      },
      undo(currentSnapshot) {
        if (state.past.length === 0) {
          return null;
        }
        const previous = state.past.pop();
        state.future.push(currentSnapshot);
        return previous;
      },
      redo(currentSnapshot) {
        if (state.future.length === 0) {
          return null;
        }
        const next = state.future.pop();
        state.past.push(currentSnapshot);
        if (state.past.length > limit) {
          state.past.shift();
        }
        return next;
      }
    };
  }

  window.SLIME.createLayoutHistory = createLayoutHistory;
})();
