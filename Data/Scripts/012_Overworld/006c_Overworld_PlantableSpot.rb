#===============================================================================
# Universal plantable-soil interaction. Call pbPlantableSpot from an overworld
# event's script box. The event name must match /plantablespot/i for the
# combined sprite hook.
#
# New crops only require a PBS entry in crop_plants.txt, a sprite sheet, and a
# Plantable-flagged item — no new interaction code needed.
#===============================================================================
def pbPlantableSpot
  interp     = pbMapInterpreter
  plant_data = interp.getVariable

  if plant_data.is_a?(CropData) && plant_data.planted?
    pbInteractWithCrop(plant_data)
    after = interp.getVariable
    if after.is_a?(CropData) && !after.planted?
      interp.setVariable(nil)
      pbSetSelfSwitch(interp.get_self.id, "A", false)
    end
    return
  end

  # Preserve pre-fertilized soil (mulch applied, not yet planted).
  # Clear anything else that is stale (dead plant data, wrong type, etc.).
  mulch_only = plant_data.is_a?(CropData) && !plant_data.planted? && plant_data.mulch_id
  if plant_data && !mulch_only
    interp.setVariable(nil)
    plant_data = nil
  end
  mulch_on_soil = mulch_only ? plant_data.mulch_id : nil

  # ── Spreader path ──────────────────────────────────────────────────────────
  if $PokemonGlobal.spreader_loaded_item
    loaded = $PokemonGlobal.spreader_loaded_item
    loaded = pbSpreaderGetItem if !loaded || !$bag.has?(loaded)
    return unless loaded
    item_data = GameData::Item.get(loaded)
    if item_data.is_mulch?
      if mulch_on_soil && mulch_on_soil == loaded
        # Same mulch already applied — inform and re-open spreader bag so the
        # player can pick a seed or a different mulch.
        pbMessage(_INTL("{1} is already spread on this soil.", item_data.name))
        $PokemonGlobal.spreader_loaded_item = nil
        new_loaded = pbSpreaderGetItem
        pbPlantCrop(new_loaded) if new_loaded
      else
        # Different (or no) mulch — apply/overwrite silently.
        crop = mulch_only ? plant_data : CropData.new
        crop.mulch_id = loaded
        $bag.remove(loaded)
        interp.setVariable(crop)
      end
    elsif item_data.is_plantable?
      pbPlantCrop(loaded)
    else
      $PokemonGlobal.spreader_loaded_item = nil
    end
    return
  end

  # ── Normal path ────────────────────────────────────────────────────────────
  if mulch_on_soil
    mulch_name = GameData::Item.get(mulch_on_soil).name
    return unless pbConfirmMessage(
      _INTL("It's soft soil with {1} spread on it.\nWould you like to plant something?", mulch_name)
    )
    chosen = nil
    pbFadeOutIn do
      scene  = PokemonBag_Scene.new
      screen = PokemonBagScreen.new(scene, $bag)
      chosen = screen.pbChooseItemScreen(proc { |item|
        d = GameData::Item.get(item)
        d.is_plantable? || d.is_mulch?
      })
    end
    pbPlantCrop(chosen) if chosen
    return
  end

  return unless pbConfirmMessage(_INTL("It's soft, loamy soil.\nWant to plant something?"))
  chosen = nil
  pbFadeOutIn do
    scene  = PokemonBag_Scene.new
    screen = PokemonBagScreen.new(scene, $bag)
    chosen = screen.pbChooseItemScreen(proc { |item|
      d = GameData::Item.get(item)
      d.is_plantable? || d.is_mulch?
    })
  end
  pbPlantCrop(chosen) if chosen
end

#===============================================================================
# Plants any plantable item or mulch into the current event's soil.
# Handles the mulch-first flow when Settings::NEW_BERRY_PLANTS is on.
#===============================================================================
def pbPlantCrop(item_id)
  interp    = pbMapInterpreter
  item_data = GameData::Item.get(item_id)

  if $PokemonGlobal.spreader_loaded_item
    loaded = pbSpreaderGetItem
    return unless loaded
    item_data = GameData::Item.get(loaded)
    existing  = interp.getVariable
    crop      = existing.is_a?(CropData) ? existing : CropData.new
    if item_data.is_mulch?
      crop.mulch_id = loaded
      $bag.remove(loaded)
      interp.setVariable(crop)
    elsif item_data.is_plantable?
      interp.setVariable(crop)
      $stats.berries_planted   += 1 if item_data.is_berry?
      $stats.apricorns_planted += 1 if item_data.is_apricorn?
      crop.plant(loaded)
      $bag.remove(loaded)
    else
      $PokemonGlobal.spreader_loaded_item = nil
    end
    return
  end

  if item_data.is_mulch?
    crop = CropData.new
    crop.mulch_id = item_id
    $bag.remove(item_id)
    interp.setVariable(crop)
    pbMessage(_INTL("The {1} was scattered on the soil.", item_data.name))
    return
  end

  # Actually plant the chosen item.
  existing = interp.getVariable
  crop = existing.is_a?(CropData) ? existing : CropData.new
  interp.setVariable(crop)
  $stats.berries_planted   += 1 if item_data.is_berry?
  $stats.apricorns_planted += 1 if item_data.is_apricorn?
  crop.plant(item_id)
  $bag.remove(item_id)
  item_name = item_data.name
  if Settings::NEW_BERRY_PLANTS
    pbMessage(_INTL("The {1} was planted in the soft, earthy soil.", item_name))
  elsif item_name.starts_with_vowel?
    pbMessage(_INTL("{1} planted an {2} in the soft loamy soil.", $player.name, item_name))
  else
    pbMessage(_INTL("{1} planted a {2} in the soft loamy soil.", $player.name, item_name))
  end
