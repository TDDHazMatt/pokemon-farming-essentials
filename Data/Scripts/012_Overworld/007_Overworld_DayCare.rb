#===============================================================================
# NOTE: In Gen 7+, the Day Care is replaced by the Pokémon Nursery, which works
#       in much the same way except deposited Pokémon no longer gain Exp because
#       of the player walking around and, in Gen 8+, deposited Pokémon are able
#       to learn egg moves from each other if they are the same species. In
#       Essentials, this code can be used for both facilities, and these
#       mechanics differences are set by some Settings.
# NOTE: The Day Care has a different price than the Pokémon Nursery. For the Day
#       Care, you are charged when you withdraw a deposited Pokémon and you pay
#       an amount based on how many levels it gained. For the Nursery, you pay
#       $500 up-front when you deposit a Pokémon. This difference will appear in
#       the Day Care Lady's event, not in these scripts.
#===============================================================================
class DayCare
  #=============================================================================
  # Code that generates an egg based on two given Pokémon.
  #
  # Signature change from original:
  #   generate(mother, father)            → generate(mother, father, pair, unlocks)
  #   set_shininess(egg, mother, father)  → set_shininess(egg, mother, father, unlocks)
  #   inherit_moves / inherit_IVs now receive `pair` for future modifier-item hooks.
  # Everything else is identical to the Essentials v21.1 original.
  #=============================================================================
  module EggGenerator
    module_function

    def generate(mother, father, pair, unlocks)
      if mother.male? || father.female? || mother.genderless?
        mother, father = father, mother
      end
      mother_data = [mother, mother.species_data.egg_groups.include?(:Ditto)]
      father_data = [father, father.species_data.egg_groups.include?(:Ditto)]
      species_parent = (mother_data[1]) ? father : mother
      baby_species = determine_egg_species(species_parent.species, mother, father)
      mother_data.push(mother.species_data.breeding_can_produce?(baby_species))
      father_data.push(father.species_data.breeding_can_produce?(baby_species))
      egg = generate_basic_egg(baby_species)
      inherit_form(egg, species_parent, mother_data, father_data)
      inherit_nature(egg, mother, father)
      inherit_ability(egg, mother_data, father_data)
      inherit_moves(egg, mother_data, father_data, pair)
      inherit_IVs(egg, mother, father, pair)
      inherit_poke_ball(egg, mother_data, father_data)
      set_shininess(egg, mother, father, unlocks)
      set_pokerus(egg)
      egg.calc_stats
      return egg
    end

    def determine_egg_species(parent_species, mother, father)
      ret = GameData::Species.get(parent_species).get_baby_species(true, mother.item_id, father.item_id)
      offspring = GameData::Species.get(ret).offspring
      ret = offspring.sample if offspring.length > 0
      return ret
    end

    def generate_basic_egg(species)
      egg = Pokemon.new(species, Settings::EGG_LEVEL)
      egg.name           = _INTL("Egg")
      egg.steps_to_hatch = egg.species_data.hatch_steps
      egg.obtain_text    = _INTL("Day-Care Couple")
      egg.happiness      = 120
      egg.form           = 0 if species == :SINISTEA
      new_form = MultipleForms.call("getFormOnEggCreation", egg)
      egg.form = new_form if new_form
      return egg
    end

    def inherit_form(egg, species_parent, mother, father)
      if species_parent.species_data.has_flag?("InheritFormFromMother")
        egg.form = species_parent.form
      end
      [mother, father].each do |parent|
        next if !parent[2]
        next if !parent[0].species_data.has_flag?("InheritFormWithEverStone")
        next if !parent[0].hasItem?(:EVERSTONE)
        egg.form = parent[0].form
        break
      end
    end

    def get_moves_to_inherit(egg, mother, father)
      move_father = (father[1]) ? mother[0] : father[0]
      move_mother = (father[1]) ? father[0] : mother[0]
      moves = []
      egg.getMoveList.each do |move|
        next if move[0] <= egg.level
        next if !mother[0].hasMove?(move[1]) || !father[0].hasMove?(move[1])
        moves.push(move[1])
      end
      if Settings::BREEDING_CAN_INHERIT_MACHINE_MOVES && !move_father.female?
        GameData::Item.each do |i|
          move = i.move
          next if !move
          next if !move_father.hasMove?(move) || !egg.compatible_with_move?(move)
          moves.push(move)
        end
      end
      if !move_father.female?
        egg.species_data.egg_moves.each do |move|
          moves.push(move) if move_father.hasMove?(move)
        end
      end
      if Settings::BREEDING_CAN_INHERIT_EGG_MOVES_FROM_MOTHER && move_mother.female?
        egg.species_data.egg_moves.each do |move|
          moves.push(move) if move_mother.hasMove?(move)
        end
      end
      if egg.species == :PICHU && GameData::Move.exists?(:VOLTTACKLE) &&
         ((father[2] && father[0].hasItem?(:LIGHTBALL)) ||
          (mother[2] && mother[0].hasItem?(:LIGHTBALL)))
        moves.push(:VOLTTACKLE)
      end
      return moves
    end

    # pair is accepted for future move-pinning modifier items; unused for now.
    def inherit_moves(egg, mother, father, pair)
      moves = get_moves_to_inherit(egg, mother, father)
      moves = moves.reverse
      moves |= []
      moves = moves.reverse
      first_move_index = moves.length - Pokemon::MAX_MOVES
      first_move_index = 0 if first_move_index < 0
      (first_move_index...moves.length).each { |i| egg.learn_move(moves[i]) }
    end

    def inherit_nature(egg, mother, father)
      new_natures = []
      new_natures.push(mother.nature) if mother.hasItem?(:EVERSTONE)
      new_natures.push(father.nature) if father.hasItem?(:EVERSTONE)
      return if new_natures.empty?
      egg.nature = new_natures.sample
    end

    def inherit_ability(egg, mother, father)
      parent = (mother[1]) ? father[0] : mother[0]
      if parent.hasHiddenAbility?
        egg.ability_index = parent.ability_index if rand(100) < 60
      elsif rand(100) < 80
        egg.ability_index = parent.ability_index
      else
        egg.ability_index = (parent.ability_index + 1) % 2
      end
    end

    # pair is accepted for future IV-pinning modifier items; unused for now.
    def inherit_IVs(egg, mother, father, pair)
      stats = []
      GameData::Stat.each_main { |s| stats.push(s.id) }
      inherit_count = 3
      if Settings::MECHANICS_GENERATION >= 6
        inherit_count = 5 if mother.hasItem?(:DESTINYKNOT) || father.hasItem?(:DESTINYKNOT)
      end
      power_items = [
        [:POWERWEIGHT, :HP],
        [:POWERBRACER, :ATTACK],
        [:POWERBELT,   :DEFENSE],
        [:POWERLENS,   :SPECIAL_ATTACK],
        [:POWERBAND,   :SPECIAL_DEFENSE],
        [:POWERANKLET, :SPEED]
      ]
      power_stats = {}
      [mother, father].each do |parent|
        power_items.each do |item|
          next if !parent.hasItem?(item[0])
          power_stats[item[1]] ||= []
          power_stats[item[1]].push(parent.iv[item[1]])
          break
        end
      end
      power_stats.each_pair do |stat, new_stats|
        next if !new_stats || new_stats.length == 0
        egg.iv[stat] = new_stats.sample
        stats.delete(stat)
        inherit_count -= 1
      end
      chosen_stats = stats.sample(inherit_count)
      chosen_stats.each { |stat| egg.iv[stat] = [mother, father].sample.iv[stat] }
    end

    def inherit_poke_ball(egg, mother, father)
      balls = []
      [mother, father].each do |parent|
        balls.push(parent[0].poke_ball) if parent[2]
      end
      balls.delete(:MASTERBALL)
      balls.delete(:CHERISHBALL)
      egg.poke_ball = balls.sample if !balls.empty?
    end

    # unlocks.shiny_bonus stacks extra rerolls on top of Masuda Method / Shiny Charm.
    def set_shininess(egg, mother, father, unlocks)
      shiny_retries = 0
      if father.owner.language != mother.owner.language
        shiny_retries += (Settings::MECHANICS_GENERATION >= 8) ? 6 : 5
      end
      shiny_retries += 2 if $bag.has?(:SHINYCHARM)
      shiny_retries += unlocks.shiny_bonus
      return if shiny_retries == 0
      shiny_retries.times do
        break if egg.shiny?
        egg.shiny = nil
        egg.personalID = rand(2**16) | (rand(2**16) << 16)
      end
    end

    def set_pokerus(egg)
      egg.givePokerus if rand(65_536) < Settings::POKERUS_CHANCE
    end
  end

  #=============================================================================
  # A slot in the Day Care, which can contain a Pokémon.
  # Unchanged from Essentials v21.1 original.
  #=============================================================================
  class DayCareSlot
    attr_reader :pokemon

    def initialize
      reset
    end

    def reset
      @pokemon = nil
      @initial_level = 0
    end

    def deposit(pkmn)
      @pokemon = pkmn
      @pokemon.heal
      @pokemon.form = 0 if @pokemon.isSpecies?(:SHAYMIN)
      @initial_level = pkmn.level
    end

    def filled?
      return !@pokemon.nil?
    end

    def pokemon_name
      return (filled?) ? @pokemon.name : ""
    end

    def level_gain
      return (filled?) ? @pokemon.level - @initial_level : 0
    end

    def cost
      return (level_gain + 1) * 100
    end

    def choice_text
      return nil if !filled?
      if @pokemon.male?
        return _INTL("{1} (♂, Lv.{2})", @pokemon.name, @pokemon.level)
      elsif @pokemon.female?
        return _INTL("{1} (♀, Lv.{2})", @pokemon.name, @pokemon.level)
      end
      return _INTL("{1} (Lv.{2})", @pokemon.name, @pokemon.level)
    end

    def add_exp(amount = 1)
      return if !filled?
      max_exp = @pokemon.growth_rate.maximum_exp
      return if @pokemon.exp >= max_exp
      old_level = @pokemon.level
      @pokemon.exp += amount
      return if @pokemon.level == old_level
      @pokemon.calc_stats
      move_list = @pokemon.getMoveList
      move_list.each { |move| @pokemon.learn_move(move[1]) if move[0] == @pokemon.level }
    end
  end

  #=============================================================================
  # DayCare instance — now owns an array of BreedingPair objects and a
  # DayCareUnlocks object.  All per-pair state (egg flag, step counter) lives
  # on the BreedingPair, not here.
  #=============================================================================

  attr_accessor :gain_exp

  def pairs
    @pairs ||= Array.new(Settings::MAX_BREEDING_PAIRS) { BreedingPair.new }
  end

  def unlocks
    @unlocks ||= DayCareUnlocks.new
  end

  def initialize
    @pairs    = Array.new(Settings::MAX_BREEDING_PAIRS) { BreedingPair.new }
    @unlocks  = DayCareUnlocks.new
    @gain_exp = Settings::DAY_CARE_POKEMON_GAIN_EXP_FROM_WALKING
  end

  # Array-style access by pair index.
  def [](pair_index)
    return @pairs[pair_index]
  end

  # Total Pokémon deposited in a given pair (defaults to pair 0 for backward compat).
  def count(pair_index = 0)
    return @pairs[pair_index].count
  end

  # Returns pairs (up to max_active_pairs) that have at least one Pokémon.
  def active_pairs
    return @pairs.first(@unlocks.max_active_pairs).select(&:any?)
  end

  def max_active_pairs
    return @unlocks.max_active_pairs
  end

  def get_compatibility(pair_index = 0)
    return @pairs[pair_index].compatibility
  end

  def egg_generated?(pair_index = 0)
    return @pairs[pair_index].egg_generated
  end

  def reset_egg_counters(pair_index = 0)
    @pairs[pair_index].reset_egg_counters
  end

  def generate_egg(pair_index = 0)
    return @pairs[pair_index].generate_egg(@unlocks)
  end

  def update_on_step_taken
    @pairs.first(@unlocks.max_active_pairs).each do |pair|
      pair.update_on_step_taken(@unlocks, @gain_exp)
    end
  end

  #-----------------------------------------------------------------------------
  # Class methods — called by NPC events via pbDayCare* script commands.
  # All accept an optional pair_index (default 0) for backward compatibility.
  #-----------------------------------------------------------------------------

  def self.count(pair_index = 0)
    return $PokemonGlobal.day_care.count(pair_index)
  end

  def self.egg_generated?(pair_index = 0)
    return $PokemonGlobal.day_care.egg_generated?(pair_index)
  end

  def self.reset_egg_counters(pair_index = 0)
    $PokemonGlobal.day_care.reset_egg_counters(pair_index)
  end

  # slot_index: which slot within the pair (0 or 1).  pair_index defaults to 0.
  def self.get_details(slot_index, name_var, cost_var, pair_index = 0)
    slot = $PokemonGlobal.day_care[pair_index].slot(slot_index)
    $game_variables[name_var] = slot.pokemon_name if name_var > 0
    $game_variables[cost_var] = slot.cost         if cost_var > 0
  end

  def self.get_level_gain(slot_index, name_var, level_var, pair_index = 0)
    slot = $PokemonGlobal.day_care[pair_index].slot(slot_index)
    $game_variables[name_var]  = slot.pokemon_name if name_var > 0
    $game_variables[level_var] = slot.level_gain   if level_var > 0
  end

  def self.get_compatibility(compat_var, pair_index = 0)
    $game_variables[compat_var] = $PokemonGlobal.day_care.get_compatibility(pair_index) if compat_var > 0
  end

  # Deposits party[party_index] into the first empty slot of pair_index.
  def self.deposit(party_index, pair_index = 0)
    $stats.day_care_deposits += 1
    day_care = $PokemonGlobal.day_care
    pair     = day_care[pair_index]
    pkmn     = $player.party[party_index]
    raise _INTL("No Pokémon at index {1} in party.", party_index) if pkmn.nil?
    slot_index = pair.first_empty_slot_index
    raise _INTL("No room to deposit a Pokémon in this pair.") if slot_index.nil?
    pair.slot(slot_index).deposit(pkmn)
    $player.party.delete_at(party_index)
    pair.reset_egg_counters
  end

  # slot_index: which slot within the pair (0 or 1).  pair_index defaults to 0.
  def self.withdraw(slot_index, pair_index = 0)
    day_care = $PokemonGlobal.day_care
    slot     = day_care[pair_index].slot(slot_index)
    raise _INTL("No Pokémon found in pair {1} slot {2}.", pair_index, slot_index) unless slot.filled?
    raise _INTL("No room in party for Pokémon.") if $player.party_full?
    $stats.day_care_levels_gained += slot.level_gain
    $player.party.push(slot.pokemon)
    slot.reset
    day_care[pair_index].reset_egg_counters
  end

  # Lets the player choose a slot from the given pair.  choice_var receives the
  # slot index (0 or 1) or -1 if cancelled.
  def self.choose(message, choice_var, pair_index = 0)
    pair = $PokemonGlobal.day_care[pair_index]
    case pair.count
    when 0
      raise _INTL("No Pokémon found in Day Care to choose from.")
    when 1
      [0, 1].each { |i| $game_variables[choice_var] = i if pair.slot(i).filled? }
    else
      commands = []
      indices  = []
      [0, 1].each do |i|
        text = pair.slot(i).choice_text
        next if !text
        commands << text
        indices  << i
      end
      commands << _INTL("CANCEL")
      command = pbMessage(message, commands, commands.length)
      $game_variables[choice_var] = (command == commands.length - 1) ? -1 : indices[command]
    end
  end

  def self.collect_egg(pair_index = 0)
    day_care = $PokemonGlobal.day_care
    egg      = day_care.generate_egg(pair_index)
    raise _INTL("Couldn't generate the egg.")  if egg.nil?
    raise _INTL("No room in party for egg.")   if $player.party_full?
    $player.party.push(egg)
    day_care.reset_egg_counters(pair_index)
  end
