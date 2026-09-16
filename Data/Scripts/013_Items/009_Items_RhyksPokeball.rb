#===============================================================================
# Rhyk's Pokeball - a togglable Key Item. While active, Rhyk (a persistent,
# moveless Rhydon) occupies party slot 0 as a genuine Pokémon - he can be
# healed normally, takes real damage, gains real EXP - and every wild
# encounter (step-triggered, fishing, Rock Smash, Sweet Scent, Bug Contest,
# etc.) becomes a Hybrid Battle (see
# 011_Battle/008_Other battle types/002_HybridBattle.rb) via the same
# :on_calling_wild_battle override hook the built-in Safari Zone uses (see
# 018_Alternate battle modes/001_SafariZone.rb).
#
# Deactivating removes Rhyk from the party and stores him, as-is (not
# healed), in $PokemonGlobal.rhyk_pokemon - there's deliberately no "heal him
# by toggling off and on" shortcut. Reactivating puts the same Pokémon
# object back (same level/EXP/HP/status), or creates him fresh the very
# first time.
#
# Lives here in 013_Items (not 012_Overworld, where the rest of the
# Overworld-side farm scripts live) because it registers with ItemHandlers
# at load time (ItemHandlers::UseInField.add etc.) - ItemHandlers itself is
# defined in 013_Items/001_Item_Utilities.rb, which loads AFTER all of
# 012_Overworld. Registering here, alongside every other item's handlers,
# guarantees ItemHandlers already exists.
#===============================================================================
class Pokemon
  # Identifies the one persistent Rhyk Pokémon. Needed because object
  # identity doesn't survive a save/load cycle (Marshal reconstructs new
  # objects) or the player reordering their party, but a plain ivar does.
  attr_accessor :is_rhyk
end

class PokemonGlobalMetadata
  # Rhyk's Pokémon object while his Pokeball is inactive (i.e. he isn't
  # currently occupying a party slot). nil while he's active and in the
  # party instead.
  attr_accessor :rhyk_pokemon
end

RHYK_STARTING_LEVEL = 15

def pbRhyksPokeballActive?
  return $player.party.any? { |p| p.is_rhyk }
end

#===============================================================================
# Builds Rhyk the first time he's ever activated, or reuses (and clears from
# cold storage) whatever's saved in $PokemonGlobal.rhyk_pokemon otherwise -
# preserving his level/EXP/HP/status across the toggle.
#===============================================================================
def pbGetOrCreateRhyk
  stored = $PokemonGlobal.rhyk_pokemon
  if stored
    $PokemonGlobal.rhyk_pokemon = nil
    return stored
  end
  pkmn = Pokemon.new(:RHYDON, RHYK_STARTING_LEVEL)
  pkmn.name           = "Rhyk"
  pkmn.moves.clear
  pkmn.is_rhyk        = true
  pkmn.cannot_release = true   # a real party member now - don't let him be released...
  pkmn.cannot_store   = true   # ...or boxed, which would silently break this key item
  pkmn.calc_stats
  pkmn.heal
  return pkmn
end

ItemHandlers::UseInField.add(:RHYKSPOKEBALL, proc { |item|
  if pbRhyksPokeballActive?
    rhyk = $player.party.find { |p| p.is_rhyk }
    $player.party.delete(rhyk)
    $PokemonGlobal.rhyk_pokemon = rhyk
    pbMessage(_INTL("Rhyk's Pokeball falls quiet.\nRhyk returns to his ball. Wild encounters are back to normal."))
  else
    if $player.party.length >= 6
      pbMessage(_INTL("There's no room in your party for Rhyk right now."))
      next true
    end
    rhyk = pbGetOrCreateRhyk
    $player.party.unshift(rhyk)
    pbMessage(_INTL("Rhyk's Pokeball hums to life.\nRhyk joins your party! Wild encounters will now be Hybrid Battles."))
  end
  next true
})

ItemHandlers::UseFromBag.add(:RHYKSPOKEBALL, proc { |item|
  next 2
})

ItemHandlers::UseText.add(:RHYKSPOKEBALL, proc { |item|
  next pbRhyksPokeballActive? ? _INTL("Deactivate") : _INTL("Activate")
})

#===============================================================================
# Starts a Hybrid Battle against pkmn, built the same way a normal wild
# battle is (see WildBattle.start_core in
# 012_Overworld/002_Battle triggering/001_Overworld_BattleStarting.rb),
# except using HybridBattle instead of Battle. Since $player.party genuinely
# contains Rhyk (in slot 0) while his Pokeball is active, party construction
# and the "Go! Rhyk!" send-out are both completely standard - no synthetic
# one-off party needed.
#===============================================================================
def pbHybridBattle(pkmn)
  pkmn = pbGenerateWildPokemon(pkmn) if !pkmn.is_a?(Pokemon)
  foe_party = [pkmn]
  player_trainers, ally_items, player_party, player_party_starts =
    BattleCreationHelperMethods.set_up_player_trainers(foe_party)
  scene  = BattleCreationHelperMethods.create_battle_scene
  battle = HybridBattle.new(scene, player_party, foe_party, player_trainers, nil)
  battle.party1starts = player_party_starts
  battle.ally_items   = ally_items
  BattleCreationHelperMethods.prepare_battle(battle)
  $game_temp.clear_battle_rules
  decision = 0
  pbBattleAnimation(pbGetWildBattleBGM(foe_party), 0, foe_party) do
    pbSceneStandby { decision = battle.pbStartBattle }
  end
  Input.update
  $stats.safari_pokemon_caught += 1 if decision == 4
  pbSet(1, decision)
  EventHandlers.trigger(:on_wild_battle_end, pkmn.species_data.id, pkmn.level, decision)
  return decision
end

EventHandlers.add(:on_calling_wild_battle, :rhyks_pokeball,
  proc { |pkmn, handled|
    next if !handled[0].nil?
    next if !pbRhyksPokeballActive?
    rhyk = $player.party.find { |p| p.is_rhyk }
    # Rhyk's fainted (and hasn't been healed) - fall through to a normal
    # wild battle instead, same as if he weren't active at all.
    next if !rhyk || rhyk.hp <= 0
    handled[0] = pbHybridBattle(pkmn)
  }
)
