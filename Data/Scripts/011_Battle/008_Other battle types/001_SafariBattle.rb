#===============================================================================
# Simple battler class for the wild Pokémon in a Safari Zone battle
#===============================================================================
class Battle::FakeBattler
  attr_reader :battle
  attr_reader :index
  attr_reader :pokemon
  attr_reader :owned

  def initialize(battle, index)
    @battle  = battle
    @pokemon = battle.party2[0]
    @index   = index
  end

  def pokemonIndex;   return 0;                     end
  def species;        return @pokemon.species;      end
  def gender;         return @pokemon.gender;       end
  def status;         return @pokemon.status;       end
  def hp;             return @pokemon.hp;           end
  def level;          return @pokemon.level;        end
  def name;           return @pokemon.name;         end
  def totalhp;        return @pokemon.totalhp;      end
  def displayGender;  return @pokemon.gender;       end
  def shiny?;         return @pokemon.shiny?;       end
  def super_shiny?;   return @pokemon.super_shiny?; end

  def isSpecies?(check_species)
    return @pokemon&.isSpecies?(check_species)
  end

  def fainted?;       return false; end
  def shadowPokemon?; return false; end
  def hasMega?;       return false; end
  def mega?;          return false; end
  def hasPrimal?;     return false; end
  def primal?;        return false; end
  def captured;       return false; end
  def captured=(value); end

  def owned?
    return $player.owned?(pokemon.species)
  end

  def pbThis(lowerCase = false)
    return (lowerCase) ? _INTL("the wild {1}", name) : _INTL("The wild {1}", name)
  end

  def opposes?(i)
    i = i.index if i.is_a?(Battle::FakeBattler)
    return (@index & 1) != (i & 1)
  end

  def pbReset; end
end

#===============================================================================
# Repurpose the wild Pokémon's existing HP bar as the attention meter.
# Draws the colored attention bar directly onto PokemonDataBox when the
# enclosing battle is a SafariBattle.
#===============================================================================
class Battle::Scene::PokemonDataBox
  SAFARI_ZONE_BAR_COLORS = {
    interested:    Color.new(150, 100, 255),
    very_calm:     Color.new(100, 150, 255),
    calm:          Color.new(100, 220, 100),
    neutral:       Color.new(255, 220, 100),
    agitated:      Color.new(255, 150,  50),
    very_agitated: Color.new(255,  50,  50),
    enraged:       Color.new(200,   0,   0)
  }

  def safari_battle?
    @battler.respond_to?(:battle) && @battler.battle.is_a?(SafariBattle)
  end

  alias __safari__refresh_hp refresh_hp unless method_defined?(:__safari__refresh_hp)

  def refresh_hp
    return __safari__refresh_hp unless safari_battle?

    # Hide the standard HP bar overlay sprite
    @hpNumbers.bitmap.clear
    @hpBar.src_rect.width = 0

    battle = @battler.battle
    zone   = battle.get_current_zone
    color  = SAFARI_ZONE_BAR_COLORS.fetch(zone, Color.new(200, 200, 200))
    meter  = battle.attention_meter.to_i

    # HP bar position within the data box bitmap
    bar_x = @spriteBaseX + 102
    bar_y = 40
    bar_w = @hpBarBitmap.width
    bar_h = @hpBarBitmap.height / 3

    fill_w = (bar_w * meter / 100.0).to_i

    # Gold safe-zone border (drawn before track so track appears inside)
    if meter <= 10 || meter >= 91
      self.bitmap.fill_rect(bar_x - 1, bar_y - 1, bar_w + 2, bar_h + 2,
                            Color.new(255, 215, 0))
    end

    # Dark track
    self.bitmap.fill_rect(bar_x, bar_y, bar_w, bar_h, Color.new(40, 40, 40))

    # Colored attention fill
    self.bitmap.fill_rect(bar_x, bar_y, fill_w, bar_h, color) if fill_w > 0

    # Zone boundary tick marks at 10/25/45/60/80/90 percent
    [10, 25, 45, 60, 80, 90].each do |pct|
      mx = bar_x + (bar_w * pct / 100)
      self.bitmap.fill_rect(mx, bar_y, 1, bar_h, Color.new(0, 0, 0, 180))
    end

    # Eating status badge in place of status icon
    if battle.safari_status == :eating
      old_size = self.bitmap.font.size
      self.bitmap.font.size = 16
      pbDrawTextPositions(self.bitmap, [
        [_INTL("EAT x{1}", battle.safari_status_turns),
         @spriteBaseX + 22, 40, :left,
         Color.new(80, 220, 80), Color.new(20, 80, 20)]
      ])
      self.bitmap.font.size = old_size
    end
  end
