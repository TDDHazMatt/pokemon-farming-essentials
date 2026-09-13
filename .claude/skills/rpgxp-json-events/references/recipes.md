# Event recipes

Copy-paste JSON taken from real events in this project. Paste an event as a new
`[id, event]` pair into a map's `@events.entries`, with `id` matching `@id`.

## The page boilerplate

Every recipe below reuses this page shell - only `@graphic`, `@trigger`,
`@condition` and `@list` change. Keep all 13 ivars.

```json
{
  "__type": "object",
  "class": "RPG::Event::Page",
  "ivars": {
    "@always_on_top": false,
    "@condition": {
      "__type": "object",
      "class": "RPG::Event::Page::Condition",
      "ivars": {
        "@self_switch_ch": "A", "@self_switch_valid": false,
        "@switch1_id": 1, "@switch1_valid": false,
        "@switch2_id": 1, "@switch2_valid": false,
        "@variable_id": 1, "@variable_valid": false, "@variable_value": 0
      }
    },
    "@direction_fix": false,
    "@graphic": {
      "__type": "object",
      "class": "RPG::Event::Page::Graphic",
      "ivars": {
        "@blend_type": 0, "@character_hue": 0, "@character_name": "",
        "@direction": 2, "@opacity": 255, "@pattern": 0, "@tile_id": 0
      }
    },
    "@list": [
      {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
    ],
    "@move_frequency": 3,
    "@move_route": {
      "__type": "object",
      "class": "RPG::MoveRoute",
      "ivars": {
        "@list": [
          {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":0,"@parameters":[]}}
        ],
        "@repeat": true, "@skippable": false
      }
    },
    "@move_speed": 3,
    "@move_type": 0,
    "@step_anime": false,
    "@through": false,
    "@trigger": 0,
    "@walk_anime": true
  }
}
```

---

## 1. Talking NPC

A complete event. `@trigger: 0` = talk to it with the action button.
Set `@graphic.@character_name` to a file in `Graphics/Characters/`.

```json
[12, {
  "__type": "object",
  "class": "RPG::Event",
  "ivars": {
    "@id": 12,
    "@name": "Farmer",
    "@x": 14,
    "@y": 8,
    "@pages": [ { "...page boilerplate with:": "",
      "@graphic.@character_name": "NPC 28",
      "@graphic.@direction": 2,
      "@list": [
        {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":101,"@indent":0,"@parameters":["\\bThe berries here grow faster if you water them "]}},
        {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":401,"@indent":0,"@parameters":["every day."]}},
        {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
      ] } ]
  }
}]
```

> The `"...page boilerplate with:"` line is shorthand for this document only -
> when you write the file, expand the full page object and replace those ivars.

`101` + `401` are joined with a space and word-wrapped, so break lines wherever
is convenient. Two adjacent `101`s = two message boxes.

## 2. Sign

Invisible-graphic events are also fine for signs; this project usually gives
signs a tile graphic and `@trigger: 0`.

```json
"@list": [
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":101,"@indent":0,"@parameters":["\\w[signskin]\\acBerry Fields\\nWater, weed, and wait."]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
]
```

## 3. Door / exit (plain transfer)

`@trigger: 1` (Player Touch), `@graphic.@character_name: ""`. This is the exact
shape of `Map009` event 1: SE, fade out, wait, transfer with no fade, fade in.

```json
"@list": [
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":250,"@indent":0,"@parameters":[
    {"__type":"object","class":"RPG::AudioFile","ivars":{"@name":"Door exit","@pitch":100,"@volume":80}}]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":223,"@indent":0,"@parameters":[
    {"__type":"Tone","red":-255.0,"green":-255.0,"blue":-255.0,"gray":0.0}, 6]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":106,"@indent":0,"@parameters":[8]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":201,"@indent":0,"@parameters":[0,7,47,10,0,1]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":223,"@indent":0,"@parameters":[
    {"__type":"Tone","red":0.0,"green":0.0,"blue":0.0,"gray":0.0}, 6]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
]
```

`201 [0, map_id, x, y, direction, 1]` - the trailing `1` means "no fade",
because the event already handled the fade itself.

## 4. Move route with its `509` mirrors

From `Map002`'s animated "Home door". Note the `509` rules: one per move command
**excluding** the route's `code 0` terminator, same `@indent`, each holding the
same MoveCommand object, in order.

```json
"@list": [
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":209,"@indent":0,"@parameters":[-1,
    {"__type":"object","class":"RPG::MoveRoute","ivars":{
      "@list": [
        {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":37,"@parameters":[]}},
        {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":4,"@parameters":[]}},
        {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":38,"@parameters":[]}},
        {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":0,"@parameters":[]}}
      ],
      "@repeat": false, "@skippable": false}}]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":509,"@indent":0,"@parameters":[
    {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":37,"@parameters":[]}}]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":509,"@indent":0,"@parameters":[
    {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":4,"@parameters":[]}}]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":509,"@indent":0,"@parameters":[
    {"__type":"object","class":"RPG::MoveCommand","ivars":{"@code":38,"@parameters":[]}}]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":210,"@indent":0,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
]
```

