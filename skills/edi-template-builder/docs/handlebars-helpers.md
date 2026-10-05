# Handlebars helpers available in editester templates

## Contents

- Comparison and control flow
- Strings
- Numbers and arithmetic
- Dates
- Lookups
- Identifier formatters
- Length and quoting (element attributes, not helpers)
- Special properties injected at runtime
- Quick pattern reference

Every `value`, `filter.expression`, `repetition.filter`, and `ignore` field in a template is a full Handlebars template. The serializer registers the helpers below in addition to Handlebars' built-in block helpers (`{{#if}}`, `{{#unless}}`, `{{#each}}`, `{{#with}}`).

All helpers tolerate missing inputs — a missing path renders `""` and is treated as zero/absent inside numeric and array helpers.

---

## Comparison and control flow

### `{{#compare a operator b}}...{{else}}...{{/compare}}`

Block helper. String comparison.

| arg | values |
|---|---|
| `operator` | `==`, `!=`, `>=`, `<=` |

```handlebars
{{#compare "Relationship Code" '==' 'Self'}}true{{/compare}}
```

In a `repetition.filter` or `filter.expression`, emit a non-empty string (e.g. `"true"`, `"1"`) to keep an item, empty string to drop it.

### `{{#dateCompare key operator input}}...{{else}}...{{/dateCompare}}`

Block helper. Compares two dates.

`key` is either one of `lastweek`, `yesterday`, `today`, or any ISO/parseable date string. `input` is the other date to compare against. `operator` is `==`, `!=`, `<`, `<=`, `>`, `>=`.

```handlebars
{{#dateCompare "Member Benefit End Date" '>=' __TODAY}}1{{/dateCompare}}
```

### `{{and a b}}` / `{{or a b}}` / `{{not a}}`

Boolean helpers. Truthy/falsy following JavaScript semantics (empty string is falsy).

---

## Strings

### `{{replace match replacement value}}`

Single regex replacement.

```handlebars
{{replace "^0+" "" "0001234"}}
```

### `{{replaceAll match replacement value}}`

Global regex replacement.

```handlebars
{{replaceAll "[^A-Z0-9]" "" (toUpper "abc-def")}}
```

### `{{match value option1 option2 ...}}`

Returns the matching option string if `value` is one of the listed options, otherwise empty string. Useful for one-of-N validation.

```handlebars
{{match "Members Gender" "M" "F" "U"}}
```

### `{{matchArray value array}}`

Same as `match` but takes a single array argument.

### `{{toUpper value}}` / `{{toLower value}}`

Case conversion.

### `{{#length}}some content{{/length}}`

Block helper. Renders the character length of the block contents.

---

## Numbers and arithmetic

### `{{add a b}}` / `{{sub a b}}` / `{{mul a b}}` / `{{div a b}}`

Basic arithmetic. Non-numeric inputs are treated as `0`. Division by zero returns `0`.

### `{{sum array property?}}`

Reduces an array to a numeric sum. With a property argument, walks each element via dot notation to find the value to sum.

```handlebars
{{sum "Benefit Plans" "Coverage Amount"}}
```

### `{{numberFormat preference precision value}}`

Format a number as a fixed-precision decimal.

| arg | values |
|---|---|
| `preference` | `'dot'` (keeps decimal point) or `'nodot'` (strips it for implied decimals) |
| `precision` | integer 0–20 |

```handlebars
{{numberFormat 'dot' '2' "Coverage Amount"}}    {{!-- 1234.56 --}}
{{numberFormat 'nodot' '2' "Coverage Amount"}}  {{!-- 123456 --}}
```

**Zero gotcha:** a value of `0` (or a missing path) renders an **empty string**,
not `0.00`. When the spec requires explicit zeros, wrap it:

```handlebars
{{#if [Employee Amount]}}{{numberFormat 'dot' 2 [Employee Amount]}}{{else}}0.00{{/if}}
```

`'dot'` does not emit thousands separators (`1234.56`, not `1,234.56`) — safe
for fixed-format currency fields. Negative values keep their minus sign
(`-38.00`).

---

## Dates

All date helpers internally produce a `UTCDate`. If `input` is empty/missing, the date helpers default to "now" (UTC).

### `{{dateFormat formatString input? inputFormat?}}`

