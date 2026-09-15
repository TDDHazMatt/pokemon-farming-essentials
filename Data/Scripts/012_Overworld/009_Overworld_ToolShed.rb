#===============================================================================
# The Tool Shed lets the player store key-item tools (anything flagged
# ShedTool in items.txt - currently the Spreader, Harvester, and the three
# fishing Rods) away from their Bag, and take them back out again. Storage is
# just $PokemonGlobal.shed_tools (an array of item IDs), which starts with a
# Spreader and a Harvester already in it.
#
# New tools only require the ShedTool flag on their PBS entry - no new
# interaction code needed.
#===============================================================================

#===============================================================================
# "Get Tools" - take a tool out of the shed and into the Bag.
#===============================================================================
def pbToolShedGetTools
  loop do
    stored = $PokemonGlobal.shed_tools.select { |item| GameData::Item.exists?(item) }
    if stored.empty?
      pbMessage(_INTL("There's nothing in the shed right now."))
      break
    end
    commands = stored.map { |item| GameData::Item.get(item).name }
    cmd = pbMessage(_INTL("Which tool would you like to take?"), commands, -1)
    break if cmd < 0
    item_id = stored[cmd]
    item_data = GameData::Item.get(item_id)
    if !$bag.can_add?(item_id)
      pbMessage(_INTL("Too bad...\nThe Bag is full..."))
      next
    end
    $bag.add(item_id)
    $PokemonGlobal.shed_tools.delete(item_id)
    pbMessage(_INTL("Took the {1} out of the shed.", item_data.name))
  end
end

#===============================================================================
# "Store Tools" - put a tool from the Bag away in the shed. Also clears the
# tool slot if the stored tool was the active one, plus the Spreader's loaded
# item specifically, since that state would otherwise silently keep affecting
# the game after the item's put away.
#===============================================================================
def pbToolShedStoreTools
  loop do
    owned = []
    GameData::Item.each { |item| owned << item.id if item.is_shed_tool? && $bag.has?(item.id) }
    if owned.empty?
      pbMessage(_INTL("You don't have any tools on you to store."))
      break
    end
    commands = owned.map { |item| GameData::Item.get(item).name }
    cmd = pbMessage(_INTL("Which tool would you like to store?"), commands, -1)
    break if cmd < 0
    item_id = owned[cmd]
    item_data = GameData::Item.get(item_id)
    $bag.remove(item_id)
    $PokemonGlobal.active_tool = nil if $PokemonGlobal.active_tool == item_id
    $PokemonGlobal.spreader_loaded_item = nil if item_id == :SPREADER
    $PokemonGlobal.shed_tools.push(item_id) unless $PokemonGlobal.shed_tools.include?(item_id)
    pbMessage(_INTL("Stored the {1} in the shed.", item_data.name))
  end
end
