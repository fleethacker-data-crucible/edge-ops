// A finite number as a JavaScript numeric literal for Runtime.evaluate.
// String() on a finite number is always that literal, so it cannot close the
// surrounding expression. JSON.stringify is not a substitute: it leaves
// U+2028, U+2029, and "<" unescaped.

const NUMERIC_LITERAL = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:e[+-]?\d+)?$/;

export function jsNumericLiteral(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new TypeError('expected a finite number');
  }
  const literal = String(value);
  if (!NUMERIC_LITERAL.test(literal)) {
    throw new TypeError('number is not a JavaScript numeric literal');
  }
  return literal;
}