end

#===============================================================================
# With each step taken, advance all active breeding pairs.
#===============================================================================
EventHandlers.add(:on_player_step_taken, :update_day_care,
  proc {
    $PokemonGlobal.day_care.update_on_step_taken
  }
)

#===============================================================================
# Shorthand for NPC event scripts.
# Usage: pbDayCareUnlock.unlock_extra_pair
#        pbDayCareUnlock.add_speed_bonus(1)
#        pbDayCareUnlock.add_shiny_bonus(2)
#===============================================================================
def pbDayCareUnlock
  return $PokemonGlobal.day_care.unlocks
end

#===============================================================================
# Prompts the player to choose which breeding pair to interact with.
# Returns the chosen pair index (0-based), or -1 if cancelled.
# When only one pair is active, returns 0 immediately with no menu shown.
#
# Usage in NPC event Script box:
#   $game_variables[VAR] = pbDayCareChoosePair
# Then branch on VAR == -1 (cancelled) or use VAR as pair_index in all
# DayCare.* calls (deposit, withdraw, egg_generated?, collect_egg, etc.)
#===============================================================================
# Short form: pbChoosePair(var_id) — stores result in $game_variables[var_id]
def pbChoosePair(var_id)
  $game_variables[var_id] = pbDayCareChoosePair