end

#===============================================================================
# Data box for safari battles (ball count display)
#===============================================================================
class Battle::Scene::SafariDataBox < Sprite
  attr_accessor :selected

  def initialize(battle, viewport = nil)
    super(viewport)
    @selected    = 0
    @battle      = battle
    @databox     = AnimatedBitmap.new(_INTL("Graphics/UI/Battle/databox_safari"))
    self.x       = Graphics.width - 232
    self.y       = Graphics.height - 184
    @contents    = Bitmap.new(@databox.width, @databox.height)
    self.bitmap  = @contents
    self.visible = false
    self.z       = 50
    pbSetSystemFont(self.bitmap)
    refresh
  end

  def refresh
    self.bitmap.clear
    self.bitmap.blt(0, 0, @databox.bitmap, Rect.new(0, 0, @databox.width, @databox.height))
    base   = Color.new(72, 72, 72)
    shadow = Color.new(184, 184, 184)
    textpos = []
    textpos.push([_INTL("Safari Balls"), 30, 14, :left, base, shadow])
    textpos.push([_INTL("Left: {1}", @battle.ballCount), 30, 44, :left, base, shadow])
    pbDrawTextPositions(self.bitmap, textpos)
  end
end

#===============================================================================
# Shows the player throwing bait at a wild Pokémon in a Safari battle.
#===============================================================================
class Battle::Scene::Animation::ThrowBait < Battle::Scene::Animation
  include Battle::Scene::Animation::BallAnimationMixin

  def initialize(sprites, viewport, battler)
    @battler = battler
    @trainer = battler.battle.pbGetOwnerFromBattlerIndex(battler.index)
    super(sprites, viewport)
  end

  def createProcesses
    batSprite = @sprites["pokemon_#{@battler.index}"]
    traSprite = @sprites["player_1"]
    ballPos = Battle::Scene.pbBattlerPosition(@battler.index, batSprite.sideSize)
    ballStartX = traSprite.x
    ballStartY = traSprite.y - (traSprite.bitmap.height / 2)
    ballMidX   = 0
    ballMidY   = 122
    ballEndX   = ballPos[0] - 40
    ballEndY   = ballPos[1] - 4
    trainer = addSprite(traSprite, PictureOrigin::BOTTOM)
    ball = addNewSprite(ballStartX, ballStartY,
                        "Graphics/Battle animations/safari_bait", PictureOrigin::CENTER)
    ball.setZ(0, batSprite.z + 1)
    if traSprite.bitmap.width >= traSprite.bitmap.height * 2
      ballStartX, ballStartY = trainerThrowingFrames(ball, trainer, traSprite)
    end
    delay = ball.totalDuration
    ball.setSE(delay, "Battle throw")
    createBallTrajectory(ball, delay, 12,
                         ballStartX, ballStartY, ballMidX, ballMidY, ballEndX, ballEndY)
    ball.setZ(9, batSprite.z + 1)
    delay = ball.totalDuration
    ball.moveOpacity(delay + 8, 2, 0)
    ball.setVisible(delay + 10, false)
    battler = addSprite(batSprite, PictureOrigin::BOTTOM)
    delay = ball.totalDuration + 3
    2.times do
      battler.setSE(delay, "player jump")
      battler.moveDelta(delay, 3, 0, -16)
      battler.moveDelta(delay + 4, 3, 0, 16)
      delay = battler.totalDuration + 1
    end
    delay = battler.totalDuration + 3
    2.times do
      battler.moveAngle(delay, 7, 5)
      battler.moveDelta(delay, 7, 0, 6)
      battler.moveAngle(delay + 7, 7, 0)
      battler.moveDelta(delay + 7, 7, 0, -6)
      delay = battler.totalDuration
    end
  end
