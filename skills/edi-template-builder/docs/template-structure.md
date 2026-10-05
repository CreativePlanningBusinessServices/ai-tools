# Template File Structure

## Contents

- Top-level fields
- Segment rule
- Repetition
- Filter
- Close rule
- Element rule
- Handlebars expressions
- Pathing
- Special properties
- Full annotated example

A template is a JSON file that describes how to serialize input data into an EDI output stream. It defines the separators used between fields, and a list of segment rules that map data properties to output segments and elements.

---

## Top-level fields

```json
{
  "$schema": "...",
  "name": "my-template",
  "version": "0.0.1",
  "elementSeparator": "*",
  "segmentSeparator": "~",
  "componentSeparator": ":",
  "repetitionSeparator": "!",
  "rules": [ ]
}
```

| Field | Type | Description |
|---|---|---|
| `$schema` | string | Optional schema reference. |
| `name` | string | Human-readable name for the template. |
| `version` | string | Serializer version to use. Must be `"0.0.1"`. |
| `elementSeparator` | string | Character written between elements within a segment (e.g. `*`). |
| `segmentSeparator` | string | Character written at the end of each segment (e.g. `~`). |
| `componentSeparator` | string | Character used to separate components within a single element (e.g. `:`). |
| `repetitionSeparator` | string | Character used to separate repeated values within a single element (e.g. `!`). |
| `rules` | array | Ordered list of segment rules. See below. |

---

## Segment rule

Each entry in `rules` (and in any `children` array) is a segment rule. There are two kinds: **standard** segments that write output, and **container** segments that only group children without writing output themselves.

### Standard segment (`container: false`)

