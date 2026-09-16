#===============================================================================
# Rhyk's Pokeball - a togglable Key Item. While active:
#   - Every wild encounter (step-triggered, fishing, Rock Smash, Sweet Scent,
#     Bug Contest, etc.) becomes a Safari-style catching battle (SafariBattle
#     - no fighting, just Balls/Bait/Mud) instead of a normal battle, via the
#     same :on_calling_wild_battle override hook the built-in Safari Zone
#     uses (see 018_Alternate battle modes/001_SafariZone.rb).
#   - Encounters can trigger even with zero usable Pokémon in the party (see
#     the bypassed gate in 001_Overworld.rb's pbBattleOnStepTaken) - Safari
#     battles never need one, since you're not fighting.
#
# Unlike the actual Safari Zone, this isn't a timed session with its own ball
# allowance: it uses the player's real Safari Ball count from the Bag, and
# whatever gets thrown during the battle is deducted from the Bag afterward.
#===============================================================================
class PokemonGlobalMetadata
  attr_accessor :rhyks_pokeball_active
end

def pbRhyksPokeballActive?
  return $PokemonGlobal&.rhyks_pokeball_active || false
end

ItemHandlers::UseInField.add(:RHYKSPOKEBALL, proc { |item|
  $PokemonGlobal.rhyks_pokeball_active = !$PokemonGlobal.rhyks_pokeball_active
  if $PokemonGlobal.rhyks_pokeball_active
    pbMessage(_INTL("Rhyk's Pokeball hums to life.\nWild encounters will now be Safari-style catching challenges."))
  else
    pbMessage(_INTL("Rhyk's Pokeball falls quiet.\nWild encounters are back to normal."))
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
# Runs a Safari-style battle against pkmn, using the player's own Safari
# Balls (from the Bag) as the throwing allowance, and deducting however many
# actually got thrown once the battle ends. Mirrors pbSafariBattle
# (001_SafariZone.rb) but with no SafariState/session coupling - no ball
# allowance to restore, no "game over" teleport, no capture-streak tracking.
#===============================================================================
def pbRhyksPokeballBattle(pkmn)
  pkmn = pbGenerateWildPokemon(pkmn) if !pkmn.is_a?(Pokemon)
  foeParty      = [pkmn]
  playerTrainer = $player
  starting_balls = $bag.quantity(:SAFARIBALL)
  scene = BattleCreationHelperMethods.create_battle_scene
  battle = SafariBattle.new(scene, playerTrainer, foeParty)
  battle.ballCount = starting_balls
  BattleCreationHelperMethods.prepare_battle(battle)
  decision = 0
  pbBattleAnimation(pbGetWildBattleBGM(foeParty), 0, foeParty) do
    pbSceneStandby { decision = battle.pbStartBattle }
  end
  Input.update
  used = starting_balls - battle.ballCount
  $bag.remove(:SAFARIBALL, used) if used > 0
  $stats.safari_pokemon_caught += 1 if decision == 4
  pbSet(1, decision)
  EventHandlers.trigger(:on_wild_battle_end, pkmn.species_data.id, pkmn.level, decision)
  return decision
end

EventHandlers.add(:on_calling_wild_battle, :rhyks_pokeball,
  proc { |pkmn, handled|
    next if !handled[0].nil?
    next if !pbRhyksPokeballActive?
    handled[0] = pbRhyksPokeballBattle(pkmn)
  }
)
