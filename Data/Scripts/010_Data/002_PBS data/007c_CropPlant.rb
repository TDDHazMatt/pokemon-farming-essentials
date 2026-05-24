module GameData
  class CropPlant
    attr_reader :id
    attr_reader :hours_per_stage
    attr_reader :drying_per_hour
    attr_reader :yield
    attr_reader :replants
    attr_reader :fully_grown_stages
    attr_reader :sprite_prefix
    attr_reader :harvest_item
    attr_reader :pbs_file_suffix

    DATA = {}
    DATA_FILENAME = "crop_plants.dat"
    PBS_BASE_FILENAME = "crop_plants"

    SCHEMA = {
      "SectionName"     => [:id,                "m"],
      "HoursPerStage"   => [:hours_per_stage,   "v"],
      "DryingPerHour"   => [:drying_per_hour,   "v"],
      "Yield"           => [:yield,             "uv"],
      "Replants"        => [:replants,          "v"],
      "FullyGrownStages"=> [:fully_grown_stages,"v"],
      "SpritePrefix"    => [:sprite_prefix,     "s"],
      "HarvestItem"     => [:harvest_item,      "m"]
    }

    NUMBER_OF_GROWTH_STAGES = 4
    WATERING_CANS = [:SPRAYDUCK, :SQUIRTBOTTLE, :WAILMERPAIL, :SPRINKLOTAD]

    extend ClassMethodsSymbols
    include InstanceMethods

    def initialize(hash)
      @id                = hash[:id]
      @hours_per_stage   = hash[:hours_per_stage]   || 3
      @drying_per_hour   = hash[:drying_per_hour]   || 0
      @yield             = hash[:yield]             || [1, 1]
      @yield.reverse! if @yield[1] < @yield[0]
      @replants          = hash[:replants]          || 9
      @fully_grown_stages= hash[:fully_grown_stages]|| 4
      @sprite_prefix     = hash[:sprite_prefix]     || "crop"
      @harvest_item      = hash[:harvest_item]      || @id
      @pbs_file_suffix   = hash[:pbs_file_suffix]   || ""
    end

    def has_moisture?
      return @drying_per_hour > 0
    end

    def minimum_yield
      return @yield[0]
    end

    def maximum_yield
      return @yield[1]
    end

    def time_per_stage
      return @hours_per_stage * 3600
    end
  end
end
