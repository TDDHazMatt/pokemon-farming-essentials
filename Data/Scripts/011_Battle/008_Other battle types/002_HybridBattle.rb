#===============================================================================
# Hybrid Battle - a real wild Battle (real damage, real AI, real fainting,
# real EXP) with Safari-Zone-style catching layered on top, for as long as
# Rhyk (see 013_Items/009_Items_RhyksPokeball.rb) is the player's active
# battler:
#   - The player's command menu is replaced with Ball/Bait/Rock/Run instead
#     of Fight/Bag/Pokémon/Run. Ball opens the real Bag filtered to the Poké
#     Ball pocket and throws a real ball (real inventory, real per-ball catch
#     multiplier) via the same pbThrowPokeBall every Poké Ball use in the
#     game already goes through. Bait/Rock reuse the existing attention-meter
#     mechanic from SafariBattle (001_SafariBattle.rb), just aimed at a real
#     Battle::Battler instead of a FakeBattler.
#   - The wild Pokémon's data box shows the same attention gauge SafariBattle
#     draws instead of an HP bar, via the same monkey-patch technique.
#   - Everything else - damage, status, AI move choice, fainting, EXP gain,
#     the "Go! Rhyk!" send-out - is the real, unmodified Battle engine,
#     because Rhyk really is battler 0's Pokémon (a genuine party member -
#     see 013_Items/009_Items_RhyksPokeball.rb).
#
# If Rhyk faints and the player sends out a different Pokémon, none of the
# above fires anymore (the guards all check whether Rhyk is still battler
# 0's Pokémon) - the fight just continues as a fully normal battle from that
# point on. That's the entire mechanism for "reverts to a regular battle":
# nothing to explicitly undo, the override conditions simply stop matching.
#===============================================================================
class HybridBattle < Battle
  BEHAVIOR_MECHANICS = {
    aggressive_fast: {
      rock_effectiveness: 1.5, rock_anger_gain: 25,
      bait_effectiveness: 0.6, bait_calm_gain: 5,
      base_flee_chance: 25, attention_volatility: 15,
      eating_duration: 1
    },
    aggressive_slow: {
      rock_effectiveness: 1.3, rock_anger_gain: 20,
      bait_effectiveness: 0.7, bait_calm_gain: 8,
      base_flee_chance: 15, attention_volatility: 10,
      eating_duration: 2
    },
    defensive_slow: {
      rock_effectiveness: 0.7, rock_anger_gain: 8,
      bait_effectiveness: 1.4, bait_calm_gain: 20,
      base_flee_chance: 5,  attention_volatility: 8,
      eating_duration: 3
    },
    defensive_fast: {
      rock_effectiveness: 0.5, rock_anger_gain: 30,
      bait_effectiveness: 1.2, bait_calm_gain: 15,
      base_flee_chance: 30, attention_volatility: 20,
      eating_duration: 1
    },
    timid: {
      rock_effectiveness: 0.4, rock_anger_gain: 35,
      bait_effectiveness: 1.6, bait_calm_gain: 25,
      base_flee_chance: 35, attention_volatility: 25,
      eating_duration: 2
    },
    balanced: {
      rock_effectiveness: 1.0, rock_anger_gain: 15,
      bait_effectiveness: 1.0, bait_calm_gain: 15,
      base_flee_chance: 20, attention_volatility: 12,
      eating_duration: 2
    },
    erratic: {
      rock_effectiveness: :random, rock_anger_gain: :random,
      bait_effectiveness: :random, bait_calm_gain: :random,
      base_flee_chance: 20, attention_volatility: 30,
      eating_duration: :random
    },
    cautious: {
      rock_effectiveness: 0.8, rock_anger_gain: 18,
      bait_effectiveness: 1.1, bait_calm_gain: 12,
      base_flee_chance: 15, attention_volatility: 10,
      eating_duration: 2
    }
  }.freeze

  ZONE_EFFECTS = {
    interested: {
      catch_modifier: 0.5, flee_chance_modifier: 0.0,
      message: "is completely focused on you!"
    },
    very_calm: {
      catch_modifier: 0.6, flee_chance_modifier: 0.2,
      message: "seems completely relaxed..."
    },
    calm: {
      catch_modifier: 0.8, flee_chance_modifier: 0.5,
      message: "is watching peacefully."
    },
    neutral: {
      catch_modifier: 1.0, flee_chance_modifier: 1.0,
      message: "is watching you carefully."
    },
    agitated: {
      catch_modifier: 1.3, flee_chance_modifier: 1.8,
      message: "looks agitated!"
    },
    very_agitated: {
      catch_modifier: 1.6, flee_chance_modifier: 3.0,
      message: "is ready to bolt!"
    },
    enraged: {
      catch_modifier: 2.0, flee_chance_modifier: 0.0,
      message: "is too enraged to run!"
    }
  }.freeze

  attr_reader :attention_meter
  attr_reader :wild_behavior_type
  attr_reader :wild_safari_status
  attr_reader :wild_safari_status_turns

  def initialize(*args)
    super
    @attention_meter          = 50
    @wild_behavior_type       = :balanced
    @wild_mechanics           = BEHAVIOR_MECHANICS[:balanced]
    @wild_safari_status       = nil
    @wild_safari_status_turns = 0
    @wild_just_started_eating_this_round = false
  end

  #-----------------------------------------------------------------------------
  # Rhyk identification - the single source of truth every override below
  # checks. No separate "hybrid mode" flag: whether Rhyk is still battler 0's
  # Pokémon IS whether Hybrid Battle behavior is still in effect.
  #-----------------------------------------------------------------------------
  def rhyk_is_active_battler?
    b = @battlers[0]
    return !b.nil? && !b.pokemon.nil? && b.pokemon.respond_to?(:is_rhyk) && b.pokemon.is_rhyk
  end

  def pbHybridControlled?(idxBattler)
    return idxBattler == 0 && rhyk_is_active_battler?
  end

  # The wild Pokémon has no trainer, so the real pbGetOwnerFromBattlerIndex
  # correctly returns nil for it - but ThrowBait/ThrowRock's animation code
  # (Battle_Scene_BaseAnimation.rb's ballTracksHand) reads @trainer.trainer_type
  # off whatever this returns for the battler passed to it, which for those
  # two animations is always the wild battler. SafariBattle sidesteps this by
  # having its own pbGetOwnerFromBattlerIndex always return the player; here,
  # only fall back to the player when the real lookup is nil (i.e. only for
  # the ownerless wild battler) and only while Rhyk is throwing at it - every
  # other real usage of this method (trainer battles, message text) is
  # unaffected since it only ever gets a non-nil owner from super in the
  # first place.
  def pbGetOwnerFromBattlerIndex(idxBattler)
    owner = super
    return pbPlayer if owner.nil? && rhyk_is_active_battler?
    return owner
  end

  #-----------------------------------------------------------------------------
  # Classify the wild Pokémon's behavior once battlers exist, same heuristic
  # SafariBattle uses (offense/defense/speed base stat comparison).
  #-----------------------------------------------------------------------------
  def pbSetUpSides
    ret = super
    if wildBattle? && pbParty(1).length == 1 && @battlers[1]
      @wild_behavior_type = determine_behavior(@battlers[1].pokemon)
      @wild_mechanics      = BEHAVIOR_MECHANICS[@wild_behavior_type]
      @attention_meter     = 50
    end
    return ret
  end

  def determine_behavior(pkmn)
    stats = pkmn.species_data.base_stats
    atk   = stats[:ATTACK]
    def_s = stats[:DEFENSE]
    spa   = stats[:SPECIAL_ATTACK]
    spd_s = stats[:SPECIAL_DEFENSE]
    speed = stats[:SPEED]

    offensive_total = atk + spa
    defensive_total = def_s + spd_s

    if offensive_total > defensive_total + 30
      return speed > offensive_total * 0.6 ? :aggressive_fast : :aggressive_slow
    elsif defensive_total > offensive_total + 30
      return speed < 60 ? :defensive_slow : :defensive_fast
    elsif speed > (offensive_total + defensive_total) * 0.4
      return :timid
    elsif (offensive_total - defensive_total).abs < 20
      stat_vals = [atk, def_s, spa, spd_s, speed]
      return stat_vals.max - stat_vals.min < 30 ? :balanced : :erratic
    else
      return :cautious
    end
  end

  def get_current_zone
    case @attention_meter
    when 1..10   then :interested
    when 11..25  then :very_calm
    when 26..45  then :calm
    when 46..60  then :neutral
    when 61..80  then :agitated
    when 81..90  then :very_agitated
    when 91..100 then :enraged
    else :neutral
    end
  end

  #-----------------------------------------------------------------------------
  # Command phase: for battler 0, show the Safari-style menu instead of
  # Fight/Bag/Pokémon/Run whenever Rhyk is still active. Bypassing pbFightMenu
  # entirely (rather than letting it call pbCanShowFightMenu?) also means
  # Rhyk's empty moveset never falls back to auto-Struggle.
  #-----------------------------------------------------------------------------
  def pbCommandMenu(idxBattler, firstAction)
    return 0 if pbHybridControlled?(idxBattler)
    return super
  end

  def pbFightMenu(idxBattler)
    return pbHybridFightMenu(idxBattler) if pbHybridControlled?(idxBattler)
    return super
  end

  def pbCommandPhase
    was_hybrid = rhyk_is_active_battler?
    super
    return if @decision != 0
    if was_hybrid && !rhyk_is_active_battler?
      # Rhyk fainted and was replaced this round - snap the wild Pokémon's
      # data box back to a real HP bar immediately rather than waiting for
      # its next incidental refresh.
      @scene.pbRefreshOne(1)
      return
    end
    return if !rhyk_is_active_battler?
    # Eating blocks the wild Pokémon's attack this round (paralysis/sleep/
    # freeze/confusion already do this for free via the normal engine).
    pbClearChoice(1) if @wild_safari_status == :eating
  end

  def pbEndOfRoundPhase
    super
    return if @decision != 0
    return if !rhyk_is_active_battler?
    if @wild_just_started_eating_this_round
      @wild_just_started_eating_this_round = false
    else
      hybrid_tick_safari_status
    end
    hybrid_apply_turn_decay
    @scene.pbSafariRefreshAttention
    zone = get_current_zone
    pbDisplayBrief(_INTL("{1} {2}", @battlers[1].pokemon.name, ZONE_EFFECTS[zone][:message]))
  end

  #-----------------------------------------------------------------------------
  # The Ball/Bait/Rock/Run menu itself (modeled on
  # SafariBattle#pbSafariCommandMenu / #pbStartBattle's command loop, but
  # integrating with the real command-phase/choice system instead of a
  # hand-rolled battle loop).
  #-----------------------------------------------------------------------------
  def pbHybridFightMenu(idxBattler)
    wild = @battlers[1]
    loop do
      cmd = @scene.pbSafariCommandMenu(0)
      case cmd
      when 0   # Ball
        next if !pbHybridThrowBall(idxBattler)
        pbClearChoice(idxBattler)
        return true
      when 1   # Bait
        pbDisplayBrief(_INTL("{1} threw some bait at the {2}!", pbPlayer.name, wild.name))
        @scene.pbThrowBait
        hybrid_throw_bait
        hybrid_check_flee
        pbClearChoice(idxBattler)
        return true
      when 2   # Rock
        pbDisplayBrief(_INTL("{1} threw a rock at the {2}!", pbPlayer.name, wild.name))
        @scene.pbThrowRock
        hybrid_throw_rock
        hybrid_check_flee
        pbClearChoice(idxBattler)
        return true
      when 3   # Run
        return pbRunMenu(idxBattler)
      else
        next
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Ball: open the Bag filtered to the Poké Ball pocket only (same
  # pbChooseItemScreen(proc) pattern already used by
  # 012_Overworld/006c_Overworld_PlantableSpot.rb for the Spreader's filtered
  # item choice), then throw the chosen real ball via the real,
  # already-shared pbThrowPokeBall (CatchAndStoreMixin) - a real Battle
  # handles storage/EXP/decision automatically, unlike SafariBattle which
  # has to hand-roll all of that itself.
  #-----------------------------------------------------------------------------
  def pbHybridThrowBall(idxBattler)
    chosen = nil
    pbFadeOutIn do
      scene  = PokemonBag_Scene.new
      screen = PokemonBagScreen.new(scene, $bag)
      chosen = screen.pbChooseItemScreen(proc { |item| GameData::Item.get(item).is_poke_ball? })
    end
    return false if !chosen
    wild = @battlers[1].pokemon
    zone_effects = ZONE_EFFECTS[get_current_zone]
    modified_catch_rate = (wild.species_data.catch_rate * zone_effects[:catch_modifier]).to_i.clamp(1, 255)
    $bag.remove(chosen)
    pbThrowPokeBall(idxBattler, chosen, modified_catch_rate, true)
    if @decision == 0
      # Didn't catch it and the battle didn't otherwise end - agitate (unless
      # eating) and check for a flee, exactly like SafariBattle's own miss
      # handling.
      unless @wild_safari_status == :eating
        @attention_meter = (@attention_meter + rand(11) + 5).clamp(0, 100)
        @scene.pbSafariRefreshAttention
      end
      hybrid_check_flee
    end
    return true
  end

  #-----------------------------------------------------------------------------
  # Bait / Rock / eating status / decay / flee - ported from SafariBattle,
  # reading a real Battle::Battler's Pokémon instead of a FakeBattler's.
  #-----------------------------------------------------------------------------
  def hybrid_throw_bait
    wild = @battlers[1].pokemon
    effectiveness = @wild_mechanics[:bait_effectiveness]
    effectiveness = (rand(121) + 40) / 100.0 if effectiveness == :random
    base_decrease = @wild_mechanics[:bait_calm_gain]
    base_decrease = rand(26) + 5 if base_decrease == :random
    third_v = [@wild_mechanics[:attention_volatility] / 3, 1].max
    meter_change = (base_decrease * effectiveness).to_i + rand(third_v * 2 + 1) - third_v
    @attention_meter = (@attention_meter - meter_change).clamp(0, 100)
    hybrid_apply_eating_status(wild)
    @scene.pbSafariRefreshAttention
  end

  def hybrid_throw_rock
    wild = @battlers[1].pokemon
    effectiveness = @wild_mechanics[:rock_effectiveness]
    effectiveness = (rand(121) + 40) / 100.0 if effectiveness == :random
    base_gain = @wild_mechanics[:rock_anger_gain]
    base_gain = rand(31) + 10 if base_gain == :random
    half_v = @wild_mechanics[:attention_volatility] / 2
    meter_change = (base_gain * effectiveness).to_i + rand(half_v * 2 + 1) - half_v
    @attention_meter = (@attention_meter + meter_change).clamp(0, 100)
    hybrid_clear_safari_status(wild, true) if @wild_safari_status == :eating
    @scene.pbSafariRefreshAttention
    pbDisplayBrief(_INTL("{1} looks angry!", wild.name))
  end

  def hybrid_apply_eating_status(wild)
    duration = @wild_mechanics[:eating_duration]
    duration = rand(3) + 1 if duration == :random
    @wild_safari_status                  = :eating
    @wild_safari_status_turns            = duration
    @wild_just_started_eating_this_round = true
    pbDisplayBrief(_INTL("{1} is eating!", wild.name))
  end

  def hybrid_clear_safari_status(wild, show_message = true)
    @wild_safari_status       = nil
    @wild_safari_status_turns = 0
    pbDisplayBrief(_INTL("{1} stopped eating.", wild.name)) if show_message
  end

  def hybrid_tick_safari_status
    return unless @wild_safari_status == :eating
    @wild_safari_status_turns -= 1
    if @wild_safari_status_turns <= 0
      hybrid_clear_safari_status(@battlers[1].pokemon)
    else
      pbDisplayBrief(_INTL("{1} is still eating...", @battlers[1].pokemon.name))
    end
  end

  def hybrid_apply_turn_decay
    return if @wild_safari_status == :eating
    if @attention_meter > 50
      @attention_meter -= 3
    elsif @attention_meter < 50
      @attention_meter += 3
    end
    @attention_meter += rand(21) - 10 if @wild_behavior_type == :erratic
    @attention_meter = @attention_meter.clamp(0, 100)
  end

  def hybrid_check_flee
    wild = @battlers[1].pokemon
    zone_effects = ZONE_EFFECTS[get_current_zone]
    if @wild_safari_status == :eating
      pbDisplayBrief(_INTL("{1} is too busy eating to flee!", wild.name))
      return
    end
    return if zone_effects[:flee_chance_modifier] == 0.0
    base_flee     = @wild_mechanics[:base_flee_chance]
    modified_flee = (base_flee * zone_effects[:flee_chance_modifier]).to_i
    if rand(100) < modified_flee
      pbSEPlay("Battle flee")
      pbDisplay(_INTL("{1} fled!", wild.name))
      @decision = 3
    end
  end
end

#===============================================================================
# Wild data box (battler 1 only): draw the same attention gauge SafariBattle
# draws, for as long as Rhyk is still battler 0's Pokémon. Chains onto
# SafariBattle's own refresh_hp alias (001_SafariBattle.rb, loaded earlier in
# this same folder) rather than replacing it, so both battle types' guards
# compose correctly.
#===============================================================================
class Battle::Scene::PokemonDataBox
  def hybrid_battle?
    return false if @battler.index != 1
    return @battler.respond_to?(:battle) && @battler.battle.is_a?(HybridBattle) &&
           @battler.battle.rhyk_is_active_battler?
  end

  alias __hybrid__refresh_hp refresh_hp unless method_defined?(:__hybrid__refresh_hp)

  def refresh_hp
    return __hybrid__refresh_hp unless hybrid_battle?

    @hpNumbers.bitmap.clear
    @hpBar.src_rect.width = 0

    battle = @battler.battle
    zone   = battle.get_current_zone
    color  = Battle::Scene::PokemonDataBox::SAFARI_ZONE_BAR_COLORS.fetch(zone, Color.new(200, 200, 200))
    meter  = battle.attention_meter.to_i

    bar_x = @spriteBaseX + 102
    bar_y = 40
    bar_w = @hpBarBitmap.width
    bar_h = @hpBarBitmap.height / 3

    fill_w = (bar_w * meter / 100.0).to_i

    if meter <= 10 || meter >= 91
      self.bitmap.fill_rect(bar_x - 1, bar_y - 1, bar_w + 2, bar_h + 2,
                            Color.new(255, 215, 0))
    end

    self.bitmap.fill_rect(bar_x, bar_y, bar_w, bar_h, Color.new(40, 40, 40))
    self.bitmap.fill_rect(bar_x, bar_y, fill_w, bar_h, color) if fill_w > 0

    [10, 25, 45, 60, 80, 90].each do |pct|
      mx = bar_x + (bar_w * pct / 100)
      self.bitmap.fill_rect(mx, bar_y, 1, bar_h, Color.new(0, 0, 0, 180))
    end

    if battle.wild_safari_status == :eating
      old_size = self.bitmap.font.size
      self.bitmap.font.size = 16
      pbDrawTextPositions(self.bitmap, [
        [_INTL("EAT x{1}", battle.wild_safari_status_turns),
         @spriteBaseX + 22, 40, :left,
         Color.new(80, 220, 80), Color.new(20, 80, 20)]
      ])
      self.bitmap.font.size = old_size
    end
  end
end

#===============================================================================
# Keep the trainer sprite standing beside Rhyk for the whole fight (Safari-
# Zone style) instead of sliding off-screen after his send-out. Falls back to
# the normal fade the instant Rhyk isn't the one being sent out - in
# particular, this is what makes the trainer sprite properly disappear again
# once Rhyk faints and a replacement Pokémon is sent out, reverting the
# battle to a normal appearance with no extra code needed for that case.
#===============================================================================
class Battle::Scene
  alias __hybrid__pbSendOutBattlers pbSendOutBattlers unless method_defined?(:__hybrid__pbSendOutBattlers)

  def pbSendOutBattlers(sendOuts, startBattle = false)
    if @battle.is_a?(HybridBattle) && sendOuts.any? { |b| b[0] == 0 && b[1]&.respond_to?(:is_rhyk) && b[1].is_rhyk }
      return pbHybridSendOutBattlers(sendOuts, startBattle)
    end
    return __hybrid__pbSendOutBattlers(sendOuts, startBattle)
  end

  # Identical to the base pbSendOutBattlers (004_Scene_PlayAnimations.rb),
  # except there's no Animation::PlayerFade at all - the trainer sprite is
  # left exactly where pbCreateTrainerBackSprite put it.
  def pbHybridSendOutBattlers(sendOuts, startBattle = false)
    return if sendOuts.length == 0
    while inPartyAnimation?
      pbUpdate
    end
    @briefMessage = false
    sendOutAnims = []
    sendOuts.each_with_index do |b, i|
      pkmn = @battle.battlers[b[0]].effects[PBEffects::Illusion] || b[1]
      pbChangePokemon(b[0], pkmn)
      pbRefresh
      if @battle.opposes?(b[0])
        sendOutAnim = Animation::PokeballTrainerSendOut.new(
          @sprites, @viewport, @battle.pbGetOwnerIndexFromBattlerIndex(b[0]) + 1,
          @battle.battlers[b[0]], startBattle, i
        )
      else
        sendOutAnim = Animation::PokeballPlayerSendOut.new(
          @sprites, @viewport, @battle.pbGetOwnerIndexFromBattlerIndex(b[0]) + 1,
          @battle.battlers[b[0]], startBattle, i
        )
      end
      dataBoxAnim = Animation::DataBoxAppear.new(@sprites, @viewport, b[0])
      sendOutAnims.push([sendOutAnim, dataBoxAnim, false])
    end
    loop do
      sendOutAnims.each do |a|
        next if a[2]
        a[0].update
        a[1].update if a[0].animDone?
        a[2] = true if a[1].animDone?
      end
      pbUpdate
      break if !inPartyAnimation? && sendOutAnims.none? { |a| !a[2] }
    end
    sendOutAnims.each do |a|
      a[0].dispose
      a[1].dispose
    end
    sendOuts.each do |b|
      next if !@battle.showAnims || !@battle.battlers[b[0]].shiny?
      if Settings::SUPER_SHINY && @battle.battlers[b[0]].super_shiny?
        pbCommonAnimation("SuperShiny", @battle.battlers[b[0]])
      else
        pbCommonAnimation("Shiny", @battle.battlers[b[0]])
      end
    end
  end
end
