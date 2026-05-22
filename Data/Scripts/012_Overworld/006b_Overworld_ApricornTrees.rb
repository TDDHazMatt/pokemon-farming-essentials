#===============================================================================
# Represents a planted apricorn tree. Stored in $PokemonGlobal.eventvars.
# Simpler than BerryPlantData: no watering or moisture mechanics. Trees grow
# on their own and reset to empty soil after being picked, just like berries.
#===============================================================================
class ApricornTreeData
  attr_accessor :apricorn_id
  attr_accessor :time_alive
  attr_accessor :time_last_updated
  attr_accessor :growth_stage
  attr_accessor :replant_count

  def initialize
    reset
  end

  def reset
    @apricorn_id       = nil
    @time_alive        = 0
    @time_last_updated = 0
    @growth_stage      = 0
    @replant_count     = 0
  end

  def plant(apricorn_id)
    reset
    @apricorn_id       = apricorn_id
    @growth_stage      = 1
    @time_last_updated = pbGetTimeNow.to_i
  end

  def replant
    @time_alive    = 0
    @growth_stage  = 2
    @replant_count += 1
  end

  def planted?
    return @growth_stage > 0
  end

  def growing?
    return @growth_stage > 0 && @growth_stage < 5
  end

  def grown?
    return @growth_stage >= 5
  end

  def replanted?
    return @replant_count > 0
  end

  def apricorn_yield
    data = GameData::ApricornTree.get(@apricorn_id)
    return data.minimum_yield + rand(1 + data.maximum_yield - data.minimum_yield)
  end

  def update
    return if !planted?
    time_now = pbGetTimeNow
    time_delta = time_now.to_i - @time_last_updated
    return if time_delta <= 0
    new_time_alive = @time_alive + time_delta
    # Get all growth data
    tree_data      = GameData::ApricornTree.get(@apricorn_id)
    time_per_stage = tree_data.hours_per_stage * 3600
    max_replants   = GameData::ApricornTree::NUMBER_OF_REPLANTS
    stages_growing = GameData::ApricornTree::NUMBER_OF_GROWTH_STAGES
    stages_full    = GameData::ApricornTree::NUMBER_OF_FULLY_GROWN_STAGES
    # Auto-replant loop: if the harvest window passes, the tree cycles again
    loop do
      stages_this_life = stages_growing + stages_full - (replanted? ? 1 : 0)
      break if new_time_alive < stages_this_life * time_per_stage
      if @replant_count >= max_replants
        reset
        return
      end
      replant
      new_time_alive -= stages_this_life * time_per_stage
    end
    # Advance growth stage based on accumulated time
    @time_alive        = new_time_alive
    @growth_stage      = 1 + (@time_alive / time_per_stage)
    @growth_stage     += 1 if replanted?   # Replants skip the "just planted" stage
    @time_last_updated = time_now.to_i
  end
end

#===============================================================================
# Sprite that manages the overworld graphic for a planted apricorn tree event.
# Expected character sheet names:
#   apricorntreeplanted        — generic sapling (stage 1, all types)
#   apricorntree_REDAPRICORN   — per-type sheet (stages 2-5+)
# Sheet layout (same as berry tree sheets):
#   down = stage 2, left = stage 3, right = stage 4, up = stage 5+ (ripe)
#===============================================================================
class ApricornTreeSprite
  def initialize(event, map, _viewport)
    @event     = event
    @map       = map
    @old_stage = 0
    @disposed  = false
    tree = event.variable
    return if !tree
    @old_stage = tree.growth_stage
    @event.character_name = ""
    tree.update if tree.planted?
    set_event_graphic(tree, true)
  end

  def dispose
    @event    = nil
    @map      = nil
    @disposed = true
  end

  def disposed?
    @disposed
  end

  def set_event_graphic(tree, full_check = false)
    return if !tree || (tree.growth_stage == @old_stage && !full_check)
    case tree.growth_stage
    when 0
      @event.character_name = ""
    else
      if tree.growth_stage == 1
        @event.character_name = "apricorntreeplanted"
        @event.turn_down
      else
        filename = sprintf("apricorntree_%s", GameData::Item.get(tree.apricorn_id).id.to_s)
        if pbResolveBitmap("Graphics/Characters/" + filename)
          @event.character_name = filename
          case tree.growth_stage
          when 2 then @event.turn_down
          when 3 then @event.turn_left
          when 4 then @event.turn_right
          else
            @event.turn_up if tree.growth_stage >= 5
          end
        else
          @event.character_name = "Object ball"
        end
      end
      if @old_stage != tree.growth_stage && @old_stage > 0 &&
         tree.growth_stage <= GameData::ApricornTree::NUMBER_OF_GROWTH_STAGES + 1
        spriteset = $scene.spriteset(@map.map_id)
        spriteset&.addUserAnimation(Settings::PLANT_SPARKLE_ANIMATION_ID,
                                    @event.x, @event.y, false, 1)
      end
    end
    @old_stage = tree.growth_stage
  end

  def update
    tree = @event.variable
    return if !tree
    tree.update if tree.planted?
    set_event_graphic(tree)
  end
