#===============================================================================
# Stub class kept for Marshal compatibility with old save files and for the
# v20 save conversion that still instantiates it. The v22 conversion migrates
# all instances to CropData automatically on load.
#===============================================================================
class BerryPlantData
  attr_accessor :new_mechanics, :berry_id, :mulch_id
  attr_accessor :time_alive, :time_last_updated, :growth_stage, :replant_count
  attr_accessor :watered_this_stage, :watering_count
  attr_accessor :moisture_level, :yield_penalty

  def initialize
    @new_mechanics      = Settings::NEW_BERRY_PLANTS
    @berry_id           = nil
    @mulch_id           = nil
    @time_alive         = 0
    @time_last_updated  = 0
    @growth_stage       = 0
    @replant_count      = 0
    @watered_this_stage = false
    @watering_count     = 0
    @moisture_level     = 100
    @yield_penalty      = 0
  end

  def planted?; return @growth_stage > 0; end
end

#===============================================================================
# Backward-compatibility wrapper. Map events that call pbBerryPlant directly
# continue to work; they use CropData + pbInteractWithCrop internally.
#===============================================================================
def pbBerryPlant
  interp    = pbMapInterpreter
  this_event = interp.get_self
  crop = interp.getVariable
  # Migrate legacy BerryPlantData instances to CropData on first touch.
  if crop.is_a?(BerryPlantData)
    new_crop = CropData.new
    if crop.planted?
      new_crop.crop_id           = crop.berry_id
      new_crop.mulch_id          = crop.mulch_id
      new_crop.time_alive        = crop.time_alive
      new_crop.time_last_updated = crop.time_last_updated
      new_crop.growth_stage      = crop.growth_stage
      new_crop.replant_count     = crop.replant_count
      new_crop.moisture_level    = crop.moisture_level || 100
      new_crop.yield_penalty     = crop.yield_penalty  || 0
    end
    crop = new_crop
    interp.setVariable(crop)
  end
  crop = CropData.new unless crop.is_a?(CropData)
  if crop.planted?
    pbInteractWithCrop(crop)
    crop = interp.getVariable
    if crop.is_a?(CropData) && !crop.planted?
      interp.setVariable(nil)
      pbSetSelfSwitch(this_event.id, "A", false)
    end
    return
  end
  # Empty soil — Spreader shortcut or normal plant flow.
  if $PokemonGlobal.spreader_loaded_item
    loaded = pbSpreaderGetItem
    if loaded
      item_data = GameData::Item.get(loaded)
      if item_data.is_mulch? && !crop.mulch_id
        crop.mulch_id = loaded
        $bag.remove(loaded)
        interp.setVariable(crop)
      elsif item_data.is_berry?
        interp.setVariable(crop)
        $stats.berries_planted += 1
        crop.plant(loaded)
        $bag.remove(loaded)
      else
        $PokemonGlobal.spreader_loaded_item = nil
      end
    end
    return
  end
  ask_to_plant = true
  if Settings::NEW_BERRY_PLANTS
    if crop.mulch_id
      pbMessage(_INTL("{1} has been laid down.", GameData::Item.get(crop.mulch_id).name))
    else
      case pbMessage(_INTL("It's soft, earthy soil."),
                     [_INTL("Fertilize"), _INTL("Plant Berry"), _INTL("Exit")], -1)
      when 0
        mulch = nil
        pbFadeOutIn do
          scene  = PokemonBag_Scene.new
          screen = PokemonBagScreen.new(scene, $bag)
          mulch  = screen.pbChooseItemScreen(proc { |item| GameData::Item.get(item).is_mulch? })
        end
        return unless mulch
        crop.mulch_id = mulch
        $bag.remove(mulch)
        interp.setVariable(crop)
        pbMessage(_INTL("The {1} was scattered on the soil.", GameData::Item.get(mulch).name))
        return
      when 1
        ask_to_plant = false
      else
        return
      end
    end
  else
    return unless pbConfirmMessage(_INTL("It's soft, loamy soil. Want to plant a berry?"))
    ask_to_plant = false
  end
  if !ask_to_plant || pbConfirmMessage(_INTL("Want to plant a Berry?"))
    berry = nil
    pbFadeOutIn do
      scene  = PokemonBag_Scene.new
      screen = PokemonBagScreen.new(scene, $bag)
      berry  = screen.pbChooseItemScreen(proc { |item| GameData::Item.get(item).is_berry? })
    end
    if berry
      interp.setVariable(crop)
      $stats.berries_planted += 1
      crop.plant(berry)
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
  end
end

#===============================================================================
# Opens the bag filtered to plantable items + mulch for the Spreader.
# Caches the result in spreader_loaded_item. Returns nil if cancelled.
#===============================================================================
def pbSpreaderGetItem
  loaded = $PokemonGlobal.spreader_loaded_item
  return loaded if loaded && $bag.has?(loaded)
  chosen = nil
  pbFadeOutIn do
    scene  = PokemonBag_Scene.new
    screen = PokemonBagScreen.new(scene, $bag)
    chosen = screen.pbChooseItemScreen(proc { |item|
      d = GameData::Item.get(item)
      d.is_plantable? || d.is_mulch?
    })
  end
  if chosen
    $PokemonGlobal.spreader_loaded_item = chosen
    return chosen
  end
  $PokemonGlobal.spreader_loaded_item = nil
  pbMessage(_INTL("The Spreader has been put away."))
  return nil
end

#===============================================================================
# Prompts the player to pick ripe berries. Delegates to pbPickCrop.
#===============================================================================
def pbPickBerry(berry, qty = 1)
  return pbPickCrop(berry, qty)
end