end

def pbDayCareChoosePair
  day_care   = $PokemonGlobal.day_care
  max_active = day_care.unlocks.max_active_pairs
  return 0 if max_active <= 1

  commands = []
  max_active.times do |i|
    pair  = day_care[i]
    count = pair.count
    egg   = pair.egg_generated ? " [Egg!]" : ""
    label = case count
            when 0 then _INTL("Pair {1} — Empty", i + 1)
            when 1 then _INTL("Pair {1} — 1 Pokémon{2}", i + 1, egg)
            when 2 then _INTL("Pair {1} — 2 Pokémon{2}", i + 1, egg)
            end
    commands << label
  end
  commands << _INTL("Cancel")

  choice = pbMessage(_INTL("Which pair?"), commands, commands.length)
  return -1 if choice == commands.length - 1
  return choice
end

#===============================================================================
# Egg helpers for NPC event scripts.
#
# pbDayCareAnyEgg?
#   Use in a Conditional Branch (Script) to check if any pair has an egg ready.
#
# pbCollectEgg(var_id)
#   Handles the full collection flow:
#     - If one pair has an egg: collects it immediately.
#     - If multiple pairs have eggs: shows a menu so the player picks which one.
#     - If party is full: stores -2 in var_id, does nothing.
#     - If player cancels (multi-egg menu): stores -1 in var_id.
#     - On success: stores 1 in var_id.
#
#   NPC event branch on var_id:
#     == 1   → "Here's your egg!" message, hand off egg
#     == -2  → "Your party is full, come back later."
#     == -1  → player changed their mind (already handled cancel text in event)
#===============================================================================
def pbDayCareAnyEgg?
  day_care = $PokemonGlobal.day_care
  day_care.unlocks.max_active_pairs.times.any? { |i| day_care[i].egg_generated }
