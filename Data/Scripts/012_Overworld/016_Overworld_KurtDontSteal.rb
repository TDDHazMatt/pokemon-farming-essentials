#===============================================================================
# Kurt's "Don't Steal" berries scene on Route 1 (Map005). Three invisible
# Player-Touch trigger events ("Don't Steal", ids 8/13/16) sit in a row north
# of his berry patch, guarding the way out. Walking into any of them while
# facing north (i.e. actually trying to leave, not just wandering into the
# patch) calls pbKurtDontStealCheck.
#
# Self switch B on the first trigger event (id 8) is a persistent "has been
# stolen from and not yet made right" flag - OFF by default. It only gets
# set the moment a violation is first caught (some PlantableSpot not
# replanted with something growing) while leaving, and only gets cleared
# once the player later leaves again with everything replanted. This means
# the confrontation can happen again and again if the player keeps stealing,
# rather than being a one-time scripted event.
#
# Kurt (event 17, "Don't Steal Kurt") walks down and either scolds the player
# (violation still outstanding) or thanks them (fully replanted, flag
# clears), then retreats home and vanishes either way - self switch A
# (already wired to his page 1 condition) toggles his visibility, and his
# position is silently reset to his spawn tile once hidden so his next
# appearance always starts from the same spot rather than wherever he last
# walked to. On a scold, the player is also pushed back into the patch, the
# same "push back" idiom Lappet Town's edge blockers use (Map002).
#===============================================================================
KURT_EVENT_ID          = 17
KURT_SPAWN_X           = 12
KURT_SPAWN_Y           = 8
KURT_STOLEN_FLAG_EVENT_ID = 8   # whichever "Don't Steal" trigger holds the "stolen from" flag (self switch B)

def pbKurtBerryPatchReplanted?
  map_id = $game_map.map_id
  # A BerryPlant event (a standing tree) is only a "spot that needs
  # replanting" once it's actually been picked - pbPickCrop
  # (012_Overworld/006c_Overworld_PlantableSpot.rb) flips its self switch A
  # on to swap it from the mature-tree page to an invisible page that just
  # calls pbPlantableSpot, at which point it behaves exactly like a
  # standalone PlantableSpot event and needs the same check. An unpicked
  # tree still has its own berries and isn't relevant here.
  spots = $game_map.events.values.select do |e|
    next true if e.name =~ /plantablespot/i
    next $game_self_switches[[map_id, e.id, "A"]] if e.name =~ /berryplant/i
    false
  end
  return spots.all? do |e|
    v = e.variable
    v.is_a?(CropData) && v.planted?
  end
end

def pbWaitForMoveRoute(character)
  while character.move_route_forcing
    Graphics.update
    Input.update
    pbUpdateSceneMap
  end
end

def pbKurtDontStealCheck
  return if $game_player.direction != 8   # only relevant when actually trying to leave (facing/moving north)

  map_id          = $game_map.map_id
  already_flagged = $game_self_switches[[map_id, KURT_STOLEN_FLAG_EVENT_ID, "B"]]
  replanted       = pbKurtBerryPatchReplanted?
  return if !already_flagged && replanted   # nothing's ever been stolen - let them pass silently

  kurt = $game_map.events[KURT_EVENT_ID]
  return if !kurt

  $game_self_switches[[map_id, KURT_EVENT_ID, "A"]]              = true
  $game_self_switches[[map_id, KURT_STOLEN_FLAG_EVENT_ID, "B"]]  = true
  $game_map.need_refresh = true

  pbMoveRoute(kurt, [PBMoveRoute::TOWARD_PLAYER] * 10)
  pbWaitForMoveRoute(kurt)
  pbMoveRoute(kurt, [PBMoveRoute::TURN_TOWARD_PLAYER])
  pbWaitForMoveRoute(kurt)

  if replanted
    pbMessage(_INTL("Kurt: \"Oh! You replanted everything - thank you kindly.\""))
    pbMoveRoute(kurt, [PBMoveRoute::TURN_UP, PBMoveRoute::UP, PBMoveRoute::UP, PBMoveRoute::UP])
    pbWaitForMoveRoute(kurt)
    $game_self_switches[[map_id, KURT_EVENT_ID, "A"]]             = false
    $game_self_switches[[map_id, KURT_STOLEN_FLAG_EVENT_ID, "B"]] = false
    $game_map.need_refresh = true
    kurt.moveto(KURT_SPAWN_X, KURT_SPAWN_Y)
  else
    pbMessage(_INTL("Kurt: \"Hey! Don't go taking my berries without replanting something!\""))
    pbMessage(_INTL("Kurt: \"Put back what you picked before you head off.\""))
    pbMoveRoute(kurt, [PBMoveRoute::TURN_UP, PBMoveRoute::UP, PBMoveRoute::UP])
    pbWaitForMoveRoute(kurt)
    $game_self_switches[[map_id, KURT_EVENT_ID, "A"]] = false
    $game_map.need_refresh = true
    kurt.moveto(KURT_SPAWN_X, KURT_SPAWN_Y)

    pbMoveRoute($game_player, [PBMoveRoute::TURN_DOWN, PBMoveRoute::DOWN])
    pbWaitForMoveRoute($game_player)
  end
end
