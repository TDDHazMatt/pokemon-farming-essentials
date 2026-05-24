#===============================================================================
# Stub class kept for Marshal compatibility with old save files.
# The v22 conversion migrates all instances to CropData automatically on load.
#===============================================================================
class ApricornTreeData
  attr_accessor :apricorn_id, :time_alive, :time_last_updated
  attr_accessor :growth_stage, :replant_count

  def initialize
    @apricorn_id       = nil
    @time_alive        = 0
    @time_last_updated = 0
    @growth_stage      = 0
    @replant_count     = 0
  end

  def planted?; return @growth_stage > 0; end
end

#===============================================================================
# Backward-compatibility wrapper. Map events that call pbApricornTree directly
# continue to work; they use CropData + pbInteractWithCrop internally.
#===============================================================================
def pbApricornTree
  interp     = pbMapInterpreter
  this_event = interp.get_self
  crop = interp.getVariable
  # Migrate legacy ApricornTreeData instances to CropData on first touch.
  if crop.is_a?(ApricornTreeData)
    new_crop = CropData.new
    if crop.planted?
      new_crop.crop_id           = crop.apricorn_id
      new_crop.time_alive        = crop.time_alive
      new_crop.time_last_updated = crop.time_last_updated
      new_crop.growth_stage      = crop.growth_stage
      new_crop.replant_count     = crop.replant_count
      new_crop.moisture_level    = 100
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
      if item_data.is_apricorn?
        interp.setVariable(crop)
        $stats.apricorns_planted += 1
        crop.plant(loaded)
        $bag.remove(loaded)
      else
        $PokemonGlobal.spreader_loaded_item = nil
      end
    end
    return
  end
  return unless pbConfirmMessage(_INTL("It's soft, loamy soil. Want to plant an Apricorn?"))
  apricorn = nil
  pbFadeOutIn do
    scene    = PokemonBag_Scene.new
    screen   = PokemonBagScreen.new(scene, $bag)
    apricorn = screen.pbChooseItemScreen(proc { |item| GameData::Item.get(item).is_apricorn? })
  end
  if apricorn
    interp.setVariable(crop)
    $stats.apricorns_planted += 1
    crop.plant(apricorn)
    $bag.remove(apricorn)
    apricorn_name = GameData::Item.get(apricorn).name
    if apricorn_name.starts_with_vowel?
      pbMessage(_INTL("{1} planted an {2} in the soft loamy soil.", $player.name, apricorn_name))
    else
      pbMessage(_INTL("{1} planted a {2} in the soft loamy soil.", $player.name, apricorn_name))
    end
  end
end

#===============================================================================
# Prompts the player to pick ripe apricorns. Delegates to pbPickCrop.
#===============================================================================
def pbPickApricorn(apricorn, qty = 1)
  return pbPickCrop(apricorn, qty)
end
