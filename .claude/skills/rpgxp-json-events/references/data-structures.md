# Data file structures

Every schema below was read out of this project's actual `Data/*.json`.
Ivar lists are complete - RPG Maker XP's editor expects all of them present.

## Which file holds what

| File | Top level | Contents |
|---|---|---|
| `MapXXX.json` | `RPG::Map` | one map: tiles, events, BGM, encounters |
| `MapInfos.json` | `hash` id -> `RPG::MapInfo` | map names and editor tree |
| `System.json` | `RPG::System` | switch/variable **names**, start position, SEs |
| `Tilesets.json` | Array (index = id, `[0]` is null) | tileset graphics, passages, priorities, terrain tags |
| `CommonEvents.json` | Array (index = id, `[0]` is null) | `RPG::CommonEvent` |
| `Animations.json` | Array | RMXP battle animations (`$data_animations`) |
| `PkmnAnimations.json` | Array subclass `PBAnimations` | Essentials move animations - 3.6MB, written by the in-game animation editor; avoid hand-editing |
| `PluginScripts.json` | Array | compiled plugin scripts; regenerated from `Plugins/` |

Not mirrored to JSON (and not to be edited here): `Scripts.rxdata` (the real
source is `Data/Scripts/*.rb`), the `*.dat` PBS caches (`items.dat`,
`species.dat`, ... - real source is `PBS/*.txt`), and the leftover RMXP demo
files (`Actors`, `Armors`, `Classes`, `Enemies`, `Items`, `Skills`, `States`,
`Troops`, `Weapons`), which no script in this project loads.

---

## RPG::Map

```json
{"__type":"object","class":"RPG::Map","ivars":{
  "@autoplay_bgm": false,
  "@autoplay_bgs": false,
  "@bgm": {"__type":"object","class":"RPG::AudioFile","ivars":{"@name":"","@pitch":100,"@volume":100}},
  "@bgs": {"__type":"object","class":"RPG::AudioFile","ivars":{"@name":"","@pitch":100,"@volume":80}},
  "@data": {"__type":"Table","xsize":20,"ysize":20,"zsize":3,"data":[ ... ]},
  "@encounter_list": [],
  "@encounter_step": 30,
  "@events": {"__type":"hash","entries":[[1, {"__type":"object","class":"RPG::Event", ...}]]},
  "@height": 20,
  "@tileset_id": 1,
  "@width": 20
}}
```

- `@data` is the tile grid: 3 z-layers, flat array indexed
  `x + y*xsize + z*xsize*ysize`. The JSON is wrapped one map row per line so it
  reads like the grid. Leave it alone unless explicitly asked to change tiles.
- `@encounter_list` is unused - Essentials uses `PBS/encounters.txt`.
- `@events` is a `hash` node: `entries` is a list of `[id, event]` pairs.

## RPG::Event

```json
{"__type":"object","class":"RPG::Event","ivars":{
  "@id": 3, "@name": "PC", "@x": 11, "@y": 1,
  "@pages": [ ... RPG::Event::Page ... ]
}}
```

The `entries` key and `@id` **must match**. `@x`/`@y` are tile coordinates
(0-based, origin top-left) and must be inside `@width`/`@height`.

Essentials reads size hints out of the **name**: `"Town Map, size(2,1)"` makes
the event 2 tiles wide and 1 tall, with the placed position as its bottom-left
tile.

## RPG::Event::Page

All 13 ivars are required:

```json
{"__type":"object","class":"RPG::Event::Page","ivars":{
  "@condition": { ...RPG::Event::Page::Condition... },
  "@graphic":   { ...RPG::Event::Page::Graphic... },
  "@list":      [ ...RPG::EventCommand..., {"@code":0,"@indent":0} ],
  "@move_route":{ ...RPG::MoveRoute... },
  "@move_type": 0,
  "@move_speed": 3,
  "@move_frequency": 3,
  "@trigger": 0,
  "@walk_anime": true,
  "@step_anime": false,
  "@direction_fix": false,
  "@through": false,
  "@always_on_top": false
}}
```

