#===============================================================================
# Shows a "Monday Morning" / "Monday Afternoon" / etc. popup whenever the
# (step-driven - see pbGetTimeNow) game clock transitions into a new
# time-of-day period, reusing the same LocationWindow banner (slide down,
# linger, slide back up) that the map name popup already uses (see
# 001_Overworld visuals/002_Overworld_Overlays.rb) - LocationWindow.new takes
# arbitrary text, it's not tied to map names at all.
#===============================================================================

# PBDayNight only exposes hour-range predicates (isMorning?/isAfternoon?/
# isEvening?/isNight?), not a single label, and they leave the 10:00-14:00
# window uncovered by any of the three named periods - call that "Midday".
def pbGetTimePeriodName(time = nil)
  time ||= pbGetTimeNow
  return _INTL("Morning") if PBDayNight.isMorning?(time)
  return _INTL("Afternoon") if PBDayNight.isAfternoon?(time)
  return _INTL("Evening") if PBDayNight.isEvening?(time)
  return _INTL("Night") if PBDayNight.isNight?(time)
  return _INTL("Midday")
end

def pbGetWeekdayName(time = nil)
  time ||= pbGetTimeNow
  return [_INTL("Sunday"), _INTL("Monday"), _INTL("Tuesday"), _INTL("Wednesday"),
          _INTL("Thursday"), _INTL("Friday"), _INTL("Saturday")][time.wday]
end

def pbGetTimePeriodLabel(time = nil)
  time ||= pbGetTimeNow
  return _INTL("{1} {2}", pbGetWeekdayName(time), pbGetTimePeriodName(time))
end

def pbShowTimePeriodPopup
  return if !$scene.is_a?(Scene_Map)
  $scene.spriteset.addUserSprite(LocationWindow.new(pbGetTimePeriodLabel))
end

# The clock only ever moves on a step (see 012_Overworld_GameClock.rb), so
# checking on_player_step_taken catches every possible transition with no
# wasted per-frame polling. last_period is a local captured by the closure,
# not saved-game state, so a fresh session/loaded save always re-seeds
# silently on its first step instead of firing a popup immediately.
last_period = nil
EventHandlers.add(:on_player_step_taken, :announce_time_period_change,
  proc {
    current = pbGetTimePeriodName
    pbShowTimePeriodPopup if last_period && last_period != current
    last_period = current
  }
)
