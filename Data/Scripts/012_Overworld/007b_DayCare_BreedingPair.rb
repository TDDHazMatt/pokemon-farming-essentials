#===============================================================================
# DayCareUnlocks — modular flags representing what the player has unlocked for
# the Day Care.  All readers are nil-safe so that old saves that lack these
# instance variables still work after loading without a migration crash.
#
# Call the unlock helpers from NPC events, e.g.:
#   $PokemonGlobal.day_care.unlocks.unlock_extra_pair
#   $PokemonGlobal.day_care.unlocks.add_speed_bonus
#===============================================================================
class DayCareUnlocks
  # extra_pairs   — how many additional pairs are active beyond the first (0..MAX-1)
  # pair_items    — per-slot modifier item slots are enabled
  # egg_move_select — egg-move selection UI is available at egg collection
  # shiny_bonus   — extra shiny rerolls added on top of Masuda Method / Shiny Charm
  # speed_bonus   — steps counted per real step taken (1 = normal, 2 = 2× speed)

  def extra_pairs;          return @extra_pairs      || 0;     end
  def extra_pairs=(v);      @extra_pairs      = v;             end
  def pair_items;           return @pair_items        || false; end
  def pair_items=(v);       @pair_items       = v;             end
  def egg_move_select;      return @egg_move_select   || false; end
  def egg_move_select=(v);  @egg_move_select  = v;             end
  def shiny_bonus;          return @shiny_bonus       || 0;    end
  def shiny_bonus=(v);      @shiny_bonus      = v;             end
  def speed_bonus;          return @speed_bonus       || 1;    end
  def speed_bonus=(v);      @speed_bonus      = v;             end

  def initialize
    @extra_pairs      = 0
    @pair_items       = false
    @egg_move_select  = false
    @shiny_bonus      = 0
    @speed_bonus      = 1
  end

  def max_active_pairs
    return [1 + (@extra_pairs || 0), Settings::MAX_BREEDING_PAIRS].min
  end

  #-----------------------------------------------------------------------------
  # Unlock helpers — call these from NPC events or upgrade scripts.
  #-----------------------------------------------------------------------------

  def unlock_extra_pair
    @extra_pairs = [(@extra_pairs || 0) + 1, Settings::MAX_BREEDING_PAIRS - 1].min
  end

  def unlock_pair_items
    @pair_items = true
  end

  def unlock_egg_move_select
    @egg_move_select = true
  end

  def add_shiny_bonus(amount = 1)
    @shiny_bonus = (@shiny_bonus || 0) + amount
  end

  def add_speed_bonus(amount = 1)
    @speed_bonus = [(@speed_bonus || 1) + amount, 4].min
  end
end