`209 [-1, route]` moves the **player** (through-on, step up, through-off) and
`210` waits for it to finish. Use `0` for "this event", `N` for event N.

## 5. Item ball (two pages)

Page 1 runs the pickup and sets self-switch A; page 2 is the empty "already
taken" state, conditioned on A, with no graphic and an empty list.

Page 1 - `@graphic.@character_name: "Object ball"`, `@trigger: 0`:

```json
"@list": [
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":111,"@indent":0,"@parameters":[12,"pbItemBall(:GREATBALL)"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":123,"@indent":1,"@parameters":["A",0]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":1,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":412,"@indent":0,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
]
```

Page 2 - boilerplate page with `@self_switch_valid: true`, `@self_switch_ch:
"A"`, `@character_name: ""`, and a `@list` of just the terminating `code 0`.
Page 2 must come **after** page 1 in `@pages` (last valid page wins).

## 6. Trainer

From `Map010`'s Brock. `@graphic.@character_name` is the trainer sprite
(`trainer_LEADER_Brock`), page 2 is the post-battle self-switch page.

```json
"@list": [
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":355,"@indent":0,"@parameters":["pbTrainerIntro(:LEADER_Brock)"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":101,"@indent":0,"@parameters":["\\bYou've made it this far, but can you beat me?"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":111,"@indent":0,"@parameters":[12,"TrainerBattle.start(:LEADER_Brock, \"Brock\")"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":101,"@indent":1,"@parameters":["\\me[Badge get]\\bYou've earned the Boulder Badge."]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":401,"@indent":1,"@parameters":["\\wtnp[110]"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":355,"@indent":1,"@parameters":["$player.badges[0] = true"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":123,"@indent":1,"@parameters":["A",0]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":1,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":412,"@indent":0,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":355,"@indent":0,"@parameters":["pbTrainerEnd"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
]
```

Note `pbTrainerEnd` sits **after** the `412`, so it runs win or lose.

## 7. Conditional branch with Else

From `Map003`'s Mom - self-switch A decides which branch runs.

```json
"@list": [
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":111,"@indent":0,"@parameters":[2,"A",0]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":101,"@indent":1,"@parameters":["\\rTake care out there!"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":1,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":411,"@indent":0,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":249,"@indent":1,"@parameters":[
    {"__type":"object","class":"RPG::AudioFile","ivars":{"@name":"Item get","@pitch":100,"@volume":100}}]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":355,"@indent":1,"@parameters":["pbReceiveItem(:TENT)"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":123,"@indent":1,"@parameters":["A",0]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":1,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":412,"@indent":0,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
]
```

## 8. Show Choices

From `Map009`'s Bill. The `102` declares the options; each `402` is one branch.

```json
"@list": [
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":101,"@indent":0,"@parameters":["\\bWhat do you want to know?"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":102,"@indent":0,"@parameters":[["Berries","Cancel"],2]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":402,"@indent":0,"@parameters":[0,"Berries"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":101,"@indent":1,"@parameters":["\\bWater them daily and they'll yield more."]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":1,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":402,"@indent":0,"@parameters":[1,"Cancel"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":1,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":404,"@indent":0,"@parameters":[]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
]
```

`[["Berries","Cancel"], 2]` - the `2` makes cancelling pick choice 2. Use `0`
to forbid cancelling, or `5` plus a `403` branch to handle cancel separately.
There is **no** `code 0` between the `102` and its first `402`.

## 9. Multi-line script

```json
"@list": [
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":355,"@indent":0,"@parameters":["pbSet(1, $player.pokedex.seen_count)"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":655,"@indent":0,"@parameters":["pbSet(2, $player.pokedex.owned_count)"]}},
  {"__type":"object","class":"RPG::EventCommand","ivars":{"@code":0,"@indent":0,"@parameters":[]}}
]
```

## 10. Autorun cutscene

`@trigger: 3` runs as soon as the page's conditions hold, with no player input.
It repeats forever unless the page stops qualifying, so the body **must** end by
flipping the flag that gated it (a `123` self switch or `121` switch), and page
ordering must give a later page that lacks the autorun trigger.

Use `@trigger: 4` (Parallel Process) only for background logic; it restarts when
it finishes and cannot show messages reliably.

## Useful script calls in this project

Grep an existing event before inventing one - `event_tool.rb grep "pbReceiveItem"`.

| Call | Purpose |
|---|---|
| `pbItemBall(:ITEM)` | pick-up item ball (returns true when taken) |
| `pbReceiveItem(:ITEM)` | give an item with the standard message |
| `pbTrainerIntro(:TYPE_Name)` / `pbTrainerEnd` | trainer battle wrapper |
| `TrainerBattle.start(:TYPE_Name, "Name")` | the battle itself |
| `pbSet(n, value)` | set game variable *n* |
| `$player.badges[n] = true` | award a badge |
| `pbPokeCenterPC` / `pbShowMap` | open PC / town map |
| `$game_switches[n] = true` | set a switch from script |
