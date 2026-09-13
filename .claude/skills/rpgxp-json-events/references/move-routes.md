# Move route reference

Codes below are from `Game_Character#move_type_custom` in
`Data/Scripts/004_Game classes/006_Game_Character.rb`.

## Container shape

```json
{
  "__type": "object",
  "class": "RPG::MoveRoute",
  "ivars": {
    "@list": [
      {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":4,"@parameters":[]}},
      {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":0,"@parameters":[]}}
    ],
    "@repeat": false,
    "@skippable": false
  }
}
```

- **`@list` must end with a `@code:0` MoveCommand.** With `@repeat:true` the
  route loops back to the start when it reaches that terminator; with
  `@repeat:false` it stops and control returns to the previous route.
- `@skippable:true` lets blocked movement steps be skipped instead of stalling.
- The idle route on a page that doesn't move is exactly one `@code:0` command
  with `@repeat:true, @skippable:false`.
- A page only *runs* its `@move_route` when `@move_type` is `3` (custom).
  `209` Set Move Route forces a route regardless of `@move_type`.

## Codes

### Movement (each takes one frame)

| Code | Action | Params |
|---|---|---|
| 1 | Move Down | |
| 2 | Move Left | |
| 3 | Move Right | |
| 4 | Move Up | |
| 5 | Move Lower Left | |
| 6 | Move Lower Right | |
| 7 | Move Upper Left | |
| 8 | Move Upper Right | |
| 9 | Move Random | |
| 10 | Move toward Player | |
| 11 | Move away from Player | |
| 12 | Step Forward | |
| 13 | Step Backward | |
| 14 | Jump | `[x_offset, y_offset]` |

### Wait and turning (each takes one frame)

| Code | Action | Params |
|---|---|---|
| 15 | Wait | `[duration]` (1/20ths of a second) |
| 16 | Turn Down | |
| 17 | Turn Left | |
| 18 | Turn Right | |
| 19 | Turn Up | |
| 20 | Turn 90° Right | |
| 21 | Turn 90° Left | |
| 22 | Turn 180° | |
| 23 | Turn 90° Right or Left | |
| 24 | Turn at Random | |
| 25 | Turn toward Player | |
| 26 | Turn away from Player | |

### Settings (instant - no frame consumed)

| Code | Action | Params |
|---|---|---|
| 27 | Switch ON | `[switch_id]` |
| 28 | Switch OFF | `[switch_id]` |
| 29 | Change Speed | `[1-6]` |
| 30 | Change Freq | `[1-5]` |
| 31 / 32 | Walk Anime ON / OFF | |
| 33 / 34 | Step Anime ON / OFF | |
| 35 / 36 | Direction Fix ON / OFF | |
| 37 / 38 | Through ON / OFF | |
| 39 / 40 | Always on Top ON / OFF | |
| 41 | Change Graphic | `["character_name", hue, direction, pattern]` |
| 42 | Change Opacity | `[0-255]` |
| 43 | Change Blending | `[0=normal,1=add,2=sub]` |
| 44 | Play SE | `[RPG::AudioFile]` |
| 45 | Script | `["ruby code"]` |

Move speed `1`..`6` = slowest..fastest (4 is normal walking).
Direction values are `2` down, `4` left, `6` right, `8` up.

## Most common in this project

`15` Wait (1176), `4` Move Up (418), `18` Turn Right (328), `17` Turn Left
(316), `38` Through OFF (292), `37` Through ON (290), `16` Turn Down (226),
`19` Turn Up (220), `1` Move Down (178), `42` Change Opacity (166),
`44` Play SE (144).

The through-on/through-off pair around a movement is the standard way to walk a
character through an obstacle (a door tile, a counter) without collision:

```
37 (through on) -> 4 (move up) -> 38 (through off)
```
