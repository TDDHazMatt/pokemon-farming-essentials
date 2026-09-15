#===============================================================================
# Advances the step-driven game clock (see pbGetTimeNow, 003_Overworld_Time.rb)
# by Settings::SECONDS_PER_STEP every step the player takes. This is the only
# thing that makes time pass at all - everything downstream (day/night tint,
# crop and ranch pen growth, wild encounter tables, Pokérus, the phone rematch
# timer, the time-period popup, etc.) just keeps calling pbGetTimeNow as
# before and needs no changes, since the clock it reads now only moves when
# this fires.
#
# Loaded (and so registered) before 011_Overworld_TimePeriodPopup.rb on
# purpose - on_player_step_taken handlers fire in registration order, and the
# clock must have already advanced by the time the popup checks it on the
# same step, or the transition would be noticed one step late.
#===============================================================================
EventHandlers.add(:on_player_step_taken, :advance_game_clock,
  proc {
    $PokemonGlobal.time_offset += Settings::SECONDS_PER_STEP
  }
)