end

#===============================================================================
# Handles interaction with a planted crop (growing or grown).
# Called from pbPlantableSpot and from the backward-compat wrappers.
#===============================================================================
def pbInteractWithCrop(crop_data)
  interp    = pbMapInterpreter
  this_event = interp.get_self
  crop_def  = GameData::CropPlant.get(crop_data.crop_id)

  if crop_data.grown?
    this_event.turn_up
    if pbPickCrop(crop_data.crop_id, crop_data.crop_yield, crop_def)
      crop_data.reset(true)   # keep mulch for replanting
    end
    return
  end

  if crop_data.growing?
    item_name = GameData::Item.get(crop_data.crop_id).name
    case crop_data.growth_stage
    when 1
      this_event.turn_down
      if item_name.starts_with_vowel?
        pbMessage(_INTL("An {1} was planted here.", item_name))
      else
        pbMessage(_INTL("A {1} was planted here.", item_name))
      end
    when 2
      this_event.turn_down
      pbMessage(_INTL("The {1} has sprouted.", item_name))
    when 3
      this_event.turn_left
      pbMessage(_INTL("The {1} is growing.", item_name))
    else
      this_event.turn_right
      pbMessage(_INTL("The {1} is nearly ready!", item_name))
    end

    # Offer watering if this crop has moisture
    if crop_def.has_moisture?
      GameData::CropPlant::WATERING_CANS.each do |item|
        next if !$bag.has?(item)
        break if !pbConfirmMessage(_INTL("Want to water with the {1}?",
                                         GameData::Item.get(item).name))
        crop_data.water
        pbMessage("\\se[Water berry plant]" + _INTL("{1} watered the plant.", $player.name) + "\\wtnp[40]")
        pbMessage(_INTL("There! All happy!"))
        break
      end
    end
  end
end

#===============================================================================
# Prompts the player to pick a ripe crop. Returns true if picked.
#===============================================================================
def pbPickCrop(crop_id, qty, crop_def = nil)
  crop_def  ||= GameData::CropPlant.get(crop_id)
  harvest_id  = crop_def.harvest_item
  harvest     = GameData::Item.get(harvest_id)
  seed_data = GameData::Item.get(crop_id)
  if $PokemonGlobal.harvester_active
    if !$bag.can_add?(harvest, qty)
      pbMessage(_INTL("Too bad...\nThe Bag is full..."))
      return false
    end
    if seed_data.is_berry?
      $stats.berry_plants_picked   += 1
      $stats.max_yield_berry_plants += 1 if qty >= crop_def.maximum_yield
    end
    $stats.apricorns_picked += 1 if seed_data.is_apricorn?
    $bag.add(harvest, qty)
    pbSetSelfSwitch(pbMapInterpreter.get_self.id, "A", true)
    return true
  end
  harvest_name = (qty > 1) ? harvest.portion_name_plural : harvest.portion_name
  if qty > 1
    message = _INTL("There are {1} \\c[1]{2}\\c[0]!\nWant to pick them?", qty, harvest_name)
  else
    message = _INTL("There is 1 \\c[1]{1}\\c[0]!\nWant to pick it?", harvest_name)
  end
  return false if !pbConfirmMessage(message)
  if !$bag.can_add?(harvest, qty)
    pbMessage(_INTL("Too bad...\nThe Bag is full..."))
    return false
  end
  if seed_data.is_berry?
    $stats.berry_plants_picked    += 1
    $stats.max_yield_berry_plants += 1 if qty >= crop_def.maximum_yield
  end
  $stats.apricorns_picked += 1 if seed_data.is_apricorn?
  $bag.add(harvest, qty)
  if qty > 1
    pbMessage("\\me[Berry get]" + _INTL("You picked {1} \\c[1]{2}\\c[0].", qty, harvest_name) + "\\wtnp[30]")
  else
    pbMessage("\\me[Berry get]" + _INTL("You picked the \\c[1]{1}\\c[0].", harvest_name) + "\\wtnp[30]")
  end
  pocket = harvest.pocket
  pbMessage(_INTL("You put the {1} in\\nyour Bag's <icon=bagPocket{2}>\\c[1]{3}\\c[0] pocket.",
                  harvest_name, pocket, PokemonBag.pocket_names[pocket - 1]) + "\1")
  pbMessage(_INTL("The soil returned to its soft and loamy state."))
  this_event = pbMapInterpreter.get_self
  pbSetSelfSwitch(this_event.id, "A", true)
  return true
end

#===============================================================================
# Always-on sprite wrapper for /plantablespot/i events. Dynamically creates
# the correct sub-sprites whenever the type of planted data changes.
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
    when CropData
      @subsprites << CropMulchSprite.new(@event, @map, @viewport)
      @subsprites << CropMoistureSprite.new(@event, @map, @viewport)
      @subsprites << CropSprite.new(@event, @map, @viewport)
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
