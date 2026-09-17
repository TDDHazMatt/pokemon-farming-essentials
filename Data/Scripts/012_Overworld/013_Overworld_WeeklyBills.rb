#===============================================================================
# Grandma's weekly farm bills. A single amount comes due every Sunday at
# midnight (in-game time, per pbGetTimeNow - see 003_Overworld_Time.rb), and
# increases week over week. The player can pay it off early via Grandma's
# "Contribute Funds" dialog option; if it's still outstanding when the due
# moment hits, Grandma calls on the Pokégear asking for the rest.
#
# Tracked as a single global tracker on $PokemonGlobal (see
# 002_Overworld_Metadata.rb), the same pattern GrandmaOrder uses for its
# pending-order state (012_Overworld_GrandmaOrder.rb) - this isn't tied to any
# one event/map, so per-event interp.setVariable storage doesn't fit.
#===============================================================================
class WeeklyBills
  SECONDS_PER_WEEK = 7 * 24 * 60 * 60
  STARTING_AMOUNT  = 2000
  AMOUNT_INCREASE  = 1000

  attr_reader :week, :amount_paid, :due_at

  def initialize
    @week        = 1
    @amount_paid = 0
    @due_at      = self.class.next_sunday_midnight(pbGetTimeNow).to_i
  end

  def self.next_sunday_midnight(time)
    days_ahead = (7 - time.wday) % 7
    days_ahead = 7 if days_ahead == 0
    return Time.local(time.year, time.month, time.day) + days_ahead * 86400
  end

  def amount_due
    return STARTING_AMOUNT + AMOUNT_INCREASE * (@week - 1)
  end

  def balance_remaining
    return [amount_due - @amount_paid, 0].max
  end

  def paid_in_full?
    return balance_remaining <= 0
  end

  def due?(time = pbGetTimeNow)
    return time.to_i >= @due_at
  end

  # Applies money toward this week's balance. Returns the amount actually
  # applied (never more than what's still owed).
  def contribute(amount)
    amount = [amount, balance_remaining].min
    return 0 if amount <= 0
    @amount_paid += amount
    return amount
  end

  # Rolls over into next week's bill once this week's due moment has been
  # handled (paid off or defaulted on). Adds exactly 7 days to @due_at rather
  # than recomputing "next Sunday" from now, so a late check doesn't drift
  # the weekly schedule.
  def advance_week!
    @week       += 1
    @amount_paid = 0
    @due_at      += SECONDS_PER_WEEK
  end
end

def pbWeeklyBills
  $PokemonGlobal.weekly_bills ||= WeeklyBills.new
  return $PokemonGlobal.weekly_bills
end

#===============================================================================
# "Contribute Funds" - Grandma's dialog choice on the Barn map (Map032, event
# "Grandma"). Lets the player pay off this week's bill before it comes due.
#===============================================================================
def pbContributeFundsToGrandma
  bills = pbWeeklyBills
  if bills.paid_in_full?
    pbMessage(_INTL("Oh, we have enough for this week.\nThank you for checking!"))
    return
  end

  amount = bills.balance_remaining
  if $player.money < amount
    # TODO: decide what happens when the player can't cover the full amount
    # up front (partial contributions, a payment plan, etc.) - not designed
    # yet, so just turn them away gently for now.
    pbMessage(_INTL("Grandma: \"That's okay, Sweetie. We still have some time.\""))
    return
  end

  return unless pbConfirmMessage(_INTL("This week's bills come to ${1}.\nContribute the full amount?", amount))
  $player.money -= amount
  bills.contribute(amount)
  pbMessage(_INTL("\\me[Money in bag]Thank you kindly! That covers us for this week."))
end

#===============================================================================
# Grandma's Pokégear call when the bills are still outstanding at the moment
# they come due (Sunday midnight). Triggered either by pbCheckWeeklyBillsDue
# below (normal step-by-step time passing) or by pbSleepInBed if a sleep jump
# would otherwise skip straight past the due moment unnoticed.
#===============================================================================
def pbWeeklyBillsOverdueCall
  bills = pbWeeklyBills

  if !bills.paid_in_full?
    balance = bills.balance_remaining

    ring = $player.has_pokegear
    Phone::Call.start_message if ring
    pbMessage(_INTL("Grandma: \"Oh, sweetheart... this week's bills came due and we're still ${1} short.\"", balance))
    pbMessage(_INTL("Grandma: \"Could you wire over the rest for us?\""))

    if $player.money >= balance
      $player.money -= balance
      bills.contribute(balance)
      pbMessage(_INTL("You wired ${1} to Grandma.", balance))
      pbMessage(_INTL("Grandma: \"Thank you so much, dear. That takes care of it!\""))
    else
      # TODO: decide what happens when the player can't cover the shortfall
      # (debt carried forward, a favor owed, consequences, etc.) - not designed
      # yet, so just let the week roll over unpaid for now.
      pbMessage(_INTL("Grandma: \"Oh dear... well, we'll have to figure something out. Don't you worry about it for now.\""))
    end
    Phone::Call.end_message if ring
  end

  # Whether it was already covered early (Contribute Funds) or just now via
  # the call above, this is the "did the week end paid off" checkpoint - a
  # milestone autosave (see 014_Overworld_AutoSave.rb) is only worth taking
  # when the answer is yes.
  payment_successful = bills.paid_in_full?
  bills.advance_week!
  pbTriggerMilestoneAutosave if payment_successful
end

#===============================================================================
# Checked every step (same step-driven clock everything else here uses - see
# 010b_Overworld_GameClock.rb) so the overdue call fires the moment the game
# clock crosses this week's due_at.
#===============================================================================
EventHandlers.add(:on_player_step_taken, :check_weekly_bills_due,
  proc {
    pbWeeklyBillsOverdueCall if pbWeeklyBills.due?
  }
)
