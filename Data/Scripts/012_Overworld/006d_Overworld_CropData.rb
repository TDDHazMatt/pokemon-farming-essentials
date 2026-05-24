#===============================================================================
# Unified runtime data class for all planted crops.
# Replaces BerryPlantData and ApricornTreeData.
# Stored in $PokemonGlobal.eventvars by plantable-spot events.
#===============================================================================
class CropData
  attr_accessor :crop_id
  attr_accessor :mulch_id
  attr_accessor :time_alive
  attr_accessor :time_last_updated
  attr_accessor :growth_stage
  attr_accessor :replant_count
  attr_accessor :moisture_level
  attr_accessor :yield_penalty

  def initialize
    reset
  end

  def reset(keep_mulch = false)
    @mulch_id          = nil unless keep_mulch
    @crop_id           = nil
    @time_alive        = 0
    @time_last_updated = 0
    @growth_stage      = 0
    @replant_count     = 0
    @moisture_level    = 100
    @yield_penalty     = 0
  end

  def plant(crop_id)
    reset(true)   # preserve any mulch already applied
    @crop_id           = crop_id
    @growth_stage      = 1
    @time_last_updated = pbGetTimeNow.to_i
  end

  def replant
    @time_alive     = 0
    @growth_stage   = 2
    @replant_count += 1
    @moisture_level = 100
    @yield_penalty  = 0
  end

  def planted?
    return @growth_stage > 0
  end

  def growing?
    return @growth_stage > 0 && @growth_stage < 5
  end

  def grown?
    return @growth_stage >= 5
  end

  def replanted?
    return @replant_count > 0
  end

  def moisture_stage
    return 2 if @moisture_level > 50
    return 1 if @moisture_level > 0
    return 0
  end

  def water
    @moisture_level = 100
  end

  def crop_yield
    crop_def = GameData::CropPlant.get(@crop_id)
    if crop_def.has_moisture?
      return [crop_def.maximum_yield * (5 - @yield_penalty) / 5, crop_def.minimum_yield].max
    else
      return crop_def.minimum_yield + rand(1 + crop_def.maximum_yield - crop_def.minimum_yield)
    end
  end

  def update
    return if !planted? || !@crop_id
    time_now   = pbGetTimeNow
    time_delta = time_now.to_i - @time_last_updated
    return if time_delta <= 0
    new_time_alive  = @time_alive + time_delta
    crop_def        = GameData::CropPlant.get(@crop_id)
    time_per_stage  = crop_def.time_per_stage
    drying_per_hour = crop_def.drying_per_hour
    max_replants    = crop_def.replants
    stages_growing  = GameData::CropPlant::NUMBER_OF_GROWTH_STAGES
    stages_full     = crop_def.fully_grown_stages
    case @mulch_id
    when :GROWTHMULCH
      time_per_stage  = (time_per_stage * 0.75).to_i
      drying_per_hour = (drying_per_hour * 1.5).ceil if crop_def.has_moisture?
    when :DAMPMULCH
      time_per_stage  = (time_per_stage * 1.25).to_i
      drying_per_hour = drying_per_hour / 2 if crop_def.has_moisture?
    when :GOOEYMULCH
      max_replants = (max_replants * 1.5).ceil
    when :STABLEMULCH
      stages_full = (stages_full * 1.5).ceil
    end
    done_replant = false
    loop do
      stages_this_life = stages_growing + stages_full - (replanted? ? 1 : 0)
      break if new_time_alive < stages_this_life * time_per_stage
      if @replant_count >= max_replants
        reset
        return
      end
      replant
      done_replant     = true
      new_time_alive  -= stages_this_life * time_per_stage
    end
    @time_alive        = new_time_alive
    @growth_stage      = 1 + (@time_alive / time_per_stage)
    @growth_stage     += 1 if replanted?
    @time_last_updated = time_now.to_i
    if crop_def.has_moisture?
      old_growth_hour = done_replant ? 0 : ((@time_alive - time_delta) / 3600)
      new_growth_hour = @time_alive / 3600
      if new_growth_hour > old_growth_hour
        (new_growth_hour - old_growth_hour).times do
          if @moisture_level > 0
            @moisture_level = [@moisture_level - drying_per_hour, 0].max
          else
            @yield_penalty += 1
          end
        end
      end
    end
  end
end

#===============================================================================
# Mulch overlay sprite — shows mulchspread.png whenever mulch_id is set on the
# soil, regardless of whether a plant is growing.
#===============================================================================
class CropMulchSprite
  def initialize(event, map, viewport = nil)
    @event     = event
    @map       = map
    @sprite    = IconSprite.new(0, 0, viewport)
    @sprite.ox = 16
    @sprite.oy = 24
    @has_mulch = nil   # nil forces first update_graphic call
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
    crop = @event.variable
    new_mulch = crop.is_a?(CropData) && !crop.mulch_id.nil?
    if new_mulch != @has_mulch
      @has_mulch = new_mulch
      @has_mulch ? @sprite.setBitmap("Graphics/Characters/mulchspread") : @sprite.setBitmap("")
    end
    @sprite.update
    @sprite.x      = ScreenPosHelper.pbScreenX(@event)
    @sprite.y      = ScreenPosHelper.pbScreenY(@event)
    @sprite.zoom_x = ScreenPosHelper.pbScreenZoomX(@event)
    @sprite.zoom_y = @sprite.zoom_x
    pbDayNightTint(@sprite)
  end
