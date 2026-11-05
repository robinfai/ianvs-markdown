import {instrument} from './instrument.mjs';
// Use exactly the production transform; no manually inserted checkpoints.
console.log(instrument(`
function spin() { for (;;) { try { (() => { while (true) {} })(); } catch (e) {} } }
spin();
`).code);
