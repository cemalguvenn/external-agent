# parseDimensions(input)

Players type parcel sizes into the cargo-fit game's level editor. Implement
`parseDimensions` in `src/parseDims.js` and add tests in `test/parseDims.test.js`
(Node's built-in `node:test`, no dependencies). Run tests with `npm test`.

Return `{ length, width, height }` in **whole millimetres** (rounded to nearest).

Accepted input:
- Three numbers separated by `x`, `X` or `×`, optional spaces around separators.
- A unit after the numbers, optional space before it: `mm`, `cm` or `m`,
  case-insensitive (`CM`, `Cm` are fine).
- Decimal separator may be `.` or `,` (Turkish players write `1,2x0,8x0,6 m`).
- Leading/trailing whitespace is ignored.

Examples:
- `"120x80x60 cm"` → `{ length: 1200, width: 800, height: 600 }`
- `"1,2 × 0,8 × 0,6m"` → `{ length: 1200, width: 800, height: 600 }`
- `"300X200X150MM"` → `{ length: 300, width: 200, height: 150 }`
- `"10.25x1x1 cm"` → `{ length: 103, width: 10, height: 10 }`

Throw an `Error` (any message) for:
- a missing or unknown unit (`"10x10x10"`, `"10x10x10 in"`)
- anything other than exactly three numbers (`"10x10 cm"`, `"1x2x3x4 cm"`)
- zero or negative values, or values that round to 0 mm (`"0x1x1 cm"`, `"0.04x1x1 mm"`)
- non-numeric parts (`"ax1x1 cm"`, `"1e3x1x1 cm"`, `""`)
- a non-string argument
