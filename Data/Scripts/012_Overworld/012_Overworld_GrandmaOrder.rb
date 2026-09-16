#===============================================================================
# Grandma's "Order Goods" - a farm-supply catalog she orders in for you rather
# than handing over immediately. Reuses the core PokemonMartScreen/BuyAdapter
# buy flow (quantity picking, running total, money deduction all just work),
# swapping in a custom adapter whose addItem/removeItem redirect purchases
# into a pending GrandmaOrder instead of straight into the Bag.
#
# The order becomes collectible HOURS_TO_DELIVER game-hours after the buying
# session ends, from a /grandmaorderball/i event placed near her (its
# visibility is driven live by GrandmaOrderBallSprite below, the same
# technique RanchPenIconSprite uses).
#===============================================================================
class GrandmaOrder
  HOURS_TO_DELIVER = 4

  attr_reader :items      # item_id => quantity
  attr_reader :ready_at   # pbGetTimeNow.to_i value, or nil until finalized

  def initialize
    @items    = {}
    @ready_at = nil
  end

  def add(item_id, qty = 1)
    @items[item_id] = (@items[item_id] || 0) + qty
  end

  def remove(item_id, qty = 1)
    return if !@items[item_id]
    @items[item_id] -= qty
    @items.delete(item_id) if @items[item_id] <= 0
  end

  def empty?
    return @items.empty?
  end

  # Starts the delivery countdown from right now - called once the buying
  # session ends, so it's "N hours from when you finished ordering", not
  # reset per item.
  def finalize
    @ready_at = pbGetTimeNow.to_i + HOURS_TO_DELIVER * 3600
  end

  def ready?
    return !@ready_at.nil? && pbGetTimeNow.to_i >= @ready_at
  end
end

#===============================================================================
# Redirects purchases into the pending order instead of the Bag. Money is
# still deducted normally (getMoney/setMoney are inherited unchanged) - only
# where the items themselves go is different.
#===============================================================================
class GrandmaOrderAdapter < PokemonMartAdapter
  def initialize(order)
    @order = order
  end

  def addItem(item)
    @order.add(item, 1)
    return true
  end

  def removeItem(item)
    @order.remove(item, 1)
    return true
  end
end

GRANDMA_ORDER_STOCK = [
  # Seeds
  :CARROTSEED, :LETTUCESEED, :POTATOSEED, :TOMATOSEED, :ONIONSEED,
  :PUMPKINSEED, :CORNSEED, :WHEATSEED, :CABBAGESEED,
  # Mulch
  :GROWTHMULCH, :DAMPMULCH, :GOOEYMULCH, :STABLEMULCH,
  # Basic (status-cure) berries
  :CHERIBERRY, :CHESTOBERRY, :PECHABERRY, :RAWSTBERRY, :ASPEARBERRY,
  # A starter Apricorn
  :REDAPRICORN,
  # Tools
  :HOE, :AUTOTILLER
].freeze

#===============================================================================
# "Order Goods" - call from Grandma's event script box.
#===============================================================================
def pbGrandmaOrderGoods
  order = $PokemonGlobal.grandma_order
  if order
    if order.ready?
      pbMessage(_INTL("\\rYour last order's come in! It's waiting for you on the counter."))
    else
      pbMessage(_INTL("\\rYour last order hasn't come in yet, dear. Give it a little more time."))
    end
    return
  end
  stock = GRANDMA_ORDER_STOCK.select { |i| GameData::Item.exists?(i) }
  new_order = GrandmaOrder.new
  scene  = PokemonMart_Scene.new
  screen = PokemonMartScreen.new(scene, stock.dup)
  screen.instance_variable_set(:@adapter, GrandmaOrderAdapter.new(new_order))
  pbMessage(_INTL("\\rWhat would you like me to order in for you?"))
  screen.pbBuyScreen
  if new_order.empty?
    pbMessage(_INTL("\\rAlright, let me know if you change your mind."))
    return
  end
  new_order.finalize
  $PokemonGlobal.grandma_order = new_order
  pbMessage(_INTL("\\rAlright, I'll get that ordered in for you. It should be ready in about four hours - I'll leave it on the counter for you."))
end

#===============================================================================
# The counter-side delivery ball. Call from a /grandmaorderball/i event's
# script box.
#===============================================================================
def pbGrandmaOrderReady?
  order = $PokemonGlobal.grandma_order
  return !order.nil? && order.ready?
end

def pbCollectGrandmaOrder
  order = $PokemonGlobal.grandma_order
  if !order || !order.ready?
    pbMessage(_INTL("There's nothing here right now."))
    return
  end
  lines = []
  order.items.each do |item_id, qty|
    next if qty <= 0
    if !$bag.can_add?(item_id, qty)
      pbMessage(_INTL("Too bad...\nThe Bag is full..."))
      break
    end
    $bag.add(item_id, qty)
    item_data = GameData::Item.get(item_id)
    name = (qty > 1) ? item_data.name_plural : item_data.name
    lines << _INTL("{1} {2}", qty, name)
    order.items[item_id] = 0
  end
  order.items.delete_if { |_id, remaining| remaining <= 0 }
  pbMessage("\\me[Item get]" + _INTL("Your order's here! Got: {1}.", lines.join(", "))) if !lines.empty?
  $PokemonGlobal.grandma_order = nil if order.items.empty?
end

#===============================================================================
# Shows "Object ball" once the order is ready, invisible otherwise.
#===============================================================================
class GrandmaOrderBallSprite
  def initialize(event)
    @event = event
    @shown = nil
    update
  end

  def dispose
    @event = nil
  end

  def disposed?
    @event.nil?
  end

  def update
    return if !@event
    ready = pbGrandmaOrderReady?
    return if ready == @shown
    @shown = ready
    @event.character_name = ready ? "Object ball" : ""
  end
end

EventHandlers.add(:on_new_spriteset_map, :show_grandma_order_ball,
  proc { |spriteset, _viewport|
    map = spriteset.map
    map.events.each_value do |event|
      next if !event.name[/grandmaorderball/i]
      spriteset.addUserSprite(GrandmaOrderBallSprite.new(event))
    end
  }
)
