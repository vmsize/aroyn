import assert from 'node:assert/strict';
import {newRetentionCycle,retentionStep} from '../workers/shared/retention-runner.js';
export async function drainRetention(env,now,{maxSteps=300}={}) {
  let state=newRetentionCycle(now);
  for(let i=0;state.active&&i<maxSteps;i++)state=await retentionStep(env,state);
  assert.equal(state.active,false,'bounded cleanup eventually finishes');
  return state;
}
