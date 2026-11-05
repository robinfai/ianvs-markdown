import {transformSync} from '@babel/core';
export function instrument(source) {
let checkpoints=0;
const instrumented=transformSync(source,{configFile:false,babelrc:false,plugins:[({types:t})=>({visitor:{
 Function(p){
  if (!t.isBlockStatement(p.node.body)) p.node.body=t.blockStatement([t.returnStatement(p.node.body)]);
  p.node.body.body.unshift(t.expressionStatement(t.callExpression(t.identifier('__linefoldBudget'),[])));checkpoints++;
 },
 Loop(p){
  if (!t.isBlockStatement(p.node.body)) p.node.body=t.blockStatement([p.node.body]);
  p.node.body.body.unshift(t.expressionStatement(t.callExpression(t.identifier('__linefoldBudget'),[])));checkpoints++;
 },
 CatchClause(p){p.node.body.body.unshift(t.expressionStatement(t.callExpression(t.identifier('__linefoldNativeCheck'),[])));checkpoints++;}
}})]}).code;
// Native cancellation is polled at most every 128 instrumented JS steps. An
// individual native JS builtin (e.g. RegExp) remains non-preemptible via public API.
const guard='var __linefoldTicks=0;function __linefoldBudget(){if((++__linefoldTicks&127)===0)__linefoldNativeCheck();}\n';
return {code:guard+instrumented,checkpoints};
}
