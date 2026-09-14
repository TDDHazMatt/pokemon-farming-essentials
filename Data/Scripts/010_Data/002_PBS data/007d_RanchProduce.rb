module GameData
  class RanchProduce
    attr_reader :id
    attr_reader :item
    attr_reader :hours_per_unit
    attr_reader :max_stockpile

    DATA = {}
    DATA_FILENAME = "ranch_produce.dat"
    PBS_BASE_FILENAME = "ranch_produce"

    SCHEMA = {
      "SectionName"  => [:id,             "m"],
      "Item"         => [:item,           "m"],
      "HoursPerUnit" => [:hours_per_unit, "v"],
      "MaxStockpile" => [:max_stockpile,  "v"]
    }

    extend ClassMethodsSymbols
    include InstanceMethods

    def initialize(hash)
      @id             = hash[:id]
      @item           = hash[:item]
      @hours_per_unit = hash[:hours_per_unit] || 6
      @max_stockpile  = hash[:max_stockpile]  || 5
    end

    def seconds_per_unit
      return @hours_per_unit * 3600
    end
  end
end
