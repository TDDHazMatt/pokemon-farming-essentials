#===============================================================================
# Grandma's "Special Requests" board - a rotating set of 10 Pokémon species
# that pay well above the normal sale rate (016_UI/026_UI_PokemonSale.rb) if
# sold to her while the request is active. Species are drawn from the Kanto
# regional dex (PBS/regional_dexes.txt index 0), biased toward lower dex
# numbers in early weeks and higher dex numbers in later weeks (using the
# same week counter as the weekly bills - see 013_Overworld_WeeklyBills.rb),
# and each one's price-per-level is set purely by its own dex number
# (earlier = more common = cheaper).
#
# Two independent schedules, both anchored to 12:01 AM (in-game time, same
# convention as 014_Overworld_AutoSave.rb's daily autosave):
#   - Weekly (Monday 12:01 AM): the whole board of 10 is thrown out and
#     redrawn from scratch.
#   - Daily (every 12:01 AM): any request slot that was fulfilled during the
#     day gets replaced with a fresh one - a completed request doesn't
#     reopen instantly, only the next morning.
#
# Caught up lazily, on access (SpecialRequests#refresh_if_due!, called from
# pbSpecialRequests below) rather than via a step-driven background hook -
# that way the board is always correct no matter how time got to where it
# is (ordinary steps, a multi-hour sleep, a debug time skip), instead of
# staying stale until the player's next literal footstep after the
# threshold passed.
#===============================================================================
class SpecialRequests
  REQUEST_COUNT       = 10
  MIN_PRICE_PER_LEVEL = 60
  MAX_PRICE_PER_LEVEL = 200
  KANTO_DEX           = 0   # index into PBS/regional_dexes.txt

  Request = Struct.new(:species, :price_per_level)

  attr_reader :requests

  def initialize
    @next_weekly_refresh = self.class.next_monday_1201am(pbGetTimeNow).to_i
    @next_daily_check    = AutoSaveState.next_1201am(pbGetTimeNow).to_i
    @requests = []
    regenerate_all!
  end

  def self.next_monday_1201am(time)
    days_ahead = (1 - time.wday) % 7   # Ruby wday: Sunday=0, Monday=1, ...
    candidate  = Time.local(time.year, time.month, time.day, 0, 1, 0) + days_ahead * 86400
    candidate += 7 * 86400 if candidate <= time
    return candidate
  end

  def weekly_due?(time = pbGetTimeNow)
    return time.to_i >= @next_weekly_refresh
  end

  def daily_due?(time = pbGetTimeNow)
    return time.to_i >= @next_daily_check
  end

  def advance_weekly!
    @next_weekly_refresh += 7 * 24 * 60 * 60
  end

  def advance_daily!
    @next_daily_check += 24 * 60 * 60
  end

  # Catches the board up to the current time, regardless of how it got here -
  # a run of ordinary steps, a multi-hour sleep, a debug time jump, or simply
  # not having been looked at in a while. Called from pbSpecialRequests on
  # every access (see below) rather than relying solely on a step-driven
  # background hook, which could leave the board stale until the player's
  # next literal footstep - or never refresh at all if time was advanced by
  # something that doesn't fire on_player_step_taken in between (sleeping
  # straight through a boundary, a debug menu time skip, etc.). The while
  # loops (rather than a single if) mean an arbitrarily large jump still ends
  # up fully caught up, not just one week/day closer.
  def refresh_if_due!
    while weekly_due?
      regenerate_all!
      advance_weekly!
    end
    while daily_due?
      refill_completed!
      advance_daily!
    end
  end

  # Throws out the whole board and draws 10 fresh requests.
  def regenerate_all!
    week = pbWeeklyBills.week
    used = []
    @requests = Array.new(REQUEST_COUNT) do
      req = self.class.generate_request(week, used)
      used << req.species
      req
    end
  end

  # Replaces only the slots emptied out by fulfill! - active requests are
  # left untouched.
  def refill_completed!
    week = pbWeeklyBills.week
    used = @requests.compact.map(&:species)
    @requests.each_with_index do |req, i|
      next if req
      new_req = self.class.generate_request(week, used)
      used << new_req.species
      @requests[i] = new_req
    end
  end

  # Clears (and returns) the active request for this species, if any - the
  # slot stays empty until the next daily check (refill_completed!) rather
  # than reopening immediately.
  def fulfill!(species)
    idx = @requests.index { |req| req && req.species == species }
    return nil if !idx
    req = @requests[idx]
    @requests[idx] = nil
    return req
  end

  def active_request_for(species)
    return @requests.find { |req| req && req.species == species }
  end

  #-----------------------------------------------------------------------

  # 2.5 at week 1 (draws skew toward low dex numbers), 1.0 around the
  # midpoint (roughly uniform), 0.4 from week 10 on (skew toward high dex
  # numbers). rand ** exponent concentrates mass near 0 for exponent > 1 and
  # near 1 for exponent < 1, so this is a cheap, tunable way to slide the
  # distribution without building a full weighted table.
  def self.week_bias_exponent(week)
    t = [(week - 1) / 9.0, 1.0].min   # 0.0 at week 1, 1.0 from week 10 on
    return 2.5 + (0.4 - 2.5) * t
  end

  def self.dex_list
    return pbAllRegionalSpecies(KANTO_DEX)
  end

  def self.generate_request(week, exclude_species)
    list = dex_list
    exponent = week_bias_exponent(week)
    species = nil
    30.times do
      roll  = rand**exponent
      index = (roll * list.length).to_i
      index = list.length - 1 if index >= list.length
      candidate = list[index]
      next if exclude_species.include?(candidate)
      species = candidate
      break
    end
    species ||= (list - exclude_species).sample || list.sample
    dex_number = pbGetRegionalNumber(KANTO_DEX, species)
    return Request.new(species, price_per_level_for_dex(dex_number, list.length))
  end

  # Straight linear map from dex position to price - #1 costs MIN_PRICE_PER_LEVEL,
  # the last entry costs MAX_PRICE_PER_LEVEL, evenly spaced in between.
  def self.price_per_level_for_dex(dex_number, dex_size)
    fraction = (dex_number - 1).to_f / [dex_size - 1, 1].max
    price = MIN_PRICE_PER_LEVEL + (MAX_PRICE_PER_LEVEL - MIN_PRICE_PER_LEVEL) * fraction
    return price.round
  end
end

def pbSpecialRequests
  requests = ($PokemonGlobal.special_requests ||= SpecialRequests.new)
  requests.refresh_if_due!
  return requests
end

#===============================================================================
# "Special Requests" - Grandma's dialog choice on the Barn map (Map032, event
# "Grandma"), listing the currently active requests. Purely informational -
# actually fulfilling one happens through the normal "Make Sale" flow
# (pbGrandmaPokemonSale, 016_UI/026_UI_PokemonSale.rb), which checks for a
# matching request automatically.
#===============================================================================
def pbGrandmaSpecialRequests
  active = pbSpecialRequests.requests.compact
  if active.empty?
    pbMessage(_INTL("No one's asking for anything special this week. Check back soon!"))
    return
  end
  lines = active.map do |req|
    _INTL("{1} - ${2} per level", GameData::Species.get(req.species).name, req.price_per_level)
  end
  pbMessage(_INTL("Folks are looking for these Pokémon this week:") + "\r\n" + lines.join("\r\n"))
end