end

#===============================================================================
# Shows the player throwing a rock at a wild Pokémon in a Safari battle.
#===============================================================================
class Battle::Scene::Animation::ThrowRock < Battle::Scene::Animation
  include Battle::Scene::Animation::BallAnimationMixin

  def initialize(sprites, viewport, battler)
    @battler = battler
    @trainer = battler.battle.pbGetOwnerFromBattlerIndex(battler.index)
    super(sprites, viewport)
  end

  def createProcesses
    batSprite = @sprites["pokemon_#{@battler.index}"]
    traSprite = @sprites["player_1"]
    ballStartX = traSprite.x
    ballStartY = traSprite.y - (traSprite.bitmap.height / 2)
    ballMidX   = 0
    ballMidY   = 122
    ballEndX   = batSprite.x
    ballEndY   = batSprite.y - (batSprite.bitmap.height / 2)
    trainer = addSprite(traSprite, PictureOrigin::BOTTOM)
    ball = addNewSprite(ballStartX, ballStartY,
                        "Graphics/Battle animations/safari_rock", PictureOrigin::CENTER)
    ball.setZ(0, batSprite.z + 1)
    if traSprite.bitmap.width >= traSprite.bitmap.height * 2
      ballStartX, ballStartY = trainerThrowingFrames(ball, trainer, traSprite)
    end
    delay = ball.totalDuration
    ball.setSE(delay, "Battle throw")
    createBallTrajectory(ball, delay, 12,
                         ballStartX, ballStartY, ballMidX, ballMidY, ballEndX, ballEndY)
    ball.setZ(9, batSprite.z + 1)
    delay = ball.totalDuration
    ball.setSE(delay, "Battle damage weak")
    ball.moveOpacity(delay + 2, 2, 0)
    ball.setVisible(delay + 4, false)
    anger = addNewSprite(ballEndX - 42, ballEndY - 36,
                         "Graphics/Battle animations/safari_anger", PictureOrigin::CENTER)
    anger.setVisible(0, false)
    anger.setZ(0, batSprite.z + 1)
    delay = ball.totalDuration + 5
    2.times do
      anger.setSE(delay, "Player jump")
      anger.setVisible(delay, true)
      anger.moveZoom(delay, 3, 130)
      anger.moveZoom(delay + 3, 3, 100)
      anger.setVisible(delay + 6, false)
      anger.setDelta(delay + 6, 96, -16)
      delay = anger.totalDuration + 3
    end
  end
end

#===============================================================================
# Safari Zone battle scene (the visuals of the battle)
#===============================================================================
class Battle::Scene
  def pbSafariStart
    @briefMessage = false
    @sprites["dataBox_0"] = SafariDataBox.new(@battle, @viewport)
    # Trigger the wild Pokémon's existing data box to draw the attention meter
    # in place of the HP bar (handled by the PokemonDataBox monkey-patch above)
    @sprites["dataBox_1"]&.refresh
    dataBoxAnim = Animation::DataBoxAppear.new(@sprites, @viewport, 0)
    loop do
      dataBoxAnim.update
      pbUpdate
      break if dataBoxAnim.animDone?
    end
    dataBoxAnim.dispose
    pbRefresh
  end

  def pbSafariRefreshAttention
    @sprites["dataBox_1"]&.refresh
  end

  def pbSafariCommandMenu(index)
    pbCommandMenuEx(index,
                    [_INTL("What will\n{1} throw?", @battle.pbPlayer.name),
                     _INTL("Ball"),
                     _INTL("Bait"),
                     _INTL("Rock"),
                     _INTL("Run")], 3)
  end

  def pbThrowBait
    @briefMessage = false
    baitAnim = Animation::ThrowBait.new(@sprites, @viewport, @battle.battlers[1])
    loop do
      baitAnim.update
      pbUpdate
      break if baitAnim.animDone?
    end
    baitAnim.dispose
  end

  def pbThrowRock
    @briefMessage = false
    rockAnim = Animation::ThrowRock.new(@sprites, @viewport, @battle.battlers[1])
    loop do
      rockAnim.update
      pbUpdate
      break if rockAnim.animDone?
    end
    rockAnim.dispose
  end

  alias __safari__pbThrowSuccess pbThrowSuccess unless method_defined?(:__safari__pbThrowSuccess)

  def pbThrowSuccess
    __safari__pbThrowSuccess
    pbWildBattleSuccess if @battle.is_a?(SafariBattle)
  end