| Ivar | Values |
|---|---|
| `@trigger` | 0 Action Button, 1 Player Touch, 2 Event Touch, 3 Autorun, 4 Parallel Process |
| `@move_type` | 0 Fixed, 1 Random, 2 Approach, 3 Custom (uses `@move_route`) |
| `@move_speed` | 1 slowest .. 6 fastest (3 is this project's default for NPCs, 4 is normal walking) |
| `@move_frequency` | 1..6 - delay between move-route steps: 1 = 4.75s, 2 = 3.6s, 3 = 2.55s, 4 = 1.6s, 5 = 0.75s, 6 = continuous. The editor only offers 1-5, but 6 is valid and is `Game_Character`'s own default |
| `@through` | true = walk through / not solid |
| `@always_on_top` | draws above the player |

**Page selection:** pages are scanned **last to first**, and the first one whose
conditions all pass is used. A new "already done" state therefore goes at the
END of `@pages`. Autorun (3) runs until something turns its condition off -
always pair it with a self-switch/switch flip or the game locks up.

## RPG::Event::Page::Condition

```json
{"__type":"object","class":"RPG::Event::Page::Condition","ivars":{
  "@switch1_valid": false, "@switch1_id": 1,
  "@switch2_valid": false, "@switch2_id": 1,
  "@variable_valid": false, "@variable_id": 1, "@variable_value": 0,
  "@self_switch_valid": false, "@self_switch_ch": "A"
}}
```

Conditions AND together. The variable test is **`variable >= @variable_value`**,
not equality. `@self_switch_ch` is `"A"`, `"B"`, `"C"` or `"D"`. Ids stay at
their defaults (1/"A") when the matching `_valid` is false.

A switch whose **name** in `System.json` starts with `s:` is evaluated as Ruby
rather than read from `$game_switches` - e.g. switch 14 is
`s:PBDayNight.isDay?`, switch 36 is `s:$player.male?`. That's how day/night and
gender page conditions are done.

## RPG::Event::Page::Graphic

```json
{"__type":"object","class":"RPG::Event::Page::Graphic","ivars":{
  "@tile_id": 0, "@character_name": "NPC 25", "@character_hue": 0,
  "@direction": 2, "@pattern": 0, "@opacity": 255, "@blend_type": 0
}}
```

`@character_name` is a file in `Graphics/Characters/` **without** extension
(`""` = invisible, used for doors/triggers/script tiles). `@direction` 2 down,
4 left, 6 right, 8 up. `@pattern` 0-3 is the animation frame. To use a map tile
as the graphic instead, set `@tile_id` (>= 384) and leave `@character_name` `""`.

Trainer sprites in this project follow `trainer_TYPE_Name`, e.g.
`"trainer_LEADER_Brock"`.

## RPG::EventCommand / RPG::MoveRoute / RPG::MoveCommand

```json
{"__type":"object","class":"RPG::EventCommand","ivars":{"@code":101,"@indent":0,"@parameters":["Hi"]}}
{"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":4,"@parameters":[]}}
```

See `event-commands.md` and `move-routes.md`.

## RPG::CommonEvent

```json
{"__type":"object","class":"RPG::CommonEvent","ivars":{
  "@id": 1, "@name": "Professor Oak phone", "@trigger": 0, "@switch_id": 1,
  "@list": [ ...same command list format as an event page... ]
}}
```

`@trigger`: 0 None (call with command `117`), 1 Autorun, 2 Parallel. For 1/2 the
event runs while `@switch_id` is ON. `CommonEvents.json` is a plain array whose
index is the id, with `null` at index 0.

## RPG::System

Holds `@switches` and `@variables`: **arrays of names** where the index is the
switch/variable id (index 0 is null). These are labels only - values live in the
save file. Also `@start_map_id`/`@start_x`/`@start_y` (new game position),
`@edit_map_id` (editor's last map), windowskin/SE defaults, and `@magic_number`.

Renaming a switch here is safe and helpful; **renumbering is not** - ids are
referenced by every page condition and `121`/`111` command in every map.

## RPG::Tileset

```json
{"@id":1,"@name":"...","@tileset_name":"...","@autotile_names":[...7 names...],
 "@panorama_name":"","@panorama_hue":0,"@fog_name":"","@fog_hue":0,
 "@fog_opacity":64,"@fog_blend_type":0,"@fog_zoom":200,"@fog_sx":0,"@fog_sy":0,
 "@battleback_name":"","@passages":{Table},"@priorities":{Table},
 "@terrain_tags":{Table}}
```

`@passages`, `@priorities` and `@terrain_tags` are 1-D `Table`s indexed by tile
id. Terrain tags drive Essentials behaviour (grass, water, ice, ledges...).
The game itself rewrites `Tilesets.rxdata` from the PBS editors, so re-run
`convert_all_to_json.rb` before editing this file.

## RPG::MapInfo

```json
{"@name":"Route 7","@parent_id":0,"@order":43,"@expanded":false,"@scroll_x":809,"@scroll_y":459}
```

Editor metadata: `@parent_id` nests the map under another in the tree (0 = top
level), `@order` is its position. `@name` is the map name shown in the editor
and used by Essentials for location signposts. Adding a map means adding both a
`MapXXX.json` **and** a `MapInfos.json` entry.
