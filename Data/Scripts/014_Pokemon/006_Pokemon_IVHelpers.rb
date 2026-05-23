#===============================================================================
# IV helper methods for NPC events and item effects.
#
# IVs in this game are uncapped — they can be negative or exceed 31.
# Stats always floor at 1 regardless of how low IVs go.
#
# All methods call pkmn.calc_stats automatically after changing IVs.
#===============================================================================

# Set one IV to an exact value.
#   pbSetIV(pkmn, :ATTACK, 50)
def pbSetIV(pkmn, stat, value)
  pkmn.iv[stat] = value
  pkmn.calc_stats
end

# Shift one IV by a delta (positive or negative).
#   pbModifyIV(pkmn, :SPEED, -10)
def pbModifyIV(pkmn, stat, delta)
  pkmn.iv[stat] = (pkmn.iv[stat] || 0) + delta
  pkmn.calc_stats
end

# Set all IVs to the same value.
#   pbSetAllIVs(pkmn, 31)   # perfect
#   pbSetAllIVs(pkmn, 0)    # zeroed
def pbSetAllIVs(pkmn, value)
  GameData::Stat.each_main { |s| pkmn.iv[s.id] = value }
  pkmn.calc_stats
end

# Shift all IVs by a delta.
#   pbModifyAllIVs(pkmn, 5)    # boost every stat
#   pbModifyAllIVs(pkmn, -10)  # curse every stat
def pbModifyAllIVs(pkmn, delta)
  GameData::Stat.each_main { |s| pkmn.iv[s.id] = (pkmn.iv[s.id] || 0) + delta }
  pkmn.calc_stats
end

# Read a single IV — safe to call from an event Script condition.
#   pbGetIV(pkmn, :HP)  →  Integer
def pbGetIV(pkmn, stat)
  return pkmn.iv[stat] || 0
end
