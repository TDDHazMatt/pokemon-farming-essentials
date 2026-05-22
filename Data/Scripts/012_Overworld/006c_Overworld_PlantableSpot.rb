#===============================================================================
# Universal plantable-soil interaction. Use this instead of pbBerryPlant or
# pbApricornTree directly when you want a single event that handles both.
#
# Call pbPlantableSpot from an overworld event's script box.
# The event name must match /plantablespot/i for the combined sprite hook.
#
# Behaviour:
#   • Soil empty   → ask "A Berry / An Apricorn / Nothing", then open the bag
#                    immediately (no second confirm).  For new berry mechanics
#                    the fertilize option is still offered before planting.
#   • Soil growing → show growth status message.
#   • Soil grown   → prompt to pick, then reset to empty.
#===============================================================================
def pbPlantableSpot
  interp     = pbMapInterpreter
  plant_data = interp.getVariable

  if plant_data.is_a?(BerryPlantData) && plant_data.planted?
    pbBerryPlant
    return
  elsif plant_data.is_a?(ApricornTreeData) && plant_data.planted?
    pbApricornTree
    return
  end

  # Clear any reset/dead plant data left over from a previous pick or death cycle
  interp.setVariable(nil) if plant_data

  choice = pbMessage(_INTL("It's soft, loamy soil.\nWhat would you like to plant?"),
                     [_INTL("A Berry"), _INTL("An Apricorn"), _INTL("Nothing")], -1)
  case choice
  when 0 then pbPlantBerryInSoil
  when 1 then pbPlantApricornInSoil
  end
end

#===============================================================================
# Plants a berry. Eventvar is only set after the player successfully plants
# (or after fertilizing, so mulch persists on the next visit).
#===============================================================================
def pbPlantBerryInSoil
  interp = pbMapInterpreter
  if Settings::NEW_BERRY_PLANTS
    case pbMessage(_INTL("It's soft, earthy soil."),
                   [_INTL("Fertilize"), _INTL("Plant Berry"), _INTL("Cancel")], -1)
    when 0
      mulch = nil
      pbFadeOutIn do
        scene  = PokemonBag_Scene.new
        screen = PokemonBagScreen.new(scene, $bag)
        mulch  = screen.pbChooseItemScreen(proc { |item| GameData::Item.get(item).is_mulch? })
      end
      return if !mulch
      mulch_data  = GameData::Item.get(mulch)
      berry_plant = BerryPlantData.new
      berry_plant.mulch_id = mulch
      $bag.remove(mulch)
      interp.setVariable(berry_plant)   # persist mulch for next visit
      pbMessage(_INTL("The {1} was scattered on the soil.", mulch_data.name))
      return
    when 1   # fall through to berry selection
    else
      return
    end
  end
  berry = nil
  pbFadeOutIn do
    scene  = PokemonBag_Scene.new
    screen = PokemonBagScreen.new(scene, $bag)
    berry  = screen.pbChooseItemScreen(proc { |item| GameData::Item.get(item).is_berry? })
  end
  return if !berry   # cancelled — eventvar stays nil, soil stays empty
  berry_plant = BerryPlantData.new
  interp.setVariable(berry_plant)
  $stats.berries_planted += 1
  berry_plant.plant(berry)
  $bag.remove(berry)
  berry_name = GameData::Item.get(berry).name
  if Settings::NEW_BERRY_PLANTS
    pbMessage(_INTL("The {1} was planted in the soft, earthy soil.", berry_name))
  elsif berry_name.starts_with_vowel?
    pbMessage(_INTL("{1} planted an {2} in the soft loamy soil.", $player.name, berry_name))
  else
    pbMessage(_INTL("{1} planted a {2} in the soft loamy soil.", $player.name, berry_name))
  end
end

#===============================================================================
# Plants an apricorn. Eventvar is only set after the player successfully plants.
#===============================================================================
def pbPlantApricornInSoil
  interp   = pbMapInterpreter
  apricorn = nil
  pbFadeOutIn do
    scene    = PokemonBag_Scene.new
    screen   = PokemonBagScreen.new(scene, $bag)
    apricorn = screen.pbChooseItemScreen(proc { |item| GameData::Item.get(item).is_apricorn? })
  end
  return if !apricorn   # cancelled — eventvar stays nil, soil stays empty
  tree = ApricornTreeData.new
  interp.setVariable(tree)
  $stats.apricorns_planted += 1
  tree.plant(apricorn)
  $bag.remove(apricorn)
  apricorn_name = GameData::Item.get(apricorn).name
  if apricorn_name.starts_with_vowel?
    pbMessage(_INTL("{1} planted an {2} in the soft loamy soil.", $player.name, apricorn_name))
  else
    pbMessage(_INTL("{1} planted a {2} in the soft loamy soil.", $player.name, apricorn_name))
  end
end

#===============================================================================
# Always-on sprite wrapper for /plantablespot/i events. Dynamically creates
# the correct sub-sprites whenever the type of planted data changes, so visuals
# appear immediately after planting without needing to reload the map.
#===============================================================================
class PlantableSpotSprite
  def initialize(event, map, viewport)
    @event      = event
    @map        = map
    @viewport   = viewport
    @disposed   = false
    @subsprites = []
    @last_class = nil
    refresh_subsprites(true)
  end

  def dispose
    clear_subsprites
    @event    = nil
    @map      = nil
    @disposed = true
  end

  def disposed?
    @disposed
  end

  def update
    return if @disposed
    plant_data = @event.variable
    new_class  = plant_data ? plant_data.class : NilClass
    if new_class != @last_class
      refresh_subsprites(true)
    else
      @subsprites.each { |s| s.update unless s.disposed? }
    end
  end

  private

  def clear_subsprites
    @subsprites.each { |s| s.dispose rescue nil }
    @subsprites.clear
  end

  def refresh_subsprites(force = false)
    plant_data = @event.variable
    new_class  = plant_data ? plant_data.class : NilClass
    return if !force && new_class == @last_class
    clear_subsprites
    @last_class = new_class
    case plant_data
    when BerryPlantData
      @subsprites << BerryPlantMoistureSprite.new(@event, @map, @viewport)
      @subsprites << BerryPlantSprite.new(@event, @map, @viewport)
    when ApricornTreeData
      @subsprites << ApricornTreeSprite.new(@event, @map, @viewport)
    else
      @event.character_name = ""
    end
  end
end

EventHandlers.add(:on_new_spriteset_map, :add_plantable_spot_graphics,
  proc { |spriteset, viewport|
    map = spriteset.map
    map.events.each do |event|
      next if !event[1].name[/plantablespot/i]
      spriteset.addUserSprite(PlantableSpotSprite.new(event[1], map, viewport))
    end
  }
)
