---
name: rpgxp-json-events
description: Edit RPG Maker XP / Pokémon Essentials game data through this project's Data/*.json mirrors - adding or changing events, NPCs, dialogue, doors, trainers, item balls, signs, common events, map settings, switches and variables. Use whenever a request touches Data/*.rxdata, Data/*.json, map events, or in-game text.
---

# Editing RPG Maker XP data via Data/*.json

The game reads `Data/*.rxdata` (Ruby Marshal binaries). This repo keeps a
human-editable `Data/*.json` mirror of each one, converted by the scripts at
the repo root. **You edit the JSON; a converter writes the .rxdata.**

## Workflow (follow in order)

1. **Refresh the JSON** if the `.rxdata` may be newer (the user played the
   game, used a debug editor, or opened RPG Maker XP since the last sync):
   ```
   ruby convert_all_to_json.rb
   ```
   It skips any file whose `.json` is newer than its `.rxdata`, so it will not
   clobber pending hand-edits.

2. **Locate what you're changing** without burning context. Map JSONs are up to
   600KB and mostly tile data - do NOT read a whole map file. Use:
   ```
   ruby .claude/skills/rpgxp-json-events/scripts/event_tool.rb list Map009
   ruby .claude/skills/rpgxp-json-events/scripts/event_tool.rb show Map009 5
   ruby .claude/skills/rpgxp-json-events/scripts/event_tool.rb grep "Prof. Oak"
   ```
   `show` prints a compact code/indent/params listing; use Read with an offset
   only when you need the exact bytes to Edit.

3. **Edit the JSON** (Edit tool). Follow the invariants below exactly.

4. **Validate before converting** - this catches structural mistakes that the
   converter would happily turn into a broken map:
   ```
   ruby .claude/skills/rpgxp-json-events/scripts/validate_events.rb Data/Map009.json
   ```
   Run with no argument to validate every map.

5. **Convert back**:
   ```
   ruby convert_all_to_rxdata.rb
   ```
   It skips any file whose `.rxdata` is newer than its `.json`; pass `--force`
   only when you intend to discard changes made directly to the `.rxdata`.

6. Tell the user to restart the game (or reload the map) - a running game has
   the old data cached.

## Hard rules

- **Never edit `Data/*.rxdata` directly**, and never hand-write Marshal bytes.
- **Never edit `Data/*.json` tile data (`@data` under `"__type": "Table"`) to
  "draw" a map** unless explicitly asked. Tiles are a 3-layer grid; use the
  RPG Maker XP editor for map painting. Events are what you edit here.
- **The game must be closed** when you run `convert_all_to_rxdata.rb`. The game
  writes `Tilesets/System/MapInfos/CommonEvents/PkmnAnimations.rxdata` itself
  (debug editors, PBS compiler), which is exactly what the mtime guard protects.
- Most of `Data/` is gitignored, so an overwritten `.rxdata` is **not**
  recoverable with git. The `.json` mirrors *are* tracked - they are the
  reviewable source of truth.
- Ruby must be on PATH (`ruby -v`). All commands run from the repo root.

## JSON encoding (the `__type` wrapper system)

`rxdata_common.rb` tags non-JSON-native Ruby types. When you write new nodes:

| Ruby value | JSON form |
|---|---|
| object | `{"__type":"object","class":"RPG::Event","ivars":{"@id":1,...}}` |
| Hash | `{"__type":"hash","entries":[[key,value],...]}` (entries, NOT a JSON object) |
| Symbol | `{"__type":"symbol","name":"GREATBALL"}` |
| Table (tile grid) | `{"__type":"Table","xsize":20,"ysize":20,"zsize":3,"data":[...]}` |
| Tone / Color | `{"__type":"Tone","red":-255.0,"green":-255.0,"blue":-255.0,"gray":0.0}` |
| Array | plain JSON array |
| String | plain JSON string |

- **Ivar names keep their `@`** and are quoted: `"@name": "Nurse"`.
- **Plain text is a plain JSON string.** Non-ASCII (é in "Pokémon") is fine as a
  normal UTF-8 JSON string - that is already the dominant form in this repo.
  You may also see `{"__type":"text_b","text":"...","enc":"ASCII-8BIT"}`; if you
  edit such a node, keep the wrapper and change only `"text"`.
- **Message control codes need doubled backslashes**: in-game `\b` is `"\\b"` in
  JSON, `\v[1]` is `"\\v[1]"`, `\PN` is `"\\PN"`. A bare `"\n"` is a real
  newline character, which is NOT the same thing as the `\n` message code.
- Tone/Color components are **floats** (`-255.0`, not `-255`).

## Event structure invariants

