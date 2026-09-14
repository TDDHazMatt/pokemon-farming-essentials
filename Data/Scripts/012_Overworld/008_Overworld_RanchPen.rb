#===============================================================================
# A ranch pen holds one Pokémon (pulled out of the party, same as Day Care) and
# accumulates produce over real elapsed time, the same way CropData accumulates
# growth. Unlike a crop, a pen never "dies" - produce just stockpiles up to the
# species' MaxStockpile until it's collected.
#
# Stored per-event via interp.setVariable/getVariable, the same generic
# per-event storage plantable-spot crops already use - so, like crops, "how
# many pens exist" is purely a map-design decision (place as many /ranchpen/i
# events as you like), not a global unlock system.
#===============================================================================
class RanchPenSlot
  attr_reader   :pokemon
  attr_accessor :stockpile

  def initialize
    reset
  end

  def reset
    @pokemon           = nil
    @stockpile         = 0
    @time_last_updated = 0
  end

  def deposit(pkmn)
    @pokemon           = pkmn
    @stockpile         = 0
    @time_last_updated = pbGetTimeNow.to_i
  end

  # Clears the pen and returns the Pokémon that was living in it.
  def withdraw
    pkmn = @pokemon
    reset
    return pkmn
  end

  def filled?
    return !@pokemon.nil?
  end

  def produce_def
    return nil if !filled?
    return GameData::RanchProduce.try_get(@pokemon.species)
  end

  def update
    return if !filled?
    prod = produce_def
    return if !prod
    return if @stockpile >= prod.max_stockpile
    time_now   = pbGetTimeNow.to_i
    time_delta = time_now - @time_last_updated
    return if time_delta <= 0
    units = time_delta / prod.seconds_per_unit
    return if units <= 0
    @stockpile          = [@stockpile + units, prod.max_stockpile].min
    @time_last_updated += units * prod.seconds_per_unit
  end

  # Empties the stockpile. Returns [item_id, quantity], or [nil, 0] if there's
  # nothing to collect.
  def collect
    prod = produce_def
    return [nil, 0] if !prod || @stockpile <= 0
    qty        = @stockpile
    @stockpile = 0
    return [prod.item, qty]
  end
end

#===============================================================================
# Universal ranch-pen interaction. Call pbRanchPen from an overworld event's
# script box. The event name must match /ranchpen/i for the icon-overlay hook.
#
# New livestock only require a PBS entry in ranch_produce.txt (mapping a
# species to a produce item) - no new interaction code needed.
#===============================================================================
def pbRanchPen
  interp = pbMapInterpreter
  pen    = interp.getVariable
  pen    = nil if !pen.is_a?(RanchPenSlot)

  if pen&.filled?
    pbInteractWithRanchPen(pen)
    return
  end

  return unless pbConfirmMessage(_INTL("It's an empty pen.\nWant to put a Pokémon here?"))
  pbChoosePokemon(1, 2, proc { |p| GameData::RanchProduce.exists?(p.species) })
  chosen = pbGet(1)
  return if chosen < 0
  if !$player.has_other_able_pokemon?(chosen)
    pbMessage(_INTL("{1} can't be the only Pokémon you have!", $player.party[chosen].name))
    return
  end
  pkmn = $player.party[chosen]
  pen ||= RanchPenSlot.new
  pen.deposit(pkmn)
  interp.setVariable(pen)
  $player.party.delete_at(chosen)
  pbMessage(_INTL("{1} was placed in the pen.\nIt looks happy here.", pkmn.name))
end

#===============================================================================
# Handles interaction with an occupied ranch pen.
#===============================================================================
def pbInteractWithRanchPen(pen)
  interp = pbMapInterpreter
  pen.update
  prod = pen.produce_def
  pkmn = pen.pokemon

  commands   = []
  cmdCollect = -1
  cmdCheck   = -1
  cmdTake    = -1
  commands[cmdCollect = commands.length] = _INTL("Collect produce") if prod && pen.stockpile > 0
  commands[cmdCheck   = commands.length] = _INTL("Check on {1}", pkmn.name)
  commands[cmdTake    = commands.length] = _INTL("Take {1} back", pkmn.name)
  cmd = pbMessage(_INTL("{1} is here.", pkmn.name), commands, commands.length)

  if cmd == cmdCollect
    item_id, qty = pen.collect
    return if !item_id
    item_data = GameData::Item.get(item_id)
    if !$bag.can_add?(item_id, qty)
      pen.stockpile = qty   # give it back, nothing was lost
      pbMessage(_INTL("Too bad...\nThe Bag is full..."))
      return
    end
    $bag.add(item_id, qty)
    name = (qty > 1) ? item_data.name_plural : item_data.name
    pbMessage("\\me[Item get]" + _INTL("Collected {1} {2}!", qty, name) + "\\wtnp[30]")
  elsif cmd == cmdCheck
    if !prod
      pbMessage(_INTL("{1} doesn't seem to produce anything here.", pkmn.name))
    elsif pen.stockpile >= prod.max_stockpile
      pbMessage(_INTL("{1} looks like it has plenty to give.\nBetter collect it soon!", pkmn.name))
    elsif pen.stockpile > 0
      pbMessage(_INTL("{1} is doing well.\nThere's a bit of produce ready.", pkmn.name))
    else
      pbMessage(_INTL("{1} is doing well.\nNothing ready to collect yet.", pkmn.name))
    end
  elsif cmd == cmdTake
    return unless pbConfirmMessage(_INTL("Take {1} out of the pen?", pkmn.name))
    if $player.party_full?
      pbMessage(_INTL("Too bad...\nYour party is full..."))
      return
    end
    withdrawn = pen.withdraw
    interp.setVariable(nil)
    $player.party.push(withdrawn)
    pbMessage(_INTL("{1} was returned to your party.", withdrawn.name))
  end
