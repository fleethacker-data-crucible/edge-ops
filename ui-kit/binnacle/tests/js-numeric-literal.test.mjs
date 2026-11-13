import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { jsNumericLiteral } from './js-numeric-literal.mjs';

const NUMERIC_LITERAL = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:e[+-]?\d+)?$/;

test('jsNumericLiteral round-trips through a JavaScript expression', () => {
  const values = [0, 1, -1, 118, 1.5, -112.25, 0.1, 1e-7, 1e21, Number.MIN_VALUE, Number.MAX_VALUE, Math.PI];
  for (const value of values) {
    const literal = jsNumericLiteral(value);
    assert.match(literal, NUMERIC_LITERAL);
    const evaluated = Function(`"use strict"; return (${literal});`)();
    assert.equal(evaluated, value);
  }
});

test('negative zero stringifies as 0', () => {
  assert.equal(jsNumericLiteral(-0), '0');
});

test('jsNumericLiteral rejects values that are not finite numbers', () => {
  const rejected = [NaN, Infinity, -Infinity, '1', '1);alert(1)', '0);alert(1)//', {}, null, undefined, true, Object(1)];
  for (const value of rejected) {
    assert.throws(() => jsNumericLiteral(value), TypeError);
  }
});

test('click-through check does not embed JSON.stringify in evaluated code', () => {
  const src = readFileSync(new URL('./browser-check.mjs', import.meta.url), 'utf8');
  const start = src.indexOf('page clicks pass through');
  const end = src.indexOf('// keyboard');
  assert.ok(start !== -1 && end > start);
  const block = src.slice(start, end);
  assert.equal(block.includes('JSON.stringify'), false);
  assert.match(block, /jsNumericLiteral\(b\.x\)/);
  assert.match(block, /const c=\{x:\$\{jsNumericLiteral\(b\.x\)\},y:\$\{jsNumericLiteral\(b\.y\)\}\}/);
});