Format a date using [date-fns format tokens](https://date-fns.org/docs/format). With `inputFormat`, parses the input string using that format.

```handlebars
{{dateFormat 'yyyyMMdd' "Members Date of Birth"}}
{{dateFormat 'yyMMdd' __TODAY}}
```

### `{{getDate mode period unit input? inputFormat?}}`

Returns a calendar boundary date, formatted `MM/dd/yyyy`.

| arg | values |
|---|---|
| `mode` | `start`, `end` |
| `period` | `previous`, `current`, `next` |
| `unit` | `day`, `week`, `month`, `year` |

```handlebars
{{getDate 'start' 'current' 'month' __TODAY}}    {{!-- first day of this month --}}
{{getDate 'end' 'next' 'year'    __TODAY}}       {{!-- last day of next year --}}
```

### `{{getDayOfMonth day input? inputFormat?}}`

Returns the input month with the day-of-month replaced by `day` (1–31), formatted `MM/dd/yyyy`.

```handlebars
{{getDayOfMonth '15' __TODAY}}
```

---

## Lookups

### `{{find array arrProp compareValue prop}}`

Walks `array`, finds the first element where `arrProp` (dot-notation path) equals `compareValue`, then returns `prop` (dot-notation path) of that element. Returns `""` if not found.

```handlebars
{{find "Benefit Plans" "Benefit Plan Name" "Dental" "Coverage Name"}}
```

With `_PARENT`, you can cross-reference between sibling records:

```handlebars
{{find _PARENT._PARENT.members 'firstname' [_PARENT].[firstname] 'lastname'}}
```

---

## Identifier formatters

### `{{ssnFormat key ssn}}`

Format a Social Security Number.

| `key` | output |
|---|---|
| `'dash'` | `123-45-6789` |
| `'nodash'` | `123456789` |

Accepts either 9-digit or `xxx-xx-xxxx` input. Empty/non-string input renders `""`.

### `{{phoneFormat key phone}}`

Format a phone number — strips a leading `+1` and removes everything that isn't a digit (or a dash, with `'dash'`).

| `key` | output |
|---|---|
| `'dash'` | `555-123-4567` (digits + dashes only) |
| `'nodash'` | `5551234567` (digits only) |

---

## Length and quoting (element attributes, not helpers)

These are applied **after** the Handlebars expression renders, via `element.attributes`:

```json
{
  "name": "ssn",
  "value": "{{ssnFormat 'nodash' \"SSN of Member\"}}",
  "attributes": {
    "length": { "min": 9, "max": 9, "padding": "0", "align": "right" },
    "quoted": false
  }
}
```

`padding` is itself a Handlebars expression (so e.g. `"padding": "{{#if foo}} {{else}}0{{/if}}"` is legal). `align: "right"` pads on the left (right-aligns the value). `quoted: true` wraps in `"…"` and reserves two characters from `max` for the quotes.

---

## Special properties injected at runtime

- `__TODAY` — ISO-8601 date string passed via `--today` (or current date). Available everywhere.
- `_PARENT` — within a `repetition` or `filter`, points to the object that owns the iterated array. Chains: `_PARENT._PARENT`.
- `_segment_count` — running count of segments produced so far. Use in `closeRule` elements for SE/GE/IEA trailer counts.

---

## Quick pattern reference

**Filter members who are "Self":**
```json
"repetition": {
  "property": "data",
  "filter": "{{#compare \"Relationship Code\" '==' 'Self'}}1{{/compare}}"
}
```

**Skip waived coverages inside a benefit-plan loop:**
```json
"repetition": {
  "property": "Benefit Plans",
  "filter": "{{#compare \"Coverage Name\" '!=' 'Waived'}}1{{/compare}}"
}
```

**Coverage end is in the future:**
```json
"filter": "{{#dateCompare \"Member Benefit End Date\" '>=' __TODAY}}1{{/dateCompare}}"
```

**Sum total coverage across plans:**
```handlebars
{{sum "Benefit Plans" "Coverage Amount"}}
```

**SE trailer with segment count:**
```json
"closeRule": {
  "name": "SE",
  "elements": [
    { "name": "tag",   "value": "SE" },
    { "name": "count", "value": "{{_segment_count}}" },
    { "name": "ctrl",  "value": "0001" }
  ]
}
```
