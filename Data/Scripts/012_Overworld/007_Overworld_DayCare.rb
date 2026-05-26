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
  # Predicates that encapsulate all item and helper effect checks.  Both
  # EggGenerator and the debug display call these so the two can never drift
  # out of sync.
  #=============================================================================
  module PairEffects
    module_function

    POWER_ITEM_STATS = {
      POWERWEIGHT: :HP,
      POWERBRACER: :ATTACK,
      POWERBELT:   :DEFENSE,
      POWERLENS:   :SPECIAL_ATTACK,
      POWERBAND:   :SPECIAL_DEFENSE,
      POWERANKLET: :SPEED
    }.freeze

    KNOWN_INCENSE = %i[
      ROSEINCENSE SEAINCENSE WAVEINCENSE ROCKINCENSE
      ODDINCENSE LUCKINCENSE PUREINCENSE FULLINCENSE LAXINCENSE
    ].freeze

    # Cross-species mutation table: {[speciesA, speciesB] => result_species}
    # Order of the pair doesn't matter — checked bidirectionally.
    CROSS_SPECIES_MUTATIONS = {
      # Electric Rodents
      [:PIKACHU,    :MINUN]      => :PACHIRISU,
      [:PIKACHU,    :PLUSLE]     => :DEDENNE,
      [:MINUN,      :PLUSLE]     => :EMOLGA,
      # Fire Quadrupeds
      [:GROWLITHE,  :HOUNDOUR]   => :FLAREON,
      # Grass Starters
      [:BULBASAUR,  :CHIKORITA]  => :TREECKO,
      # Fire Starters
      [:CHARMANDER, :CYNDAQUIL]  => :TORCHIC,
      # Water Starters
      [:SQUIRTLE,   :TOTODILE]   => :MUDKIP,
      # Bug Types
      [:CATERPIE,   :WURMPLE]    => :SPINARAK,
      # Small Early Birds
      [:PIDGEY,     :TAILLOW]    => :STARLY,
      # Normal Rodents
      [:RATTATA,    :SENTRET]    => :ZIGZAGOON,
      # Fairy-Normal
      [:CLEFAIRY,   :JIGGLYPUFF] => :SNUBBULL,
      # Psychic
      [:ABRA,       :RALTS]      => :ESPURR,
    }.freeze

    # --- Helper-specific predicates (called by debug "Check effect") ---

    def helper_ditto_surrogate?(pair)
      return pair&.helper_pokemon&.isSpecies?(:DITTO) == true
    end

    def helper_everstone?(pair)
      return pair&.helper_pokemon&.hasItem?(:EVERSTONE) == true
    end

    def helper_destiny_knot?(pair)
      return pair&.helper_pokemon&.hasItem?(:DESTINYKNOT) == true
    end

    def helper_light_ball?(pair)
      return pair&.helper_pokemon&.hasItem?(:LIGHTBALL) == true
    end

    # Returns [[item_id, stat_sym]] for the helper's Power item, or [].
    def helper_power_items(pair)
      item_id = pair&.helper_pokemon&.item_id
      return [] unless item_id
      POWER_ITEM_STATS.each { |sym, stat| return [[item_id, stat]] if item_id == sym }
      return []
    end

    def helper_incense?(pair)
      item_id = pair&.helper_pokemon&.item_id
      return item_id ? KNOWN_INCENSE.include?(item_id) : false
    end

    def helper_ha_boost?(pair)
      helper = pair&.helper_pokemon
      return false unless helper
      return helper.types.include?(:PSYCHIC) && helper.hasMove?(:HIDDENPOWER)
    end

    # --- Combined predicates (called by EggGenerator) ---

    def ditto_surrogate?(pair)
      return helper_ditto_surrogate?(pair)
    end

    def everstone_active?(pair)
      return pair&.pair_item == :EVERSTONE || helper_everstone?(pair)
    end

    def destiny_knot_active?(pair)
      return pair&.pair_item == :DESTINYKNOT || helper_destiny_knot?(pair)
    end

    def light_ball_active?(pair)
      return pair&.pair_item == :LIGHTBALL || helper_light_ball?(pair)
    end

    # Returns [[item_id, stat_sym]] for the pair item's Power item, or [].
    def pair_item_power_items(pair)
      item_id = pair&.pair_item
      return [] unless item_id
      POWER_ITEM_STATS.each { |sym, stat| return [[item_id, stat]] if item_id == sym }
      return []
    end

    # Returns [[item_id, stat_sym]] for both pair item and helper, deduplicating by stat.
    def all_power_items(pair)
      return (pair_item_power_items(pair) + helper_power_items(pair)).uniq { |_id, stat| stat }
    end

    def ha_boost_active?(pair)
      return helper_ha_boost?(pair)
    end

    # Returns the mutation result species if the two species appear in
    # CROSS_SPECIES_MUTATIONS, nil otherwise. Same-species pairs are skipped.
    def check_mutation(species_a, species_b)
      return nil if species_a == species_b
      CROSS_SPECIES_MUTATIONS[[species_a, species_b]] ||
        CROSS_SPECIES_MUTATIONS[[species_b, species_a]]
    end

    # True if Mutagenic Incense is present anywhere in the breeding setup.
    def mutagenic_incense_active?(mother, father, pair)
      [pair&.pair_item,
       pair&.helper_pokemon&.item_id,
       mother.item_id,
       father.item_id].any? { |item| item == :MUTAGENICINCENSE }
    end
  end

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
      # Ditto helper as surrogate: neither pair member is Ditto, so randomly pick
      # either parent as the species parent instead of always defaulting to mother.
      if PairEffects.ditto_surrogate?(pair) && !mother_data[1] && !father_data[1]
        species_parent = [mother, father].sample
      end
      baby_species = determine_egg_species(species_parent.species, mother, father, pair)
      mother_data.push(mother.species_data.breeding_can_produce?(baby_species))
      father_data.push(father.species_data.breeding_can_produce?(baby_species))
      egg = generate_basic_egg(baby_species)
      inherit_form(egg, species_parent, mother_data, father_data)
      inherit_nature(egg, mother, father, pair)
      inherit_ability(egg, mother_data, father_data)
      apply_helper_ability_effects(egg, pair)
      inherit_moves(egg, mother_data, father_data, pair)
      inherit_IVs(egg, mother, father, pair)
      inherit_poke_ball(egg, mother_data, father_data)
      set_shininess(egg, mother, father, unlocks)
      set_pokerus(egg)
      egg.calc_stats
      return egg
    end

    def determine_egg_species(parent_species, mother, father, pair)
      # Check for incense/baby-species items in priority order:
      # pair slot → helper held → mother held, then father held as second argument.
      mother_side = pair&.pair_item || pair&.helper_pokemon&.item_id || mother.item_id
      ret = GameData::Species.get(parent_species).get_baby_species(true, mother_side, father.item_id)
      offspring = GameData::Species.get(ret).offspring
      ret = offspring.sample if offspring.length > 0
      # Cross-species mutation: check table when parents are different species.
      mutation = PairEffects.check_mutation(mother.species, father.species)
      if mutation && GameData::Species.exists?(mutation)
        chance = PairEffects.mutagenic_incense_active?(mother, father, pair) ? 1.0 : 0.25
        ret = mutation if rand < chance
      end
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

    def inherit_moves(egg, mother, father, pair)
      moves = get_moves_to_inherit(egg, mother, father)
      # pair item or helper Light Ball grants Volt Tackle to Pichu.
      if egg.species == :PICHU && GameData::Move.exists?(:VOLTTACKLE) && !moves.include?(:VOLTTACKLE)
        moves.push(:VOLTTACKLE) if PairEffects.light_ball_active?(pair)
      end
      moves = moves.reverse
      moves |= []
      moves = moves.reverse
      first_move_index = moves.length - Pokemon::MAX_MOVES
      first_move_index = 0 if first_move_index < 0
      (first_move_index...moves.length).each { |i| egg.learn_move(moves[i]) }
    end

    def inherit_nature(egg, mother, father, pair)
      new_natures = []
      new_natures.push(mother.nature) if mother.hasItem?(:EVERSTONE)
      new_natures.push(father.nature) if father.hasItem?(:EVERSTONE)
      # pair item or helper Everstone pins a randomly chosen parent's nature when neither parent holds one.
      if new_natures.empty?
        new_natures.push([mother, father].sample.nature) if PairEffects.everstone_active?(pair)
      end
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

    def inherit_IVs(egg, mother, father, pair)
      stats = []
      GameData::Stat.each_main { |s| stats.push(s.id) }
      inherit_count = 3
      if Settings::MECHANICS_GENERATION >= 6
        destiny_knot = mother.hasItem?(:DESTINYKNOT) || father.hasItem?(:DESTINYKNOT) ||
                       PairEffects.destiny_knot_active?(pair)
        inherit_count = 5 if destiny_knot
      end
      power_stats = {}
      [mother, father].each do |parent|
        PairEffects::POWER_ITEM_STATS.each do |item_sym, stat|
          next if !parent.hasItem?(item_sym)
          power_stats[stat] ||= []
          power_stats[stat].push(parent.iv[stat])
          break
        end
      end
      PairEffects.all_power_items(pair).each do |_item_id, stat|
        power_stats[stat] ||= []
        power_stats[stat].push([mother, father].sample.iv[stat])
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

    # Applies passive effects from the pair's helper Pokémon after normal inheritance.
    def apply_helper_ability_effects(egg, pair)
      egg.ability_index = 2 if PairEffects.ha_boost_active?(pair) && rand(100) < 60
      # Hook: ability-based effects (add new entries here as designed).
      # Hook: species-based effects beyond Ditto (add new entries here as designed).
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

  # Returns the helper Pokémon in the pair's helper slot, or nil.
  def helper_pokemon(pair_index = 0)
    return @pairs[pair_index]&.helper_pokemon
  end

  # Places pkmn into the pair's helper slot.  Raises if the slot is occupied.
  def set_helper(pkmn, pair_index = 0)
    raise _INTL("Pair {1} already has a helper Pokémon.", pair_index + 1) if @pairs[pair_index].helper_pokemon
    @pairs[pair_index].helper_pokemon = pkmn
  end

  # Removes and returns the helper Pokémon from the pair (nil if empty).
  def clear_helper(pair_index = 0)
    pkmn = @pairs[pair_index]&.helper_pokemon
    @pairs[pair_index].helper_pokemon = nil if @pairs[pair_index]
    return pkmn
  end

  # Takes party[party_index] and places it as the pair's helper.
  # Returns false if the helper slot feature is locked, the slot is occupied,
  # or the party index is invalid.
  def self.give_helper(party_index, pair_index = 0)
    day_care = $PokemonGlobal.day_care
    return false unless day_care.unlocks.helper_slot_unlocked_for?(pair_index)
    return false if day_care.helper_pokemon(pair_index)
    pkmn = $player.party[party_index]
    return false unless pkmn
    day_care.set_helper(pkmn, pair_index)
    $player.party.delete_at(party_index)
    return true
  end

  # Returns the helper Pokémon to the player's party.
  # Returns false if the slot was empty or the party is full.
  def self.return_helper(pair_index = 0)
    day_care = $PokemonGlobal.day_care
    return false if $player.party_full?
    pkmn = day_care.clear_helper(pair_index)
    return false unless pkmn
    $player.party.push(pkmn)
    return true
  end

  # Returns the item ID in the pair's item slot, or nil.
  def pair_item(pair_index = 0)
    return @pairs[pair_index]&.pair_item
  end

  # Places item_id into the pair's item slot.  Raises if the slot is occupied.
  def set_pair_item(item_id, pair_index = 0)
    raise _INTL("Pair {1} already has an item in its slot.", pair_index + 1) if @pairs[pair_index].pair_item
    @pairs[pair_index].pair_item = item_id
  end

  # Removes and returns the item from the pair's item slot (nil if empty).
  def clear_pair_item(pair_index = 0)
    item = @pairs[pair_index]&.pair_item
    @pairs[pair_index].pair_item = nil if @pairs[pair_index]
    return item
  end

  # Takes item_id from the player's bag and places it in the pair's slot.
  # Returns false if the item slot feature is not yet unlocked, the bag
  # doesn't contain the item, or the slot is already occupied.
  def self.give_item(item_id, pair_index = 0)
    day_care = $PokemonGlobal.day_care
    return false unless day_care.unlocks.pair_items_unlocked_for?(pair_index)
    return false if day_care.pair_item(pair_index)
    return false unless $bag.has?(item_id)
    $bag.remove(item_id, 1)
    day_care.set_pair_item(item_id, pair_index)
    return true
  end

  # Returns the pair's item to the player's bag.
  # Returns the item ID on success, nil if the slot was empty.
  def self.return_item(pair_index = 0)
    day_care = $PokemonGlobal.day_care
    item = day_care.clear_pair_item(pair_index)
    $bag.add(item) if item
    return item
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
# Pair item slot helpers for NPC event scripts.
#
# pbDayCareGiveItem(pair_index, item_id)
#   Takes item_id from the player's bag and places it in the pair's item slot.
#   Returns true on success, false if the slot is already occupied or the bag
#   doesn't contain the item.
#   NPC usage example (pair 0, Rose Incense):
#     pbDayCareGiveItem(0, :ROSEINCENSE)
#
# pbDayCareReturnItem(pair_index, var_id)
#   Returns the pair's item to the player's bag and stores its item ID in
#   var_id (stores nil if the slot was empty).
#   NPC usage example:
#     pbDayCareReturnItem(0, 5)   # result in $game_variables[5]
#
# pbDayCareItemName(pair_index)
#   Returns the display name of the item in the pair's slot, or nil.
#===============================================================================
#===============================================================================
# Helper Pokémon slot helpers for NPC event scripts.
#
# pbDayCareGiveHelper(pair_index, party_index)
#   Takes party[party_index] and places it as the pair's helper Pokémon.
#   Returns true on success, false if locked, occupied, or invalid index.
#
# pbDayCareReturnHelper(pair_index)
#   Returns the helper Pokémon to the player's party.
#   Returns false if the slot was empty or the party is full.
#
# pbDayCareHelperName(pair_index)
#   Returns the helper Pokémon's name (species), or nil if slot is empty.
#
# pbDayCareChooseHelper(pair_index, var_id)
#   Shows the party screen so the player can choose which Pokémon to place
#   as a helper.  Stores the chosen party index in var_id, or -1 if cancelled.
#===============================================================================
def pbDayCareGiveHelper(pair_index, party_index)
  return DayCare.give_helper(party_index, pair_index)
end

def pbDayCareReturnHelper(pair_index)
  return DayCare.return_helper(pair_index)
end

def pbDayCareHelperName(pair_index)
  pkmn = $PokemonGlobal.day_care.helper_pokemon(pair_index)
  return pkmn ? pkmn.name : nil
end

def pbDayCareChooseHelper(pair_index, var_id)
  pbChooseNonEggPokemon(var_id, 3)
end

#===============================================================================
def pbDayCareGiveItem(pair_index, item_id)
  return DayCare.give_item(item_id, pair_index)
end

def pbDayCareReturnItem(pair_index, var_id)
  item = DayCare.return_item(pair_index)
  $game_variables[var_id] = item
end

def pbDayCareItemName(pair_index)
  item = $PokemonGlobal.day_care.pair_item(pair_index)
  return item ? GameData::Item.get(item).name : nil
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
