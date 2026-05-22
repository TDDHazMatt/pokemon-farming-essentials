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

  hours = SLEEP_HOUR_CHOICES[choice]

  pbBGMFade(1.5)
  pbFadeOutIn do
    $PokemonGlobal.time_offset += hours * 3600
    PBDayNight.instance_variable_set(:@dayNightToneLastUpdate, nil)
  end
  $game_map.autoplayAsCue

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
