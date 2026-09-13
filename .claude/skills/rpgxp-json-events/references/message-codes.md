# Message text codes (Pokémon Essentials)

From `pbMessageDisplay` in
`Data/Scripts/007_Objects and windows/011_Messages.rb`.

**In JSON every backslash must be doubled**: in-game `\b` is written `"\\b"`,
`\v[1]` is `"\\v[1]"`. A literal `"\n"` in JSON is a real newline character and
is *not* the `\n` message code.

## Substitutions

| Code | Effect |
|---|---|
| `\\PN` | Player's name |
| `\\PM` | Player's money |
| `\\v[n]` | Value of game variable *n* (resolved repeatedly, so nesting works) |
| `\\n[1-8]` | Actor *n*'s name |
| `\\n` | Line break |
| `\\\\` | A literal backslash |

## Colour and style

| Code | Effect |
|---|---|
| `\\b` | Male/blue text colour |
| `\\r` | Female/red text colour |
| `\\pg` | `\b` if the player is male, `\r` if female |
| `\\pog` | The opposite - `\r` if the player is male, `\b` if female |
| `\\c[n]` | Windowskin colour *n* |
| `\\[RRGGBBAA]` | Explicit 8-hex-digit colour |
| `\\w[skin]` | Switch windowskin to `Graphics/Windowskins/skin`; `\w[]` resets |
| `\\sign[x]` | Sign-style box - expands to `\op\cl\ts[]\w[x]` |
| `\\l[n]` | Force the window to *n* lines |

`\b` at the start of a line is the convention in this project for ordinary NPC
speech. Signs typically use `\\w[signskin]`.

## Pausing, timing, input

| Code | Effect |
|---|---|
| `\\.` | Pause 0.25s |
| `\\\|` | Pause 1s |
| `\\wt[n]` | Wait *n*/20 seconds, then continue |
| `\\wtnp[n]` | Wait *n*/20 seconds, then close with **no** keypress |
| `\\^` | Close the message with no keypress |
| `\\!` | Wait for a keypress here |
| `\\wu` / `\\wd` / `\\wm` | Window up / down / middle |
| `\\op` / `\\cl` | Open / close the window |
| `\\g` | Show the gold window |
| `\\cn` / `\\pt` | Coins / Battle Points window |

## Media and faces

| Code | Effect |
|---|---|
| `\\se[name]` | Play SE `name` at that point in the text |
| `\\me[name]` | Play ME `name` |
| `\\f[pic]` | Show face picture from `Graphics/Pictures/` |
| `\\ff[face]` | Show a VX-style face |
| `\\ts[n]` | Text speed |
| `\\ch[var,cancel,opt1,opt2,...]` | Inline choice list, result into variable |

Example from a real gym event:
`"\\me[Badge get]\\bYou've earned the Boulder Badge."` followed by a `401` of
`"\\wtnp[110]"` - plays the fanfare, shows the line, auto-closes after 5.5s.

## Formatting tags (drawFormattedText)

These are angle-bracket tags, not backslash codes, handled by
`Data/Scripts/007_Objects and windows/010_DrawText.rb`:

`<c=...>`, `<c2=RRGGBBAA>`, `<c3=...>` colours; `<b>` bold, `<i>` italic,
`<u>` underline, `<s>` strikethrough, `<outln>` outline, `<fs=n>` font size,
`<al>` / `<ac>` / `<ar>` left/centre/right align, `<icon=name>` inline icon.

`<ac>` (centre) is common on sign text.
