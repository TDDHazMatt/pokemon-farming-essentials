#===============================================================================
# Selling Pokémon - a restricted Party/PC Storage screen showing only
# "Summary" and "Sell" per Pokémon (instead of the full Switch/Item/Mark/
# Release/etc. command set), plus the pricing rules behind it.
#
# Pricing has four layers, checked in this order:
#   1. An active Special Request for this exact species (012_Overworld/
#      015_Overworld_SpecialRequests.rb) - someone specifically wants this
#      one, so it outbids everything else, including an emergency liquidation
#      rate.
#   2. A situational override (PokemonSalePrice.with_situational_price_per_level)
#      - active only for the duration of a specific call, e.g. Grandma's
#        weekly-bills liquidation offer prices everything at $20/level instead
#        of the normal rate, regardless of species.
#   3. A per-species override (PokemonSalePrice::SPECIES_PRICE_PER_LEVEL) -
#      rarer/more desirable species can be worth more per level than default.
#   4. PokemonSalePrice::DEFAULT_PRICE_PER_LEVEL ($50) otherwise.
#===============================================================================
module PokemonSalePrice
  DEFAULT_PRICE_PER_LEVEL = 50

  # Species => price-per-level. Empty by default - infrastructure for a
  # future "rarer Pokémon are worth more" pass, not populated yet.
  SPECIES_PRICE_PER_LEVEL = {}

  @situational_price_per_level = nil

  def self.situational_price_per_level
    return @situational_price_per_level
  end

  # Runs the block with every sale priced at price_per_level regardless of
  # species, restoring whatever override (or lack of one) was active before -
  # even if the block raises. Nest freely; the previous value always comes
  # back once the innermost block finishes.
  def self.with_situational_price_per_level(price_per_level)
    old = @situational_price_per_level
    @situational_price_per_level = price_per_level
    yield
  ensure
    @situational_price_per_level = old
  end

  def self.price_per_level_for(pkmn)
    request = pbSpecialRequests.active_request_for(pkmn.species)
    return request.price_per_level if request
    return @situational_price_per_level if @situational_price_per_level
    return SPECIES_PRICE_PER_LEVEL[pkmn.species] || DEFAULT_PRICE_PER_LEVEL
  end

  def self.price_for(pkmn)
    return price_per_level_for(pkmn) * pkmn.level
  end
end

#===============================================================================
# Shared "confirm and sell" step, used by both the Party and Storage sell
# screens below - eligibility checks mirror PokemonStorageScreen#pbRelease
# (017_UI_PokemonStorage.rb), since selling is just as permanent as releasing.
# Yields (with no arguments) to actually remove the Pokémon from wherever it
# lives once the player confirms - the caller supplies that, since removal
# differs between the party array and PC storage. Returns whether a sale
# went through.
#===============================================================================
def pbSellPokemonConfirm(pkmn)
  if pkmn.egg?
    pbMessage(_INTL("You can't sell an Egg."))
    return false
  elsif pkmn.mail
    pbMessage(_INTL("Please remove the mail from {1} first.", pkmn.name))
    return false
  elsif pkmn.cannot_release
    pbMessage(_INTL("{1} refuses to leave you!", pkmn.name))
    return false
  end
  price   = PokemonSalePrice.price_for(pkmn)
  request = pbSpecialRequests.active_request_for(pkmn.species)
  prompt  = if request
              _INTL("This fulfills a special request!\nSell {1} (Lv. {2}) for ${3}?", pkmn.name, pkmn.level, price)
            else
              _INTL("Sell {1} (Lv. {2}) for ${3}?", pkmn.name, pkmn.level, price)
            end
  return false unless pbConfirmMessage(prompt)
  yield
  $player.money += price
  pbSpecialRequests.fulfill!(pkmn.species)
  pbMessage(_INTL("Sold {1} for ${2}.", pkmn.name, price))
  return true
end

