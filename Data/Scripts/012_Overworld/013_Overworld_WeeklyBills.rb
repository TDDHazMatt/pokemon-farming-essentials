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
      Phone::Call.end_message if ring
    else
      sold_enough = false
      if pbConfirmMessage(_INTL("Grandma: \"Is there anything you could sell to help cover the rest?\""))
        sold_enough = pbWeeklyBillsLiquidateAssets(bills)
      end
      if sold_enough
        remaining = bills.balance_remaining
        $player.money -= remaining
        bills.contribute(remaining)
        pbMessage(_INTL("You wired ${1} to Grandma.", remaining))
        pbMessage(_INTL("Grandma: \"Thank you so much, dear. That takes care of it!\""))
        Phone::Call.end_message if ring
      else
        Phone::Call.end_message if ring
        pbWeeklyBillsGameOver
        return   # don't advance the week or take a milestone save - the run stops here
      end
    end
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
# Grandma's last-minute "sell something to cover it" offer, shown only when
# the player can't wire the full shortfall outright. Loops on a menu showing
# the running money/still-owed totals; Confirm only appears once selling has
# raised enough. Returns true if the player reached Confirm (caller is
# responsible for actually deducting/contributing the money), or false if
# they bailed via Nevermind/cancel without raising enough (falls through to
# pbWeeklyBillsGameOver).
#===============================================================================
def pbWeeklyBillsLiquidateAssets(bills)
  loop do
    balance     = bills.balance_remaining
    can_confirm = $player.money >= balance
    status      = _INTL("Money: ${1}\nStill owed: ${2}", $player.money, balance)

    commands      = []
    cmd_items     = -1
    cmd_pokemon   = -1
    cmd_confirm   = -1
    cmd_nevermind = -1
    commands[cmd_items     = commands.length] = _INTL("Sell Items")
    commands[cmd_pokemon   = commands.length] = _INTL("Sell Pokémon")
    commands[cmd_confirm   = commands.length] = _INTL("Confirm") if can_confirm
    commands[cmd_nevermind = commands.length] = _INTL("Nevermind")

    cmd = pbMessage(status, commands, commands.length)

    if cmd == cmd_items
      pbWeeklyBillsSellItems
    elsif cmd == cmd_pokemon
      pbWeeklyBillsSellPokemon
    elsif cmd == cmd_confirm
      return true
    else   # cmd_nevermind, or cancel
      return false
    end
  end
end

def pbWeeklyBillsSellItems
  commands = [_INTL("From Bag"), _INTL("From PC"), _INTL("Cancel")]
  cmd = pbMessage(_INTL("Sell items from where?"), commands, commands.length)
  case cmd
  when 0 then pbWeeklyBillsSellFromBag
  when 1 then pbWeeklyBillsSellFromStorage
  end
end

# Selling Pokémon isn't implemented yet - stubbed entry point so the menu
# shape (From Party / From PC) is already in place for when it is.
def pbWeeklyBillsSellPokemon
  commands = [_INTL("From Party"), _INTL("From PC"), _INTL("Cancel")]
  cmd = pbMessage(_INTL("Sell a Pokémon from where?"), commands, commands.length)
  return if cmd < 0 || cmd == commands.length - 1
  pbMessage(_INTL("Grandma: \"Oh, we're not set up to sell Pokémon that way yet, dear. Sorry.\""))
end

# [item_id, qty] pairs restricted to what's actually sellable - same filter
# PokemonMartScreen's adapter uses (016_UI/020_UI_PokeMart.rb): a positive
# sell price, and not a key/important item.
def pbWeeklyBillsFilterSellable(pairs)
  return pairs.select do |item_id, _qty|
    item_d = GameData::Item.get(item_id)
    item_d.sell_price > 0 && !item_d.is_important?
  end
end

def pbWeeklyBillsSellFromBag
  items = pbWeeklyBillsFilterSellable($bag.pockets.flatten(1))
  if items.empty?
    pbMessage(_INTL("You don't have anything in your Bag worth selling."))
    return
  end
  pbWeeklyBillsSellFromList(items) { |item_id, qty| $bag.remove(item_id, qty) }
end

def pbWeeklyBillsSellFromStorage
  storage = ($PokemonGlobal.pcItemStorage ||= PCItemStorage.new)
  items = pbWeeklyBillsFilterSellable(storage.items)
  if items.empty?
    pbMessage(_INTL("There's nothing in storage worth selling."))
    return
  end
  pbWeeklyBillsSellFromList(items) { |item_id, qty| storage.remove(item_id, qty) }
end

# items: [[item_id, qty], ...] already filtered to sellable stock. Sells at
# most one stack (or part of one) and returns - pbWeeklyBillsLiquidateAssets
# redraws its own totals afterward rather than looping back in here, so
# selling several things means repeatedly choosing Sell Items from the outer
# menu, same as the mid-week Contribute Funds flow feeding back into Grandma's
# main dialog.
def pbWeeklyBillsSellFromList(items)
  commands = items.map do |item_id, qty|
    item_d = GameData::Item.get(item_id)
    _INTL("{1} x{2} (${3} each)", item_d.name, qty, item_d.sell_price)
  end
  commands << _INTL("Cancel")
  cmd = pbMessage(_INTL("What would you like to sell?"), commands, commands.length)
  return if cmd < 0 || cmd == commands.length - 1

  item_id, qty_have = items[cmd]
  item_d = GameData::Item.get(item_id)
  qty = 1
  if qty_have > 1
    params = ChooseNumberParams.new
    params.setRange(1, qty_have)
    params.setDefaultValue(qty_have)
    qty = pbMessageChooseNumber(_INTL("How many {1} would you like to sell?", item_d.name_plural), params)
  end
  return if qty <= 0

  total = item_d.sell_price * qty
  name  = (qty > 1) ? item_d.name_plural : item_d.name
  return unless pbConfirmMessage(_INTL("I can pay ${1} for {2} {3}.\nIs that OK?", total, qty, name))
  yield(item_id, qty)
  $player.money += total
  pbMessage(_INTL("Sold {1} {2} for ${3}.", qty, name, total))
end

#===============================================================================
# Reached when the bills go unpaid at the Sunday-midnight due moment - ends
# the run and kicks back to the title screen (the same safe "return to title
# from deep in gameplay" idiom used elsewhere, e.g. a language change: setting
# the flag and letting Scene_Map#update perform the actual scene swap at its
# own well-defined checkpoint, rather than touching $scene directly from here).
#
# The bill itself is deliberately left exactly as unpaid/due (no advance_week!,
# no milestone save) - if the player picks Continue on this same save without
# rolling back first, they'll walk straight back into this identical check on
# their very next step. Rolling back to an earlier autosave (Data/Scripts/016_UI
# /013_UI_Load.rb - press D on a highlighted save) is the intended way out.
#===============================================================================
def pbWeeklyBillsGameOver
  pbMessage(_INTL("Grandma: \"Oh no... we just couldn't cover it this time.\""))
  pbMessage(_INTL("The bank forecloses on the farm. There's nothing more to be done here."))
  pbMessage(_INTL("From the main menu, highlight a save and press D to browse its rollback saves - Daily autosaves from the past week, or Milestone autosaves from past weeks the bills were paid off in full."))
  pbMessage(_INTL("Only roll back as far as you actually need to, though - once you keep playing from an older save, it starts filling in those same rotating slots again, which can overwrite rollback points further ahead that you might still want."))
  $game_temp.title_screen_calling = true
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
