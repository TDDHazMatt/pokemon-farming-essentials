#===============================================================================
# Tillable soil. A /tillablespot/i event sits on dry, untilled ground - the
# map author paints the actual dry-soil tile there (one of the IDs below);
# the event itself is invisible, exactly like a plantable spot.
#
# Interacting with it while carrying a Hoe (or simply stepping onto it while
# carrying an Auto Tiller, no interaction needed) swaps the underlying tile
# to its loamy-soil counterpart and flips the event's own self-switch A. The
# event's second page (condition: self-switch A) just calls pbPlantableSpot -
# from that point on the spot behaves exactly like any other plantable spot,
# no different interaction code needed.
#
# Tile mutations made with Game_Map#set_tile are NOT part of the saved map
# data (the map reloads its tiles fresh from disk every time it's entered),
# so every already-tilled spot re-applies its own conversion on map load,
# keyed off the event's self-switch - see the on_new_spriteset_map hook below.
#===============================================================================

# Maps each dry-soil tile ID to its tilled, loamy-soil counterpart.
TILLABLE_TILE_CONVERSION = {
  593 => 1003,
  595 => 1004,
  601 => 1019,
  603 => 1020,
  609 => 1035,
  611 => 1036
}.freeze

# Converts the dry-soil tile at (x, y) on the given map to its loamy
# counterpart, checking each layer for a recognized dry-soil tile ID.
# Returns true if a conversion was made.
def pbTillTileAt(map, x, y)
  [2, 1, 0].each do |z|
    tile_id = map.data[x, y, z]
    next if tile_id.nil?
    converted = TILLABLE_TILE_CONVERSION[tile_id]
    next if !converted
    map.set_tile(x, y, z, converted)
    return true
  end
  return false
end

#===============================================================================
# "Hoe" interaction - call from a /tillablespot/i event's script box, on the
# page that runs before it's been tilled. The Hoe must be the active tool
# (equipped via its Bag "Use"), not just owned.
#===============================================================================
def pbTillableSpot
  interp = pbMapInterpreter
  this_event = interp.get_self
  if $PokemonGlobal.active_tool != :HOE
    pbMessage(_INTL("This soil looks like it could be tilled, but you'll need to equip your Hoe first."))
    return
  end
  if pbTillTileAt($game_map, this_event.x, this_event.y)
    pbMessage(_INTL("You tilled the soil with your Hoe."))
    pbSetSelfSwitch(this_event.id, "A", true)
  else
    pbMessage(_INTL("This patch doesn't look like it needs tilling."))
  end
end

#===============================================================================
# Auto Tiller - silently tills any untilled /tillablespot/i tile the player
# steps onto, no interaction needed, as long as it's the active tool.
#===============================================================================
EventHandlers.add(:on_step_taken, :auto_till_tillable_spot,
  proc { |event|
    next if event != $game_player
    next if $PokemonGlobal.active_tool != :AUTOTILLER
    map = event.map
    map.events.each_value do |ev|
      next if !ev.name[/tillablespot/i]
      next if ev.x != event.x || ev.y != event.y
      next if $game_self_switches[[map.map_id, ev.id, "A"]]
      next if !pbTillTileAt(map, ev.x, ev.y)
      $game_self_switches[[map.map_id, ev.id, "A"]] = true
      map.need_refresh = true
    end
  }
)

#===============================================================================
# Re-applies the loamy-soil tile for every already-tilled TillableSpot when
# the map loads, since raw tile mutations aren't part of the saved map data -
# only the event's self-switch remembers that this spot was tilled.
#===============================================================================
EventHandlers.add(:on_new_spriteset_map, :retill_tillable_spots,
  proc { |spriteset, _viewport|
    map = spriteset.map
    map.events.each_value do |event|
      next if !event.name[/tillablespot/i]
      next if !$game_self_switches[[map.map_id, event.id, "A"]]
      pbTillTileAt(map, event.x, event.y)
    end
  }
)
