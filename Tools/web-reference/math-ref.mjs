// Reference values for webMathMatchesOriginal: runs the original math.ts (89a7721) under node.
// Usage, from inside the patched clone: node <this dir>/math-ref.mjs
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
// Run from inside the patched ascii-spiders clone: its sources are ./src.
const src = (f) => pathToFileURL(resolve("src", f)).href;
const M = await import(src("math.ts"));
const show = (k, v) => console.log(k.padEnd(34), Object.is(v, -0) ? "-0" : v.toPrecision(17));
show("hash3(1,2,3)", M.hash3(1, 2, 3));
show("hash3(-7,123456,91)", M.hash3(-7, 123456, 91));
show("hash3(3.9,-2.5,5e9)", M.hash3(3.9, -2.5, 5e9));
show("noise1(0.5)", M.noise1(0.5));
show("noise1(12.34,7)", M.noise1(12.34, 7));
show("noise1(-3.3,123.7)", M.noise1(-3.3, 123.7));
show("angleDiff(3,-3)", M.angleDiff(3, -3));
show("angleDiff(-3,3)", M.angleDiff(-3, 3));
show("angleDiff(0.5,20)", M.angleDiff(0.5, 20));
show("closestT(5,5,0,0,10,0)", M.closestT(5, 5, 0, 0, 10, 0));
show("closestT(3,7,1,2,9,4)", M.closestT(3, 7, 1, 2, 9, 4));
show("closestT(-4,1,1,2,9,4)", M.closestT(-4, 1, 1, 2, 9, 4));
show("crossAlong(0,0,10,10,0,10,10,0)", M.crossAlong(0, 0, 10, 10, 0, 10, 10, 0));
show("crossAlong(1,2,7,9,0,8,12,1)", M.crossAlong(1, 2, 7, 9, 0, 8, 12, 1));
show("crossAlong(0,0,1,0,0,1,1,1)", M.crossAlong(0, 0, 1, 0, 0, 1, 1, 1));
show("smoothstep(0.2,0.8,0.35)", M.smoothstep(0.2, 0.8, 0.35));
show("ease(0.3)", M.ease(0.3));
show("easeOut(0.3)", M.easeOut(0.3));
show("lerp(2,9,0.25)", M.lerp(2, 9, 0.25));
show("clamp(5,0,3)", M.clamp(5, 0, 3));