end

#===============================================================================
# Hook: create ApricornTreeSprite for every event named /apricorntree/i.
#===============================================================================
EventHandlers.add(:on_new_spriteset_map, :add_apricorn_tree_graphics,
  proc { |spriteset, viewport|
    map = spriteset.map
    map.events.each do |event|
      next if !event[1].name[/apricorntree/i]
      spriteset.addUserSprite(ApricornTreeSprite.new(event[1], map, viewport))
    end
  }
)

#===============================================================================
# Main interaction function. Call this from an apricorn tree event's script box.
#===============================================================================
def pbApricornTree
  interp     = pbMapInterpreter
  this_event = interp.get_self
  tree       = interp.getVariable
  if !tree
    tree = ApricornTreeData.new
    interp.setVariable(tree)
  end
  apricorn = tree.apricorn_id
  # Interact based on growth stage
  if tree.grown?
    this_event.turn_up
    tree.reset if pbPickApricorn(apricorn, tree.apricorn_yield)
    return
  elsif tree.growing?
    apricorn_name = GameData::Item.get(apricorn).name
    case tree.growth_stage
    when 1
      this_event.turn_down
      if apricorn_name.starts_with_vowel?
        pbMessage(_INTL("An {1} tree was planted here.", apricorn_name))
      else
        pbMessage(_INTL("A {1} tree was planted here.", apricorn_name))
      end
    when 2
      this_event.turn_down
      pbMessage(_INTL("The {1} tree has sprouted.", apricorn_name))
    when 3
      this_event.turn_left
      pbMessage(_INTL("The {1} tree is growing taller.", apricorn_name))
    else
      this_event.turn_right
      pbMessage(_INTL("The {1} tree is bearing fruit!", apricorn_name))
    end
    return
  end
  # Nothing planted — offer to plant
  return if !pbConfirmMessage(_INTL("It's soft, loamy soil. Want to plant an Apricorn?"))
  apricorn = nil
  pbFadeOutIn do
    scene    = PokemonBag_Scene.new
    screen   = PokemonBagScreen.new(scene, $bag)
    apricorn = screen.pbChooseItemScreen(proc { |item| GameData::Item.get(item).is_apricorn? })
  end
  if apricorn
    $stats.apricorns_planted += 1
    tree.plant(apricorn)
    $bag.remove(apricorn)
    apricorn_name = GameData::Item.get(apricorn).name
    if apricorn_name.starts_with_vowel?
      pbMessage(_INTL("{1} planted an {2} in the soft loamy soil.",
                      $player.name, apricorn_name))
    else
      pbMessage(_INTL("{1} planted a {2} in the soft loamy soil.",
                      $player.name, apricorn_name))
    end
  end
end

#===============================================================================
# Prompts the player to pick ripe apricorns. Returns true if they were picked.
#===============================================================================
def pbPickApricorn(apricorn, qty = 1)
  apricorn      = GameData::Item.get(apricorn)
  apricorn_name = (qty > 1) ? apricorn.portion_name_plural : apricorn.portion_name
  if qty > 1
    message = _INTL("There are {1} \\c[1]{2}\\c[0]!\nWant to pick them?", qty, apricorn_name)
  else
    message = _INTL("There is 1 \\c[1]{1}\\c[0]!\nWant to pick it?", apricorn_name)
  end
  return false if !pbConfirmMessage(message)
  if !$bag.can_add?(apricorn, qty)
    pbMessage(_INTL("Too bad...\nThe Bag is full..."))
    return false
  end
  $stats.apricorns_picked += 1
  $bag.add(apricorn, qty)
  if qty > 1
    pbMessage("\\me[Berry get]" + _INTL("You picked {1} \\c[1]{2}\\c[0].", qty, apricorn_name) + "\\wtnp[30]")
  else
    pbMessage("\\me[Berry get]" + _INTL("You picked the \\c[1]{1}\\c[0].", apricorn_name) + "\\wtnp[30]")
  end
  pocket = apricorn.pocket
  pbMessage(_INTL("You put the {1} in\\nyour Bag's <icon=bagPocket{2}>\\c[1]{3}\\c[0] pocket.",
                  apricorn_name, pocket, PokemonBag.pocket_names[pocket - 1]) + "\1")
  pbMessage(_INTL("The soil returned to its soft and loamy state."))
  this_event = pbMapInterpreter.get_self
  pbSetSelfSwitch(this_event.id, "A", true)
  return true
end
