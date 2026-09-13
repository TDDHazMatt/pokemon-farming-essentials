# Event command reference

Parameter layouts below were read out of this project's own interpreter,
`Data/Scripts/003_Game processing/004_Interpreter_Commands.rb`. Codes not
listed there are ignored at runtime (`else return true`).

Every command is an object:

```json
{"__type":"object","class":"RPG::EventCommand","ivars":{"@code":101,"@indent":0,"@parameters":["Hi!"]}}
```

Conventions used below:
- **char** = character id: `-1` player, `0` this event, `N` event N.
- **duration** = time in 1/20ths of a second (8 = 0.4s).
- **on/off** = `0` means ON/true, `1` means OFF/false (RMXP's inverted flag).

---

## Messages and choices

| Code | Name | Parameters |
|---|---|---|
| 101 | Show Text | `["text"]` |
| 401 | Text continuation | `["more text"]` |
| 102 | Show Choices | `[["Choice1","Choice2"], cancel_type]` |
| 402 | When [n] | `[n, "Choice text"]` - `n` is 0-based |
| 403 | When Cancel | `[4]` |
| 404 | Choices Branch End | `[]` |
| 103 | Input Number | `[variable_id, max_digits]` |
| 104 | Change Text Options | `[position, frame]` |
| 105 | Button Input Processing | `[variable_id]` |
| 106 | Wait | `[duration]` |

**Show Text:** `101` holds the first line; each additional `401` is appended
**with a space separator**, then the message system word-wraps. `\n` (written
`"\\n"` in JSON) forces a line break. Two adjacent `101` commands become two
separate message boxes.

**Show Choices:** `cancel_type` is `0` = disallow cancel, `1..4` = cancelling
picks that choice (1-based), `5` = cancel runs the `403` branch.
Structure (indents relative to the `102`):

```
102 [["Yes","No"], 2]        indent N
  402 [0,"Yes"]              indent N     <- no code 0 before the first 402
    ...body...               indent N+1
    0                        indent N+1
  402 [1,"No"]               indent N
    ...body...               indent N+1
    0                        indent N+1
  404 []                     indent N
```

Essentials extension: a second `102` immediately following a choices block is
merged into the first, allowing **more than 4 choices**. Script helpers
`hide_choice(n)` and `rename_choice(n, "text")` work on the pending block.

---

## Flow control

| Code | Name | Parameters |
|---|---|---|
| 111 | Conditional Branch | see table below |
| 411 | Else | `[]` |
| 412 | Branch End | `[]` |
| 112 | Loop | `[]` |
| 413 | Repeat Above | `[]` |
| 113 | Break Loop | `[]` |
| 115 | Exit Event Processing | `[]` |
| 116 | Erase Event | `[]` |
| 117 | Call Common Event | `[common_event_id]` |
| 118 | Label | `["name"]` |
| 119 | Jump to Label | `["name"]` |

### Conditional Branch (111) types

| p[0] | Condition | Parameters |
|---|---|---|
| 0 | Switch | `[0, switch_id, on/off]` |
| 1 | Variable | `[1, var_id, 0=const/1=var, operand, op]` |
| 2 | Self Switch | `[2, "A", on/off]` |
| 3 | Timer | `[3, seconds, 0=at least/1=at most]` |
| 6 | Character direction | `[6, char, direction]` (2/4/6/8) |
| 7 | Gold | `[7, amount, 0=at least/1=at most]` |
| 11 | Button pressed | `[11, input_constant]` |
| 12 | **Script** | `[12, "ruby expression"]` |

Variable `op`: `0` ==, `1` >=, `2` <=, `3` >, `4` <, `5` !=.

Types **4, 5, 8, 9, 10 are disabled in Essentials** (actor/enemy/item/weapon/
armor) - they always evaluate false. Use type 12 with a script instead:
`[12,"$player.has_item?(:POTION)"]`, `[12,"$player.badges[0]"]`.

A `111` whose body is a battle/item script commonly wraps the result, e.g.
`[12,"pbItemBall(:GREATBALL)"]` - the script's return value is the condition.

---

## Switches, variables, party

| Code | Name | Parameters |
|---|---|---|
| 121 | Control Switches | `[first_id, last_id, on/off]` |
| 122 | Control Variables | `[first_id, last_id, op, operand_type, ...]` |
| 123 | Control Self Switch | `["A", on/off]` |
| 124 | Control Timer | `[0=start/1=stop, seconds]` |
| 125 | Change Gold | `[0=inc/1=dec, 0=const/1=var, value]` |
| 314 | Recover All | `[actor]` (Essentials: heals the party) |

**122 Control Variables** - `op`: 0 set, 1 add, 2 sub, 3 mul, 4 div, 5 mod.
`operand_type` and what follows:

| p[3] | Operand | Rest |
|---|---|---|
| 0 | constant | `p[4]` = value |
| 1 | variable | `p[4]` = source variable id |
| 2 | random | `p[4]` = min, `p[5]` = max |
| 6 | character | `p[4]` = char, `p[5]` = 0 x, 1 y, 2 direction, 3 screen_x, 4 screen_y, 5 terrain tag |
| 7 | other | `p[4]` = 0 map id, 1 party count, 2 gold, 3 steps, 4 play time, 5 timer, 6 save count |

Types 3, 4, 5 (item/actor/enemy) are disabled in Essentials.

---

## Movement and the map

| Code | Name | Parameters |
|---|---|---|
| 201 | Transfer Player | `[0=direct/1=vars, map_id, x, y, direction, fade]` |
| 202 | Set Event Location | `[char, 0=direct/1=vars/2=swap, x, y, direction]` |
| 203 | Scroll Map | `[direction, distance, speed]` |
| 204 | Change Map Settings | `[0=panorama/1=fog/2=battleback, ...]` |
| 205 | Change Fog Color Tone | `[Tone, duration]` |
| 206 | Change Fog Opacity | `[opacity, duration]` |
| 207 | Show Animation | `[char, animation_id]` |
| 208 | Change Transparent Flag | `[0=transparent/1=normal]` |
| 209 | Set Move Route | `[char, RPG::MoveRoute]` |
| 210 | Wait for Move's Completion | `[]` |

`201` direction: `0` retain, `2` down, `4` left, `6` right, `8` up.
`201` fade: `0` fade out/in, `1` no fade (used when the event already faded the
screen itself with `223`).

**`209` is always followed by mirror `509` commands.** RPG Maker XP writes one
`509` per *real* move command so the route is visible in the editor's event
list. The exact rule (verified across all 441 `209`s in this project):

- the route's own `@list` ends with a terminator `RPG::MoveCommand` of `@code:0`;
- the number of `509` lines is **`route.length - 1`** - every move command
  except that terminator;
- the *n*th `509`'s `@parameters[0]` is **the same MoveCommand object** as
  `route[n]`, in order;
- every `509` carries **the same `@indent`** as its `209`.

The interpreter ignores `509` entirely, but the RPG Maker XP editor relies on
it, so write them. See `recipes.md` for a complete copy-paste example.

---

## Screen effects

| Code | Name | Parameters |
|---|---|---|
| 221 | Prepare for Transition | `[]` |
| 222 | Execute Transition | `["transition_name"]` (`""` = default) |
| 223 | Change Screen Color Tone | `[Tone, duration]` |
| 224 | Screen Flash | `[Color, duration]` |
| 225 | Screen Shake | `[power, speed, duration]` |
| 236 | Set Weather Effects | `[type, power, duration]` |

Fade to black / restore, the standard door pattern:
`223 [{"__type":"Tone","red":-255.0,"green":-255.0,"blue":-255.0,"gray":0.0}, 6]`
then `223 [{"__type":"Tone","red":0.0,"green":0.0,"blue":0.0,"gray":0.0}, 6]`.

---

## Pictures

| Code | Name | Parameters |
|---|---|---|
| 231 | Show Picture | `[num, "name", origin, 0=direct/1=vars, x, y, zoom_x, zoom_y, opacity, blend]` |
| 232 | Move Picture | `[num, duration, origin, 0/1, x, y, zoom_x, zoom_y, opacity, blend]` |
| 233 | Rotate Picture | `[num, speed]` |
| 234 | Change Picture Color Tone | `[num, Tone, duration]` |
| 235 | Erase Picture | `[num]` |

Picture files come from `Graphics/Pictures/`. `origin`: 0 top-left, 1 center.

---

## Audio

| Code | Name | Parameters |
|---|---|---|
| 241 | Play BGM | `[RPG::AudioFile]` |
| 242 | Fade Out BGM | `[seconds]` |
| 245 | Play BGS | `[RPG::AudioFile]` |
| 246 | Fade Out BGS | `[seconds]` |
| 247 | Memorize BGM/BGS | `[]` |
| 248 | Restore BGM/BGS | `[]` |
| 249 | Play ME | `[RPG::AudioFile]` |
| 250 | Play SE | `[RPG::AudioFile]` |
| 251 | Stop SE | `[]` |

```json
{"__type":"object","class":"RPG::AudioFile","ivars":{"@name":"Door enter","@pitch":100,"@volume":100}}
```

Names are filenames without extension, from `Audio/SE`, `Audio/ME`, `Audio/BGM`.
Common in this project: SE `"Door enter"`, `"Door exit"`, `"Item get"` (ME),
`"Badge get"` (usually via the `\me[]` message code instead).

---

## Scripts and scenes

| Code | Name | Parameters |
|---|---|---|
| 355 | Script | `["ruby line"]` |
| 655 | Script continuation | `["ruby line"]` |
| 351 | Call Menu Screen | `[]` |
| 352 | Call Save Screen | `[]` |
| 353 | Game Over | `[]` |
| 354 | Return to Title Screen | `[]` |
| 303 | Name Input Processing | `[actor_id, max_chars]` |

A `355` absorbs every following `655` **and every following `355`**, joining
them with newlines into one script that is eval'd once. Keep one statement per
line; put the first line in the `355` and the rest in `655` commands.

---

## Comments and no-ops

| Code | Name | Parameters |
|---|---|---|
| 108 | Comment | `["text"]` |
| 408 | Comment continuation | `["text"]` |
| 0 | Empty / block terminator | `[]` |

`0` is not a real command - it terminates every branch body (at `indent+1`) and
the command list itself (at indent 0). Essentials also reads certain `108`
comments on an event page as metadata in some plugins; don't delete comments you
didn't add.

---

## Battle / shop (RMXP originals, largely unused here)

`301` Battle Processing, `601/602/603` If Win/Escape/Lose, `302` Shop Processing,
`311`-`322` actor stat changes, `331`-`340` enemy changes. Essentials replaces
all of these with script calls (`TrainerBattle.start`, `pbPokemonMart`, ...).
Do not add them; use `355`.