end

#===============================================================================
# "Livestock Sales" - sells only registered ranch-produce items (Moomoo Milk,
# Slowpoke Tail, etc.), not the player's whole Bag. Intended to be called from
# Grandma's shop event.
#===============================================================================
def pbRanchLivestockSale
  produce_items = []
  GameData::RanchProduce.each { |p| produce_items << p.item }
  produce_items.uniq!

  loop do
    owned = produce_items.select { |i| $bag.has?(i) }
    if owned.empty?
      pbMessage(_INTL("You don't have any livestock produce to sell right now."))
      break
    end
    commands = owned.map do |i|
      item_d = GameData::Item.get(i)
      _INTL("{1} x{2} (${3} each)", item_d.name, $bag.quantity(i), item_d.sell_price)
    end
    cmd = pbMessage(_INTL("What would you like to sell?"), commands, commands.length)
    break if cmd >= owned.length
    item_id  = owned[cmd]
    item_d   = GameData::Item.get(item_id)
    price    = item_d.sell_price
    qty_have = $bag.quantity(item_id)
    qty = 1
    if qty_have > 1
      params = ChooseNumberParams.new
      params.setRange(1, qty_have)
      params.setDefaultValue(qty_have)
      qty = pbMessageChooseNumber(_INTL("How many {1} would you like to sell?", item_d.name_plural), params)
    end
    next if qty <= 0
    total = price * qty
    next unless pbConfirmMessage(_INTL("I can pay ${1} for {2} {3}.\nIs that OK?", total, qty, item_d.name))
    $bag.remove(item_id, qty)
    $player.money += total
    pbMessage(_INTL("Turned over {1} {2} and got ${3}.", qty, item_d.name, total))
  end
end

#===============================================================================
# "Current Market Rates" - lists the current sell price of every registered
# ranch-produce item, regardless of whether the player owns any.
#===============================================================================
def pbRanchMarketRates
  lines = []
  GameData::RanchProduce.each do |p|
    item_d = GameData::Item.get(p.item)
    lines << _INTL("{1}: ${2} each", item_d.name, item_d.sell_price)
  end
  pbMessage(lines.uniq.join("\r\n"))
end

#===============================================================================
# Icon overlay showing which Pokémon (if any) lives in a ranch pen. The pen's
# base graphic is static and set directly on the event's page (like a sign);
# only this overlay is live, since it depends on which Pokémon is inside.
#===============================================================================
class RanchPenIconSprite
  def initialize(event, map, viewport = nil)
    @event     = event
    @map       = map
    @sprite    = IconSprite.new(0, 0, viewport)
    @sprite.ox = 16
    @sprite.oy = 40
    @shown_for = false   # false forces the first update to set the bitmap
    @disposed  = false
    update
  end

  def dispose
    @sprite.dispose
    @map      = nil
    @event    = nil
    @disposed = true
  end

  def disposed?
    @disposed
  end

  def update
    return if !@sprite || !@event
    pen     = @event.variable
    pkmn    = (pen.is_a?(RanchPenSlot) && pen.filled?) ? pen.pokemon : nil
    species = pkmn&.species
    if species != @shown_for
      @shown_for = species
      if species
        filename = GameData::Species.icon_filename_from_pokemon(pkmn)
        @sprite.setBitmap(filename || "")
      else
        @sprite.setBitmap("")
      end
    end
    @sprite.update
    @sprite.x      = ScreenPosHelper.pbScreenX(@event)
    @sprite.y      = ScreenPosHelper.pbScreenY(@event)
    @sprite.zoom_x = ScreenPosHelper.pbScreenZoomX(@event) * 0.6
    @sprite.zoom_y = @sprite.zoom_x
    pbDayNightTint(@sprite)
  end
end

EventHandlers.add(:on_new_spriteset_map, :add_ranch_pen_graphics,
  proc { |spriteset, viewport|
    map = spriteset.map
    map.events.each do |event|
      next if !event[1].name[/ranchpen/i]
      spriteset.addUserSprite(RanchPenIconSprite.new(event[1], map, viewport))
    end
  }
)