end

#===============================================================================
# Safari Zone battle class
#===============================================================================
class SafariBattle
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
  }

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
  }

  attr_reader   :battlers
  attr_accessor :sideSizes
  attr_accessor :backdrop
  attr_accessor :backdropBase
  attr_accessor :time
  attr_accessor :environment
  attr_reader   :weather
  attr_reader   :player
  attr_accessor :party2
  attr_accessor :canRun
  attr_accessor :canLose
  attr_accessor :switchStyle
  attr_accessor :showAnims
  attr_accessor :expGain
  attr_accessor :moneyGain
  attr_accessor :rules
  attr_accessor :ballCount
  attr_reader   :attention_meter
  attr_reader   :behavior_type
  attr_reader   :safari_status
  attr_reader   :safari_status_turns

  include Battle::CatchAndStoreMixin

  def pbRandom(x); return rand(x); end

  def initialize(scene, player, party2)
    @scene              = scene
    @peer               = Battle::Peer.new
    @backdrop           = ""
    @backdropBase       = nil
    @time               = 0
    @environment        = :None
    @weather            = :None
    @decision           = 0
    @caughtPokemon      = []
    @player             = [player]
    @party2             = party2
    @sideSizes          = [1, 1]
    @battlers           = [Battle::FakeBattler.new(self, 0),
                           Battle::FakeBattler.new(self, 1)]
    @rules              = {}
    @ballCount          = 0
    @attention_meter    = 50
    @behavior_type      = :balanced
    @mechanics          = BEHAVIOR_MECHANICS[:balanced]
    @safari_status      = nil
    @safari_status_turns = 0
  end

  def disablePokeBalls=(value); end
  def sendToBoxes=(value); end
  def defaultWeather=(value); @weather = value; end
  def defaultTerrain=(value); end

  def wildBattle?;    return true;  end
  def trainerBattle?; return false; end

  def setBattleMode(mode); end

  def pbSideSize(index)
    return @sideSizes[index % 2]
  end

  def pbPlayer; return @player[0]; end
  def opponent; return nil;        end

  def pbGetOwnerFromBattlerIndex(idxBattler); return pbPlayer; end

  def pbSetSeen(battler)
    return if !battler || !@internalBattle
    if battler.is_a?(Battle::Battler)
      pbPlayer.pokedex.register(battler.displaySpecies, battler.displayGender,
                                battler.displayForm, battler.shiny?)
    else
      pbPlayer.pokedex.register(battler)
    end
  end

  def pbSetCaught(battler)
    return if !battler || !@internalBattle
    if battler.is_a?(Battle::Battler)
      pbPlayer.pokedex.register_caught(battler.displaySpecies)
    else
      pbPlayer.pokedex.register_caught(battler.species)
    end
  end

  def pbParty(idxBattler)
    return (opposes?(idxBattler)) ? @party2 : nil
  end

  def pbAllFainted?(idxBattler = 0); return false; end

  def opposes?(idxBattler1, idxBattler2 = 0)
    idxBattler1 = idxBattler1.index if idxBattler1.respond_to?("index")
    idxBattler2 = idxBattler2.index if idxBattler2.respond_to?("index")
    return (idxBattler1 & 1) != (idxBattler2 & 1)
  end

  def pbRemoveFromParty(idxBattler, idxParty); end
  def pbGainExp; end

  def pbDisplay(msg, &block)
    @scene.pbDisplayMessage(msg, &block)
  end

  def pbDisplayPaused(msg, &block)
    @scene.pbDisplayPausedMessage(msg, &block)
  end

  def pbDisplayBrief(msg)
    @scene.pbDisplayMessage(msg, true)
  end

  def pbDisplayConfirm(msg)
    return @scene.pbDisplayConfirmMessage(msg)
  end

  class BattleAbortedException < Exception; end

  def pbAbort
    raise BattleAbortedException.new("Battle aborted")
  end

  #-----------------------------------------------------------------------------
  # Behavior pattern classification from base stats
  #-----------------------------------------------------------------------------
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
  # Eating status management
  #-----------------------------------------------------------------------------
  def apply_eating_status
    duration = @mechanics[:eating_duration]
    duration = rand(3) + 1 if duration == :random
    @safari_status       = :eating
    @safari_status_turns = duration
    pbDisplayBrief(_INTL("{1} is eating!", @party2[0].name))
  end

  def clear_safari_status(show_message = true)
    @safari_status       = nil
    @safari_status_turns = 0
    pbDisplayBrief(_INTL("{1} stopped eating.", @party2[0].name)) if show_message
  end

  def tick_safari_status
    return unless @safari_status == :eating
    @safari_status_turns -= 1
    if @safari_status_turns <= 0
      clear_safari_status
    else
      pbDisplayBrief(_INTL("{1} is still eating...", @party2[0].name))
    end
  end

  #-----------------------------------------------------------------------------
  # Per-turn attention meter drift toward neutral (50); paused while eating
  #-----------------------------------------------------------------------------
  def apply_turn_decay
    return if @safari_status == :eating
    if @attention_meter > 50
      @attention_meter -= 3
    elsif @attention_meter < 50
      @attention_meter += 3
    end
    if @behavior_type == :erratic
      @attention_meter += rand(21) - 10
    end
    @attention_meter = @attention_meter.clamp(0, 100)
  end

  #-----------------------------------------------------------------------------
  # Action: throw rock — raises meter, clears eating, checks flee
  #-----------------------------------------------------------------------------
  def safari_throw_rock
    effectiveness = @mechanics[:rock_effectiveness]
    effectiveness = (rand(121) + 40) / 100.0 if effectiveness == :random

    base_gain = @mechanics[:rock_anger_gain]
    base_gain = rand(31) + 10 if base_gain == :random

    half_v = @mechanics[:attention_volatility] / 2
    meter_change = (base_gain * effectiveness).to_i + rand(half_v * 2 + 1) - half_v
    @attention_meter = (@attention_meter + meter_change).clamp(0, 100)

    clear_safari_status(true) if @safari_status == :eating
    @scene.pbSafariRefreshAttention

    pbDisplayBrief(_INTL("{1} looks angry!", @party2[0].name))
  end

  #-----------------------------------------------------------------------------
  # Action: throw bait — lowers meter, applies eating status
  #-----------------------------------------------------------------------------
  def safari_throw_bait
    effectiveness = @mechanics[:bait_effectiveness]
    effectiveness = (rand(121) + 40) / 100.0 if effectiveness == :random

    base_decrease = @mechanics[:bait_calm_gain]
    base_decrease = rand(26) + 5 if base_decrease == :random

    third_v = [@mechanics[:attention_volatility] / 3, 1].max
    meter_change = (base_decrease * effectiveness).to_i + rand(third_v * 2 + 1) - third_v
    @attention_meter = (@attention_meter - meter_change).clamp(0, 100)

    apply_eating_status
    @scene.pbSafariRefreshAttention
  end

  #-----------------------------------------------------------------------------
  # Action: throw safari ball — slightly agitates (unless eating), then catches
  #-----------------------------------------------------------------------------
  def safari_throw_ball
    attempt_catch
  end

  def attempt_catch
    pkmn = @party2[0]
    zone = get_current_zone
    zone_effects = ZONE_EFFECTS[zone]

    base_catch_rate     = pkmn.species_data.catch_rate
    modified_catch_rate = (base_catch_rate * zone_effects[:catch_modifier]).to_i.clamp(1, 255)

    echoln("[Safari Catch] #{pkmn.name} | meter=#{@attention_meter} zone=#{zone} | " \
                "catch_rate: #{base_catch_rate} x#{zone_effects[:catch_modifier]} = #{modified_catch_rate}/255")

    safariBall = GameData::Item.get(:SAFARIBALL).id
    pbThrowPokeBall(1, safariBall, modified_catch_rate, true)

    if @caughtPokemon.length > 0
      pbRecordAndStoreCaughtPokemon
      @decision = 4
    else
      # Catch failed — agitate the Pokémon, then check flee
      unless @safari_status == :eating
        @attention_meter = (@attention_meter + rand(11) + 5).clamp(0, 100)
        @scene.pbSafariRefreshAttention
      end
      check_flee(zone_effects)
    end
  end

  def check_flee(zone_effects)
    pkmn = @party2[0]

    # Eating prevents fleeing
    if @safari_status == :eating
      pbDisplayBrief(_INTL("{1} is too busy eating to flee!", pkmn.name))
      return
    end

    # Safe zones (flee_chance_modifier == 0.0) prevent fleeing
    if zone_effects[:flee_chance_modifier] == 0.0
      echoln("[Safari Flee] #{pkmn.name} | meter=#{@attention_meter} zone=#{get_current_zone} | blocked (safe zone)")
      return
    end

    base_flee     = @mechanics[:base_flee_chance]
    modified_flee = (base_flee * zone_effects[:flee_chance_modifier]).to_i
    echoln("[Safari Flee] #{pkmn.name} | meter=#{@attention_meter} zone=#{get_current_zone} | " \
                "flee_chance: #{base_flee}pct x#{zone_effects[:flee_chance_modifier]} = #{modified_flee}pct")
    if rand(100) < modified_flee
      pbSEPlay("Battle flee")
      pbDisplay(_INTL("{1} fled!", pkmn.name))
      @decision = 3
    end
  end

  #-----------------------------------------------------------------------------
  # Main battle loop
  #-----------------------------------------------------------------------------
  def pbStartBattle
    begin
      pkmn = @party2[0]
      pbSetSeen(pkmn)
      @scene.pbStartBattle(self)
      pbDisplayPaused(_INTL("Wild {1} appeared!", pkmn.name))

      @behavior_type       = determine_behavior(pkmn)
      @mechanics           = BEHAVIOR_MECHANICS[@behavior_type]
      @attention_meter     = 50
      @safari_status       = nil
      @safari_status_turns = 0

      @scene.pbSafariStart
      weather_data = GameData::BattleWeather.try_get(@weather)
      @scene.pbCommonAnimation(weather_data.animation) if weather_data

      loop do
        cmd = @scene.pbSafariCommandMenu(0)

        case cmd
        when 0   # Ball
          if pbBoxesFull?
            pbDisplay(_INTL("The boxes are full! You can't catch any more Pokémon!"))
            next
          end
          @ballCount -= 1
          @scene.pbRefresh
          safari_throw_ball

        when 1   # Bait
          pbDisplayBrief(_INTL("{1} threw some bait at the {2}!", pbPlayer.name, pkmn.name))
          @scene.pbThrowBait
          safari_throw_bait

        when 2   # Rock
          pbDisplayBrief(_INTL("{1} threw a rock at the {2}!", pbPlayer.name, pkmn.name))
          @scene.pbThrowRock
          safari_throw_rock

        when 3   # Run
          pbSEPlay("Battle flee")
          pbDisplayPaused(_INTL("You got away safely!"))
          @decision = 3

        else
          next
        end

        break if @decision > 0

        # Ball count check
        if @ballCount <= 0
          pbSEPlay("Safari Zone end")
          pbDisplay(_INTL("PA: You have no Safari Balls left! Game over!"))
          @decision = 2
          break
        end

        # Flee check for bait/rock (ball handles this internally via attempt_catch)
        if cmd != 0
          check_flee(ZONE_EFFECTS[get_current_zone])
        end

        break if @decision > 0

        # End-of-turn: tick eating status (skip on the turn bait is first applied),
        # then decay meter toward neutral
        tick_safari_status unless cmd == 1
        apply_turn_decay
        @scene.pbSafariRefreshAttention

        # Zone state message
        zone = get_current_zone
        pbDisplayBrief(_INTL("{1} {2}", pkmn.name, ZONE_EFFECTS[zone][:message]))

        weather_data = GameData::BattleWeather.try_get(@weather)
        @scene.pbCommonAnimation(weather_data.animation) if weather_data
      end

      @scene.pbEndBattle(@decision)
    rescue BattleAbortedException
      @decision = 0
      @scene.pbEndBattle(@decision)
    end
    return @decision
  end
end