end

#===============================================================================
# Moisture overlay sprite for any moisture-enabled crop.
# Uses the existing berrytreedry/damp/wet graphic sheets.
#===============================================================================
class CropMoistureSprite
  def initialize(event, map, viewport = nil)
    @event          = event
    @map            = map
    @sprite         = IconSprite.new(0, 0, viewport)
    @sprite.ox      = 16
    @sprite.oy      = 24
    @moisture_stage = -1
    @disposed       = false
    update_graphic
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

  def update_graphic
    case @moisture_stage
    when -1 then @sprite.setBitmap("")
    when 0  then @sprite.setBitmap("Graphics/Characters/berrytreedry")
    when 1  then @sprite.setBitmap("Graphics/Characters/berrytreedamp")
    when 2  then @sprite.setBitmap("Graphics/Characters/berrytreewet")
    end
  end

  def update
    return if !@sprite || !@event
    new_moisture = -1
    crop = @event.variable
    if crop.is_a?(CropData) && crop.planted? && crop.crop_id
      new_moisture = crop.moisture_stage if GameData::CropPlant.get(crop.crop_id).has_moisture?
    end
    if new_moisture != @moisture_stage
      @moisture_stage = new_moisture
      update_graphic
    end
    @sprite.update
    @sprite.x      = ScreenPosHelper.pbScreenX(@event)
    @sprite.y      = ScreenPosHelper.pbScreenY(@event)
    @sprite.zoom_x = ScreenPosHelper.pbScreenZoomX(@event)
    @sprite.zoom_y = @sprite.zoom_x
    pbDayNightTint(@sprite)
  end
end

#===============================================================================
# Overworld sprite for any planted crop event.
# Graphic lookup:
#   Stage 1  -> "#{sprite_prefix}planted", fallback "croplanted"
#   Stage 2+ -> "#{sprite_prefix}_#{crop_id}", fallback "Object ball"
#   Direction: stage 1-2 = down, 3 = left, 4 = right, 5+ = up
#===============================================================================
class CropSprite
  def initialize(event, map, _viewport)
    @event     = event
    @map       = map
    @old_stage = 0
    @disposed  = false
    crop = event.variable
    return if !crop.is_a?(CropData)
    @old_stage = crop.growth_stage
    @event.character_name = ""
    crop.update if crop.planted?
    set_event_graphic(crop, true)
  end

  def dispose
    @event    = nil
    @map      = nil
    @disposed = true
  end

  def disposed?
    @disposed
  end

  def set_event_graphic(crop, full_check = false)
    return if !crop || (crop.growth_stage == @old_stage && !full_check)
    if crop.growth_stage == 0
      @event.character_name = ""
    else
      crop_def = GameData::CropPlant.get(crop.crop_id)
      prefix   = crop_def.sprite_prefix
      if crop.growth_stage == 1
        filename = "#{prefix}planted"
        filename = "croplanted" if !pbResolveBitmap("Graphics/Characters/#{filename}")
        @event.character_name = filename
        @event.turn_down
      else
        filename = "#{prefix}_#{GameData::Item.get(crop.crop_id).id}"
        if pbResolveBitmap("Graphics/Characters/#{filename}")
          @event.character_name = filename
        else
          @event.character_name = "Object ball"
        end
        case crop.growth_stage
        when 2 then @event.turn_down
        when 3 then @event.turn_left
        when 4 then @event.turn_right
        else        @event.turn_up if crop.growth_stage >= 5
        end
      end
      if @old_stage != crop.growth_stage && @old_stage > 0 &&
         crop.growth_stage <= GameData::CropPlant::NUMBER_OF_GROWTH_STAGES + 1
        spriteset = $scene.spriteset(@map.map_id)
        spriteset&.addUserAnimation(Settings::PLANT_SPARKLE_ANIMATION_ID,
                                    @event.x, @event.y, false, 1)
      end
    end
    @old_stage = crop.growth_stage
  end

  def update
    crop = @event.variable
    return if !crop.is_a?(CropData)
    crop.update if crop.planted?
    set_event_graphic(crop)
  end
end

#===============================================================================
# Hooks: update existing event-name hooks to use CropSprite/CropMoistureSprite.
# These replace the old :add_berry_plant_graphics and :add_apricorn_tree_graphics
# handlers that are removed from BerryPlants.rb and ApricornTrees.rb.
#===============================================================================
EventHandlers.add(:on_new_spriteset_map, :add_berry_plant_graphics,
  proc { |spriteset, viewport|
    map = spriteset.map
    map.events.each do |event|
      next if !event[1].name[/berryplant/i]
      spriteset.addUserSprite(CropMulchSprite.new(event[1], map, viewport))
      spriteset.addUserSprite(CropMoistureSprite.new(event[1], map, viewport))
      spriteset.addUserSprite(CropSprite.new(event[1], map, viewport))
    end
  }
)

EventHandlers.add(:on_new_spriteset_map, :add_apricorn_tree_graphics,
  proc { |spriteset, viewport|
    map = spriteset.map
    map.events.each do |event|
      next if !event[1].name[/apricorntree/i]
      spriteset.addUserSprite(CropMulchSprite.new(event[1], map, viewport))
      spriteset.addUserSprite(CropMoistureSprite.new(event[1], map, viewport))
      spriteset.addUserSprite(CropSprite.new(event[1], map, viewport))
    end
  }
)