Verified true across all 81 maps; the validator enforces them.

- An event lives in the map's `@events` hash: `[id, RPG::Event]`, and the hash
  key **must equal** the event's `@id`. New ids must be unique in that map.
- `@pages` is a non-empty array. **The last page whose conditions are satisfied
  wins** (pages are scanned in reverse), so an "after" state goes at the END.
- Every page needs all 13 ivars (`@condition @graphic @list @move_route
  @move_type @move_speed @move_frequency @trigger @walk_anime @step_anime
  @direction_fix @through @always_on_top`) - copy a whole page and edit it
  rather than assembling one from memory.
- **`@list` must be non-empty and end with `{"@code":0,"@indent":0}`.**
- `@indent` starts at 0 and increases by exactly 1 per nesting level.
- **Every branch body ends with a `code 0` at `indent+1`**, then the block
  terminator at the outer indent:
  - `111` Conditional Branch -> optional `411` Else -> `412` Branch End
  - `102` Show Choices -> `402` When[n] (one per choice) -> optional `403`
    When Cancel -> `404` Branch End
  - `112` Loop -> `413` Repeat Above
- Continuation lines only ever follow their opener: `401` after `101`/`401`
  (extra text lines), `655` after `355`/`655` (extra script lines).
- `@move_route` must exist on every page even if unused - minimum is a
  `RPG::MoveRoute` with one `code 0` MoveCommand, `@repeat:true`,
  `@skippable:false`.

## Most-used command codes

Full table with exact parameters: `references/event-commands.md`.

| Code | Command | Parameters |
|---|---|---|
| 101 | Show Text | `["line"]` (+ `401` lines, joined with a SPACE) |
| 102 | Show Choices | `[["A","B"], cancel]` |
| 402 / 403 / 404 | When[n] / When Cancel / End | `[n,"A"]` / `[4]` / `[]` |
| 111 / 411 / 412 | Conditional / Else / End | see reference |
| 355 / 655 | Script / script continuation | `["ruby code"]` |
| 121 / 122 / 123 | Switch / Variable / Self Switch | `[from,to,0=on]` / see ref / `["A",0=on]` |
| 201 | Transfer Player | `[0,mapid,x,y,dir,fade]` |
| 209 / 210 | Set Move Route / Wait for it | `[char,MoveRoute]` / `[]` |
| 250 / 249 / 241 | Play SE / ME / BGM | `[RPG::AudioFile]` |
| 223 | Screen Tone | `[Tone, duration]` |
| 106 | Wait | `[duration]` |
| 108 / 408 | Comment / comment continuation | `["text"]` |

Durations are in **1/20ths of a second** (`106 [8]` = 0.4s).
Character ids: **-1 = player, 0 = this event, N = event N**.

## Essentials specifics that differ from stock RMXP

- `101` + `401` lines are joined with a **space** (the interpreter adds one only
  if the previous chunk doesn't already end in a space, which is why the
  existing data has trailing spaces - harmless either way), then the message box
  word-wraps. Don't expect one displayed line per `401`; use `\\n` to force a
  break.
- Consecutive `355` Script commands are **concatenated into one script** before
  being eval'd, so a multi-line script can be `355` + `655` lines.
- Conditional Branch types 4,5,8,9,10 (actor/enemy/item/weapon/armor) are
  **disabled** in Essentials. Use type 12 (script) instead, e.g.
  `[12,"$player.has_item?(:POTION)"]`.
- Variable page conditions test **`variable >= value`**, not equality.
- A switch whose name in `System.json` starts with `s:` is evaluated as Ruby
  instead of read from `$game_switches` (e.g. switch 14 = `s:PBDayNight.isDay?`).
- Most Pokémon logic is done with `355` Script calls (`pbTrainerIntro`,
  `TrainerBattle.start`, `pbItemBall`, `pbReceiveItem`, ...), not with RMXP
  commands. Prefer matching an existing event's script calls over inventing.

## References

- `references/recipes.md` - copy-paste JSON for NPC, sign, door, item ball,
  trainer, choices, conditional, 2-page self-switch events. **Start here when
  adding an event.**
- `references/event-commands.md` - every command code + exact parameters.
- `references/move-routes.md` - move route command codes.
- `references/message-codes.md` - `\b`, `\v[]`, `\wtnp[]`, `<ac>`, etc.
- `references/data-structures.md` - full JSON schema of every RPG:: class,
  plus System/Tilesets/CommonEvents/MapInfos layout.

## Finishing a change

Always report: which file(s) changed, the validator result, and whether
`convert_all_to_rxdata.rb` succeeded. If the converter prints `SKIPPED`, say so
and explain the mtime reason - do not silently pass `--force`.