```json
{
  "name": "Member_Record",
  "container": false,
  "trim": true,
  "repetition": { "property": "members", "filter": "..." },
  "ignore": "{{#if condition}}true{{/if}}",
  "filter": { "property": "members", "expression": "..." },
  "elements": [ ],
  "children": [ ],
  "closeRule": { }
}
```

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Identifier for this segment. Used for readability only. |
| `container` | Yes | Must be `false`. |
| `elements` | Yes | Ordered list of element rules that form the segment's output. |
| `children` | Yes | Child segment rules rendered after this segment's elements. |
| `trim` | No | When `true`, trailing empty elements are stripped from the output before the segment separator is written. Default: `false`. |
| `repetition` | No | Repeat this segment once per item in an array. See [Repetition](#repetition). |
| `filter` | No | Filter an array property before rendering children. See [Filter](#filter). |
| `ignore` | No | Handlebars expression — if it renders a non-empty string the segment is rendered, otherwise skipped entirely. An empty string value always skips the segment. **Despite the name, this is a render-if-truthy gate, not a skip-if-truthy gate.** To suppress a segment when a condition is true, invert the expression: `{{#unless cond}}true{{/unless}}` keeps the segment only when `cond` is false. To gate a segment on a member of a fixed list (e.g. "only render AMT for plans X, Y, Z"), the natural-reading expression `{{#if (match [Benefit Plan ID] X Y Z)}}true{{/if}}` already does the right thing — it renders for the listed plans and skips the rest. |
| `closeRule` | No | A closing segment written after all children. See [Close rule](#close-rule). |
| `numberOfRowsToSkip` | No | Used by the deserializer to skip leading rows in the input. |

### Container segment (`container: true`)

```json
{
  "name": "Member_Container",
  "container": true,
  "repetition": { "property": "members" },
  "children": [ ]
}
```

A container does not write any elements of its own. It exists purely to scope a `repetition` or `filter` for its children, or to logically group child segments without contributing an output line.

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Identifier for this segment. |
| `container` | Yes | Must be `true`. |
| `children` | Yes | Child segment rules to render. |
| `repetition` | No | Repeat children once per item in an array. |
| `filter` | No | Filter an array before rendering children. |
| `ignore` | No | Same semantics as on a standard segment. |

---

## Repetition

Causes a segment (and its children) to repeat once for each item in an array property of the current input.

```json
"repetition": {
  "property": "members",
  "filter": "{{#compare status '==' 'active'}}true{{/compare}}"
}
```

| Field | Required | Description |
|---|---|---|
| `property` | Yes | Key on the current input object that holds the array to iterate. |
| `filter` | No | Handlebars expression evaluated against each array item. Items that render an empty string are skipped. |

During iteration the current array item becomes the new context, and `_PARENT` is injected onto it pointing back to the outer input. See [Special properties — `_PARENT`](#_parent) below.

---

## Filter

Filters an array property in-place before the segment and its children are rendered, then restores the original array afterwards. Unlike `repetition`, the segment itself is rendered once using the filtered array — the array is not iterated.

```json
"filter": {
  "property": "members",
  "expression": "{{#compare status '==' 'active'}}1{{/compare}}"
}
```

| Field | Required | Description |
|---|---|---|
| `property` | Yes | Key on the current input whose array value will be filtered. |
| `expression` | Yes | Handlebars expression evaluated per item. Items that render an empty string are removed from the array for the duration of this segment's rendering. |

`_PARENT` is injected on each item during the filter step, pointing to the object that owns the array.

---

## Close rule

An optional trailing segment written after all children of a standard segment have been rendered. Commonly used for EDI trailer segments that need a `_segment_count`.

```json
"closeRule": {
  "name": "Trailer",
  "trim": true,
  "elements": [
    { "name": "tag",   "value": "SE" },
    { "name": "count", "value": "{{_segment_count}}" }
  ]
}
```

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Identifier for the close segment. |
| `elements` | Yes | Elements written for the close segment. |
| `trim` | No | Same trimming behaviour as on a standard segment. |

---

## Element rule

An element is a single field within a segment.

```json
{
  "name": "first_name",
  "value": "{{member.firstName}}",
  "attributes": {
    "length": {
      "min": 1,
      "max": 20,
      "padding": "0",
      "align": "right"
    },
    "quoted": true
  }
}
```

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Identifier for this element. Used for readability only. |
| `value` | Yes | Handlebars expression that produces the element's string value. |
| `attributes` | No | Post-processing rules applied after the Handlebars expression is rendered. |

### `attributes.length`

Enforces a minimum and maximum character length on the rendered value.

| Field | Required | Description |
|---|---|---|
| `min` | Yes | Pad the value to at least this many characters. |
| `max` | Yes | Truncate the value to at most this many characters. |
| `padding` | No | Character to pad with. Defaults to a space. Accepts a Handlebars expression. |
| `align` | No | `"left"` (default) pads on the right; `"right"` pads on the left. |

If `quoted: true` is also set, two characters are reserved for the surrounding quotes when computing padding and truncation.

### `attributes.quoted`

When `true`, the rendered value is wrapped in double quotes: `"value"`.

---

## Handlebars expressions

Element `value` strings, `filter` expressions, `repetition` filter expressions, and `ignore` expressions are all full Handlebars templates — not just property references. This means you can embed conditional logic, iteration, string transforms, date formatting, arithmetic, and lookups directly inside any expression field using built-in Handlebars block helpers (`{{#if}}`, `{{#each}}`, `{{#unless}}`) and a set of registered custom helpers. See the helpers reference for full details.

---

## Pathing

All `{{ }}` expressions use [Handlebars](https://handlebarsjs.com/) syntax. The serializer passes the current `input` object as the Handlebars context for each segment, so all paths resolve relative to that object.

### Simple property access

Resolves a top-level key on the current context.

```handlebars
{{invoiceNumber}}
```

### Nested objects — dot notation

Walks down nested objects using `.` as a separator.

```handlebars
{{address.city}}
{{employee.name.last}}
```

### Array element by index — bracket notation

Accesses a specific array element by its zero-based index. The dot before the bracket is required.

```handlebars
{{members.[0].firstname}}
{{lines.[2].amount}}
```

### Dynamic key dereference — `[varName]`

Wrapping a name in brackets tells Handlebars to use the *runtime value* of that expression as the key, rather than treating it as a literal string. This is used when the key to look up is itself a variable.

```handlebars
{{find _PARENT._PARENT.members 'firstname' [_PARENT].[firstname] 'lastname'}}
```

Here `[_PARENT].[firstname]` evaluates `_PARENT.firstname` at runtime and uses that value as the comparison argument passed to `find`.

### Pathing inside helpers — `sum` and `find`

The `sum` and `find` helpers accept a property path as a plain string argument. Internally they walk the path using dot notation, so nested paths work as expected.

```handlebars
{{sum lineItems 'price.amount'}}
```

Sums `price.amount` across every object in the `lineItems` array.

```handlebars
{{find coverages 'plan.code' 'MED' 'plan.name'}}
```

Finds the first element in `coverages` where `plan.code === 'MED'`, then returns its `plan.name`.

### Missing paths

Handlebars returns an empty string `""` for any path that resolves to `undefined` or a missing key — it does not throw an error. Helpers likewise treat a missing path as absent or zero.

### Pathing quick reference

| Syntax | What it does |
|---|---|
| `{{foo}}` | Direct property on current context |
| `{{foo.bar.baz}}` | Nested object traversal |
| `{{arr.[0].name}}` | Array element by zero-based index |
| `[varName]` | Use the runtime value of a variable as a key |
| `'foo.bar'` string in a helper | Dot-notation path walked internally |
| `{{_PARENT.foo}}` | Property on the parent context |
| `{{_PARENT._PARENT.foo}}` | Property two levels up |

---

## Special properties

The serializer injects several properties into the input object at runtime. These are available in element `value` strings, `filter` expressions, and `repetition` filter expressions.

### `_PARENT`

When a segment uses `repetition` or `filter` to iterate over an array of child objects, each child is given a `_PARENT` reference pointing to the object that contains the array. This lets you access fields from an outer scope while rendering a nested segment. `_PARENT` can be chained — `_PARENT._PARENT` walks up another level.

**Example input:**

```json
{
  "header": { "companyName": "Acme Corp" },
  "invoices": [
    {
      "invoiceNumber": "INV-001",
      "lines": [
        { "sku": "A100", "qty": 2 },
        { "sku": "B200", "qty": 5 }
      ]
    }
  ]
}
```

**Example template (abbreviated):**

```json
{
  "name": "invoice_header",
  "repetition": { "property": "invoices" },
  "elements": [
    { "name": "invoice_number", "value": "{{invoiceNumber}}" },
    { "name": "company",        "value": "{{_PARENT.header.companyName}}" }
  ],
  "children": [
    {
      "name": "line_item",
      "repetition": { "property": "lines" },
      "elements": [
        { "name": "sku",            "value": "{{sku}}" },
        { "name": "invoice_number", "value": "{{_PARENT.invoiceNumber}}" },
        { "name": "company",        "value": "{{_PARENT._PARENT.header.companyName}}" }
      ]
    }
  ]
}
```

When rendering a `line_item`:
- `{{sku}}` — current line object
- `{{_PARENT.invoiceNumber}}` — the invoice object one level up
- `{{_PARENT._PARENT.header.companyName}}` — the root input two levels up

**Using `_PARENT` in a repetition filter:**

```json
{
  "name": "line_item",
  "repetition": {
    "property": "lines",
    "filter": "{{#compare _PARENT.invoiceNumber '==' 'INV-001'}}true{{/compare}}"
  },
  "elements": [
    { "name": "sku", "value": "{{sku}}" }
  ]
}
```

### `__TODAY`

The current date string passed into `serialize()`. Injected into the top-level input before rendering begins and accessible anywhere in the template, including deeply nested segments. In practice this is an ISO 8601 string (e.g. `2025-09-15T00:00:00.000Z`).

```json
{ "name": "date", "value": "{{__TODAY}}" }
```

### `_segment_count`

The total number of segments produced by the current serialization pass. Injected just before each segment's elements are rendered, so it reflects the full count including all repetitions. Used in EDI trailer segments.

```json
{ "name": "count", "value": "{{_segment_count}}" }
```

> `_segment_count` includes every non-container segment written, including the trailer segment itself. Verify the expected count for your EDI transaction set, as some specs require the count to exclude certain envelope segments.

---

## Full annotated example

```json
{
  "$schema": "",
  "name": "example-834",
  "version": "0.0.1",
  "elementSeparator": "*",
  "segmentSeparator": "~",
  "componentSeparator": ":",
  "repetitionSeparator": "!",
  "rules": [
    {
      "name": "ISA_Header",
      "container": false,
      "elements": [
        { "name": "tag",   "value": "ISA" },
        { "name": "date",  "value": "{{__TODAY}}" }
      ],
      "children": [
        {
          "name": "Member_Container",
          "container": true,
          "repetition": { "property": "members" },
          "children": [
            {
              "name": "Member_Record",
              "container": false,
              "trim": true,
              "elements": [
                { "name": "tag",       "value": "INS" },
                { "name": "firstname", "value": "{{firstname}}" },
                {
                  "name": "id",
                  "value": "{{memberId}}",
                  "attributes": { "length": { "min": 9, "max": 9, "padding": "0", "align": "right" } }
                }
              ],
              "children": []
            }
          ]
        }
      ],
      "closeRule": {
        "name": "IEA_Trailer",
        "elements": [
          { "name": "tag",   "value": "IEA" },
          { "name": "count", "value": "{{_segment_count}}" }
        ]
      }
    }
  ]
}
```