#===============================================================================
# BreedingPair — one independent breeding slot pair with its own egg state.
#
# Replaces the monolithic @slots / @egg_generated / @step_counter that used to
# live directly on DayCare.  Each pair is self-contained so that multiple pairs
# can progress at different rates without interfering.
#
# item_a / item_b are reserved for future per-slot modifier items (separate from
# the Pokémon's own held item).  They have no effect yet.
#===============================================================================
class BreedingPair
  attr_accessor :slot_a, :slot_b
  attr_accessor :egg_generated
  attr_accessor :step_counter
  attr_accessor :item_a, :item_b   # per-slot modifier items (reserved for future use)

  STEP_THRESHOLD = 256   # steps between egg-chance rolls (unchanged from original)

  def initialize
    # DayCare::DayCareSlot is defined in 007_Overworld_DayCare.rb, which loads
    # after this file — but initialize is only ever called at runtime (never at
    # class-definition time), so the constant is already resolved by then.
    @slot_a        = DayCare::DayCareSlot.new
    @slot_b        = DayCare::DayCareSlot.new
    @egg_generated = false
    @step_counter  = 0
    @item_a        = nil
    @item_b        = nil
  end

  #-----------------------------------------------------------------------------
  # Slot accessors
  #-----------------------------------------------------------------------------

  def slot(index)
    return (index == 0) ? @slot_a : @slot_b
  end

  def count
    n = 0
    n += 1 if @slot_a&.filled?
    n += 1 if @slot_b&.filled?
    return n
  end

  def has_pair?; return count == 2; end
  def empty?;    return count == 0; end
  def any?;      return count > 0;  end

  def first_empty_slot_index
    return 0 if !@slot_a&.filled?
    return 1 if !@slot_b&.filled?
    return nil
  end

  def reset_egg_counters
    @egg_generated = false
    @step_counter  = 0
  end

  #-----------------------------------------------------------------------------
  # Breeding
  #-----------------------------------------------------------------------------

  def pokemon_pair
    raise _INTL("Couldn't find 2 deposited Pokémon.") unless has_pair?
    return @slot_a.pokemon, @slot_b.pokemon
  end

  def compatibility
    return 0 unless has_pair?
    pkmn1, pkmn2 = @slot_a.pokemon, @slot_b.pokemon
    return 0 if pkmn1.shadowPokemon? || pkmn2.shadowPokemon?
    grps1 = pkmn1.species_data.egg_groups
    grps2 = pkmn2.species_data.egg_groups
    return 0 if grps1.include?(:Undiscovered) || grps2.include?(:Undiscovered)
    return 0 if !grps1.include?(:Ditto) && !grps2.include?(:Ditto) &&
                (grps1 & grps2).empty?
    return 0 unless compatible_gender?(pkmn1, pkmn2)
    ret = 1
    ret += 1 if pkmn1.species == pkmn2.species
    ret += 1 if pkmn1.owner.id != pkmn2.owner.id
    return ret
  end

  def generate_egg(unlocks)
    return nil unless has_pair?
    pkmn1, pkmn2 = pokemon_pair
    return DayCare::EggGenerator.generate(pkmn1, pkmn2, self, unlocks)
  end

  def share_egg_move
    return unless has_pair?
    pkmn1, pkmn2 = pokemon_pair
    return if pkmn1.species != pkmn2.species
    egg_moves1 = pkmn1.species_data.get_egg_moves
    egg_moves2 = pkmn2.species_data.get_egg_moves
    known1 = []
    known2 = []
    if pkmn2.numMoves < Pokemon::MAX_MOVES
      pkmn1.moves.each { |m| known1 << m.id if egg_moves2.include?(m.id) && !pkmn2.hasMove?(m.id) }
    end
    if pkmn1.numMoves < Pokemon::MAX_MOVES
      pkmn2.moves.each { |m| known2 << m.id if egg_moves1.include?(m.id) && !pkmn1.hasMove?(m.id) }
    end
    if !known1.empty?
      if known2.empty?
        pkmn2.learn_move(known1[0])
      else
        learner = [[pkmn1, known2[0]], [pkmn2, known1[0]]].sample
        learner[0].learn_move(learner[1])
      end
    elsif !known2.empty?
      pkmn1.learn_move(known2[0])
    end
  end

  def update_on_step_taken(unlocks, gain_exp)
    @step_counter += unlocks.speed_bonus
    if @step_counter >= STEP_THRESHOLD
      @step_counter = 0
      if !@egg_generated && has_pair?
        compat     = compatibility
        egg_chance = [0, 20, 50, 70][compat]
        egg_chance = [0, 40, 80, 88][compat] if $bag.has?(:OVALCHARM)
        @egg_generated = true if rand(100) < egg_chance
      end
      share_egg_move if Settings::DAY_CARE_POKEMON_CAN_SHARE_EGG_MOVES && rand(100) < 50
    end
    if gain_exp
      @slot_a.add_exp if @slot_a&.filled?
      @slot_b.add_exp if @slot_b&.filled?
    end
  end

  private

  def compatible_gender?(pkmn1, pkmn2)
    return true if pkmn1.female? && pkmn2.male?
    return true if pkmn1.male? && pkmn2.female?
    ditto1 = pkmn1.species_data.egg_groups.include?(:Ditto)
    ditto2 = pkmn2.species_data.egg_groups.include?(:Ditto)
    return true if ditto1 && !ditto2
    return true if ditto2 && !ditto1
    return false
  end
end
