#===============================================================================
# Sleeping in bed — advances game time so berries, apricorn trees, and all
# other time-based systems progress without waiting in real life.
#
# Usage: call  pbSleepInBed  from a bed event's script box.
#
# The player chooses how many hours to sleep (4 / 8 / 12). The game's internal
# clock (pbGetTimeNow) advances by that many hours, which is picked up
# automatically by BerryPlantData#update, ApricornTreeData#update, the day/
# night tint, seasons, moon phases, and anything else that reads pbGetTimeNow.
#===============================================================================
SLEEP_HOUR_CHOICES = [4, 8, 12]

def pbSleepInBed
  return unless pbConfirmMessage(
    _INTL("You're feeling sleepy...\nWant to get some rest?")
  )

  choice = pbMessage(
    _INTL("How long would you like to sleep?"),
    [_INTL("4 hours"), _INTL("8 hours"), _INTL("12 hours"), _INTL("Cancel")],
    -1
  )
  return if choice < 0 || choice >= SLEEP_HOUR_CHOICES.length

  hours              = SLEEP_HOUR_CHOICES[choice]
  requested_seconds  = hours * 3600
  seconds_to_advance = requested_seconds

  # Sleeping can jump several hours at once, which could leap straight over
  # the Sunday-midnight bills deadline without ever running the overdue call
  # (that call only fires on a per-step check - see 013_Overworld_WeeklyBills.rb).
  # Cap the jump at the due moment instead, so waking up runs the call first.
  bills = pbWeeklyBills
  interrupted_by_bills = false
  if !bills.paid_in_full?
    seconds_until_due = bills.due_at - pbGetTimeNow.to_i
    if seconds_until_due >= 0 && seconds_until_due < requested_seconds
      seconds_to_advance    = seconds_until_due
      interrupted_by_bills  = true
    end
  end

  pbBGMFade(1.5)
  pbFadeOutIn do
    $PokemonGlobal.time_offset += seconds_to_advance
    PBDayNight.instance_variable_set(:@dayNightToneLastUpdate, nil)
  end
  $game_map.autoplayAsCue

  # Sleeping jumps time in one go rather than ticking step by step, so it can
  # cross the 12:01 AM daily-autosave boundary without the per-step check
  # (014_Overworld_AutoSave.rb) ever running during the jump. Catch it up
  # here instead - the autosave just ends up capturing the moment right after
  # waking, whatever time that turns out to be.
  while pbAutoSaveState.daily_due?
    pbPerformAutoSave(pbAutoSaveState.daily_slot)
    pbAutoSaveState.advance_daily!
  end

  if interrupted_by_bills
    pbMessage(_INTL("Your Pokégear rings, jolting you awake..."))
    pbWeeklyBillsOverdueCall
    return
  end

  hour     = pbGetTimeNow.hour
  greeting = if hour >= 5 && hour < 12
               _INTL("Good morning!")
             elsif hour >= 12 && hour < 17
               _INTL("Good afternoon!")
             elsif hour >= 17 && hour < 20
               _INTL("Good evening!")
             else
               _INTL("It's still dark outside...")
             end
  pbMessage(_INTL("You slept for {1} hours.\n{2}", hours, greeting))
end