#===============================================================================
# Party screen, restricted to Summary + Sell.
#===============================================================================
class PokemonPartyScreen
  def pbSellPokemonScreen
    helptext = _INTL("Choose a Pokémon to sell, or cancel.")
    @scene.pbStartScene(@party, helptext)
    loop do
      break if @party.length <= 1   # never sell your last Pokémon
      @scene.pbSetHelpText(helptext)
      pkmnid = @scene.pbChoosePokemon
      break if pkmnid < 0
      pkmn = @party[pkmnid]
      next if !pkmn
      commands    = []
      cmd_summary = -1
      cmd_sell    = -1
      commands[cmd_summary = commands.length] = _INTL("Summary")
      commands[cmd_sell    = commands.length] = _INTL("Sell")
      commands[commands.length]               = _INTL("Cancel")
      command = @scene.pbShowCommands(_INTL("Do what with {1}?", pkmn.name), commands)
      if command == cmd_summary
        @scene.pbSummary(pkmnid) { @scene.pbSetHelpText(helptext) }
      elsif command == cmd_sell
        if pbSellPokemonConfirm(pkmn) { @party.delete_at(pkmnid) }
          @scene.pbHardRefresh
        end
      end
    end
    @scene.pbEndScene
  end
end

#===============================================================================
# PC Storage screen, restricted to Summary + Sell. Mirrors the stock
# "Withdraw" mode's box-browsing loop (017_UI_PokemonStorage.rb, pbStartScreen
# command 1) exactly, since that's already the proven pattern for "browse
# boxes, act on one Pokémon, repeat" - just with a different per-Pokémon
# command set.
#===============================================================================
class PokemonStorageScreen
  def pbSellPokemonScreen
    @scene.pbStartBox(self, 1)
    loop do
      selected = @scene.pbSelectBox(@storage.party)
      if selected.nil?
        next if pbConfirm(_INTL("Continue Box operations?"))
        break
      end
      case selected[0]
      when -2   # Party Pokémon - this screen only sells from boxes
        pbDisplay(_INTL("Sell Pokémon from your party using the Party screen instead."))
        next
      when -3   # Close box
        if pbConfirm(_INTL("Exit from the Box?"))
          pbSEPlay("PC close")
          break
        end
        next
      when -4   # Box name
        pbBoxCommands
        next
      end
      pokemon = @storage[selected[0], selected[1]]
      next if !pokemon
      commands    = []
      cmd_summary = -1
      cmd_sell    = -1
      commands[cmd_summary = commands.length] = _INTL("Summary")
      commands[cmd_sell    = commands.length] = _INTL("Sell")
      commands[commands.length]               = _INTL("Cancel")
      command = pbShowCommands(_INTL("{1} is selected.", pokemon.name), commands)
      if command == cmd_summary
        pbSummary(selected, nil)
      elsif command == cmd_sell
        box, index = selected
        if pbSellPokemonConfirm(pokemon) { @storage.pbDelete(box, index) }
          @scene.pbRefresh
        end
      end
    end
    @scene.pbCloseBox
  end
end

#===============================================================================
# Entry points - open a fresh scene/screen pair and go straight into the
# restricted sell flow, mirroring how pbPokemonScreen/PC storage call sites
# set themselves up elsewhere (e.g. 016_UI/019_UI_PC.rb).
#===============================================================================
def pbSellPokemonFromParty
  scene  = PokemonParty_Scene.new
  screen = PokemonPartyScreen.new(scene, $player.party)
  screen.pbSellPokemonScreen
end

def pbSellPokemonFromStorage
  scene  = PokemonStorageScene.new
  screen = PokemonStorageScreen.new(scene, $PokemonStorage)
  screen.pbSellPokemonScreen
end

#===============================================================================
# "Pokemon Sales" - Grandma's dialog choice on the Barn map (Map032, event
# "Grandma"). Sells at the normal rate (no situational override) - contrast
# with the discounted $20/level emergency sale in
# 012_Overworld/013_Overworld_WeeklyBills.rb's liquidation offer.
#===============================================================================
def pbGrandmaPokemonSale
  commands = [_INTL("From Party"), _INTL("From PC"), _INTL("Nevermind")]
  cmd = pbMessage(_INTL("Sell a Pokémon from where?"), commands, commands.length)
  case cmd
  when 0 then pbSellPokemonFromParty
  when 1 then pbSellPokemonFromStorage
  end
end
