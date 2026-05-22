module GameData
  class ApricornTree
    attr_reader :id
    attr_reader :hours_per_stage
    attr_reader :yield
    attr_reader :pbs_file_suffix

    DATA = {}
    DATA_FILENAME = "apricorn_trees.dat"
    PBS_BASE_FILENAME = "apricorn_trees"

    SCHEMA = {
      "SectionName"   => [:id,              "m"],
      "HoursPerStage" => [:hours_per_stage, "v"],
      "Yield"         => [:yield,           "uv"]
    }

    NUMBER_OF_REPLANTS           = 20
    NUMBER_OF_GROWTH_STAGES      = 4
    NUMBER_OF_FULLY_GROWN_STAGES = 2

    extend ClassMethodsSymbols
    include InstanceMethods

    def initialize(hash)
      @id              = hash[:id]
      @hours_per_stage = hash[:hours_per_stage] || 12
      @yield           = hash[:yield]           || [2, 2]
      @yield.reverse! if @yield[1] < @yield[0]
      @pbs_file_suffix = hash[:pbs_file_suffix] || ""
    end

    def minimum_yield
      return @yield[0]
    end

    def maximum_yield
      return @yield[1]
    end
  end
end
