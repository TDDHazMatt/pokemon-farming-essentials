module GameData
  class BerryPlant
    NUMBER_OF_REPLANTS           = 9
    NUMBER_OF_GROWTH_STAGES      = 4
    NUMBER_OF_FULLY_GROWN_STAGES = 4
    WATERING_CANS                = [:SPRAYDUCK, :SQUIRTBOTTLE, :WAILMERPAIL, :SPRINKLOTAD]

    # Delegate all lookups to CropPlant for backward compatibility.
    def self.get(id)
      return GameData::CropPlant.get(id)
    end

    def self.get_species_form(id, _form)
      return GameData::CropPlant.get(id)
    end

    def self.try_get(id)
      return GameData::CropPlant.try_get(id)
    end

    def self.exists?(id)
      return GameData::CropPlant.exists?(id)
    end
  end
end