end

def pbCollectEgg(var_id)
  day_care   = $PokemonGlobal.day_care
  max_active = day_care.unlocks.max_active_pairs
  ready      = (0...max_active).select { |i| day_care[i].egg_generated }

  if ready.empty?
    $game_variables[var_id] = 0
    return
  end

  if ready.length == 1
    pair_index = ready[0]
  else
    commands = ready.map { |i|
      pair = day_care[i]
      _INTL("Pair {1} ({2} Pokémon)", i + 1, pair.count)
    }
    commands << _INTL("Cancel")
    choice = pbMessage(
      _INTL("Eggs are ready in multiple pairs!\nWhich would you like to take?"),
      commands, commands.length
    )
    if choice == commands.length - 1
      $game_variables[var_id] = -1
      return
    end
    pair_index = ready[choice]
  end

  if $player.party_full?
    $game_variables[var_id] = -2
    return
  end

  DayCare.collect_egg(pair_index)
  $game_variables[var_id] = 1
end

#===============================================================================
# DEBUG — force egg ready on every active pair that has 2 deposited Pokémon.
# If no pair has 2 Pokémon, forces pair 0 regardless (for quick testing).
# Call from a Script event box: pbDebugForceEgg
#===============================================================================
def pbDebugForceEgg
  day_care   = $PokemonGlobal.day_care
  max_active = day_care.unlocks.max_active_pairs
  forced     = []
  max_active.times do |i|
    pair = day_care[i]
    if pair.has_pair?
      pair.egg_generated = true
      forced << i + 1
    end
  end
  if forced.empty?
    day_care[0].egg_generated = true
    pbMessage(_INTL("[DEBUG] Forced egg on Pair 1 (no full pairs found)."))
  else
    pbMessage(_INTL("[DEBUG] Egg forced on Pair(s): {1}", forced.join(", ")))
  end
end
