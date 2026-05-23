#===============================================================================
#
#===============================================================================
class PokemonLoadPanel < Sprite
  attr_reader :selected

  TEXT_COLOR               = Color.new(232, 232, 232)
  TEXT_SHADOW_COLOR        = Color.new(136, 136, 136)
  MALE_TEXT_COLOR          = Color.new(56, 160, 248)
  MALE_TEXT_SHADOW_COLOR   = Color.new(56, 104, 168)
  FEMALE_TEXT_COLOR        = Color.new(240, 72, 88)
  FEMALE_TEXT_SHADOW_COLOR = Color.new(160, 64, 64)

  def initialize(index, title, isContinue, trainer, stats, mapid, viewport = nil)
    super(viewport)
    @index = index
    @title = title
    @isContinue = isContinue
    @trainer = trainer
    @totalsec = stats&.play_time.to_i || 0
    @mapid = mapid
    @selected = (index == 0)
    @bgbitmap = AnimatedBitmap.new("Graphics/UI/Load/panels")
    @refreshBitmap = true
    @refreshing = false
    refresh
  end

  def dispose
    @bgbitmap.dispose
    self.bitmap.dispose
    super
  end

  def selected=(value)
    return if @selected == value
    @selected = value
    @refreshBitmap = true
    refresh
  end

  def pbRefresh
    @refreshBitmap = true
    refresh
  end

  def refresh
    return if @refreshing
    return if disposed?
    @refreshing = true
    if !self.bitmap || self.bitmap.disposed?
      self.bitmap = Bitmap.new(@bgbitmap.width, 222)
      pbSetSystemFont(self.bitmap)
    end
    if @refreshBitmap
      @refreshBitmap = false
      self.bitmap&.clear
      if @isContinue
        self.bitmap.blt(0, 0, @bgbitmap.bitmap, Rect.new(0, (@selected) ? 222 : 0, @bgbitmap.width, 222))
      else
        self.bitmap.blt(0, 0, @bgbitmap.bitmap, Rect.new(0, 444 + ((@selected) ? 46 : 0), @bgbitmap.width, 46))
      end
      textpos = []
      if @isContinue
        textpos.push([@title, 32, 16, :left, TEXT_COLOR, TEXT_SHADOW_COLOR])
        textpos.push([_INTL("Badges:"), 32, 118, :left, TEXT_COLOR, TEXT_SHADOW_COLOR])
        textpos.push([@trainer.badge_count.to_s, 206, 118, :right, TEXT_COLOR, TEXT_SHADOW_COLOR])
        textpos.push([_INTL("Pokédex:"), 32, 150, :left, TEXT_COLOR, TEXT_SHADOW_COLOR])
        textpos.push([@trainer.pokedex.seen_count.to_s, 206, 150, :right, TEXT_COLOR, TEXT_SHADOW_COLOR])
        textpos.push([_INTL("Time:"), 32, 182, :left, TEXT_COLOR, TEXT_SHADOW_COLOR])
        hour = @totalsec / 60 / 60
        min  = @totalsec / 60 % 60
        if hour > 0
          textpos.push([_INTL("{1}h {2}m", hour, min), 206, 182, :right, TEXT_COLOR, TEXT_SHADOW_COLOR])
        else
          textpos.push([_INTL("{1}m", min), 206, 182, :right, TEXT_COLOR, TEXT_SHADOW_COLOR])
        end
        if @trainer.male?
          textpos.push([@trainer.name, 112, 70, :left, MALE_TEXT_COLOR, MALE_TEXT_SHADOW_COLOR])
        elsif @trainer.female?
          textpos.push([@trainer.name, 112, 70, :left, FEMALE_TEXT_COLOR, FEMALE_TEXT_SHADOW_COLOR])
        else
          textpos.push([@trainer.name, 112, 70, :left, TEXT_COLOR, TEXT_SHADOW_COLOR])
        end
        mapname = pbGetMapNameFromId(@mapid)
        mapname.gsub!(/\\PN/, @trainer.name)
        textpos.push([mapname, 386, 16, :right, TEXT_COLOR, TEXT_SHADOW_COLOR])
      else
        textpos.push([@title, 32, 14, :left, TEXT_COLOR, TEXT_SHADOW_COLOR])
      end
      pbDrawTextPositions(self.bitmap, textpos)
    end
    @refreshing = false
  end
end

#===============================================================================
#
#===============================================================================
class PokemonLoad_Scene
  # slot_data_array: Array parallel to commands. Each entry is either nil
  # (non-continue command) or a Hash with :trainer, :stats, :map_id keys.
  def pbStartScene(commands, slot_data_array)
    @commands = commands
    @slot_data_array = slot_data_array
    @sprites = {}
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99998
    addBackgroundOrColoredPlane(@sprites, "background", "Load/bg", Color.new(248, 248, 248), @viewport)
    @panel_y = []
    y = 32
    commands.length.times do |i|
      sd = slot_data_array[i]
      is_continue = !sd.nil?
      @panel_y[i] = y
      @sprites["panel#{i}"] = PokemonLoadPanel.new(
        i, commands[i], is_continue,
        sd && sd[:trainer],
        sd && sd[:stats],
        (sd && sd[:map_id]) || 0,
        @viewport
      )
      @sprites["panel#{i}"].x = 48
      @sprites["panel#{i}"].y = y
      @sprites["panel#{i}"].pbRefresh
      y += is_continue ? 224 : 48
    end
    @sprites["cmdwindow"] = Window_CommandPokemon.new([])
    @sprites["cmdwindow"].viewport = @viewport
    @sprites["cmdwindow"].visible  = false
  end

  def pbStartScene2
    pbFadeInAndShow(@sprites) { pbUpdate }
  end

  def pbStartDeleteScene
    @sprites = {}
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99998
    addBackgroundOrColoredPlane(@sprites, "background", "Load/bg", Color.new(248, 248, 248), @viewport)
  end

  def pbUpdate
    oldi = @sprites["cmdwindow"].index rescue 0
    pbUpdateSpriteHash(@sprites)
    newi = @sprites["cmdwindow"].index rescue 0
    if oldi != newi
      @sprites["panel#{oldi}"].selected = false
      @sprites["panel#{oldi}"].pbRefresh
      @sprites["panel#{newi}"].selected = true
      @sprites["panel#{newi}"].pbRefresh
      while @sprites["panel#{newi}"].y > Graphics.height - 80
        @commands.length.times { |i| @sprites["panel#{i}"].y -= 48 }
        _scroll_party_sprites(-48)
      end
      while @sprites["panel#{newi}"].y < 32
        @commands.length.times { |i| @sprites["panel#{i}"].y += 48 }
        _scroll_party_sprites(48)
      end
    end
  end

  # slot_data_array: same array passed to pbStartScene.
  # Creates a walking sprite + party icons for each continue slot, positioned
  # relative to that slot's panel y coordinate.
  def pbSetParty(slot_data_array)
    slot_data_array.each_with_index do |sd, i|
      next if sd.nil?
      trainer = sd[:trainer]
      next if !trainer || !trainer.party
      panel_y = @panel_y[i]
      meta = GameData::PlayerMetadata.get(trainer.character_ID)
      if meta
        filename = pbGetPlayerCharset(meta.walk_charset, trainer, true)
        @sprites["player#{i}"] = TrainerWalkingCharSprite.new(filename, @viewport)
        if !@sprites["player#{i}"].bitmap
          raise _INTL("Player character {1}'s walking charset was not found (filename: \"{2}\").", trainer.character_ID, filename)
        end
        charwidth  = @sprites["player#{i}"].bitmap.width
        charheight = @sprites["player#{i}"].bitmap.height
        @sprites["player#{i}"].x = 112 - (charwidth / 8)
        @sprites["player#{i}"].y = panel_y + 80 - (charheight / 8)
        @sprites["player#{i}"].z = 99999
      end
      trainer.party.each_with_index do |pkmn, j|
        @sprites["party#{i}_#{j}"] = PokemonIconSprite.new(pkmn, @viewport)
        @sprites["party#{i}_#{j}"].setOffset(PictureOrigin::CENTER)
        @sprites["party#{i}_#{j}"].x = 334 + (66 * (j % 2))
        @sprites["party#{i}_#{j}"].y = panel_y + 80 + (50 * (j / 2))
        @sprites["party#{i}_#{j}"].z = 99999
      end
    end
  end

  def pbChoose(commands)
    @sprites["cmdwindow"].commands = commands
    loop do
      Graphics.update
      Input.update
      pbUpdate
      if Input.trigger?(Input::USE)
        return @sprites["cmdwindow"].index
      end
    end
  end

  def pbEndScene
    pbFadeOutAndHide(@sprites) { pbUpdate }
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end

  def pbCloseScene
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end

  private

  def _scroll_party_sprites(dy)
    @commands.length.times do |i|
      @sprites["player#{i}"].y += dy if @sprites["player#{i}"]
      6.times do |j|
        break unless @sprites["party#{i}_#{j}"]
        @sprites["party#{i}_#{j}"].y += dy
      end
    end
  end
end

#===============================================================================
#
#===============================================================================
class PokemonLoadScreen
  def initialize(scene)
    @scene = scene
    @slot_data = {}
    (1..Settings::MAX_SAVE_SLOTS).each do |slot|
      next unless SaveData.exists?(slot)
      data = load_save_file(SaveData.file_path(slot))
      @slot_data[slot] = data unless data.empty?
    end
    @save_data = @slot_data.values.first || {}
  end

  def load_save_file(file_path)
    save_data = SaveData.read_from_file(file_path)
    unless SaveData.valid?(save_data)
      if File.file?(file_path + ".bak")
        pbMessage(_INTL("The save file is corrupt. A backup will be loaded."))
        save_data = load_save_file(file_path + ".bak")
      else
        self.prompt_save_deletion
        return {}
      end
    end
    return save_data
  end

  def prompt_save_deletion
    pbMessage(_INTL("The save file is corrupt, or is incompatible with this game.") + "\1")
    exit unless pbConfirmMessageSerious(
      _INTL("Do you want to delete the save file and start anew?")
    )
    self.delete_save_data
    $game_system   = Game_System.new
    $PokemonSystem = PokemonSystem.new
  end

  def pbStartDeleteScreen
    @scene.pbStartDeleteScene
    @scene.pbStartScene2
    if @slot_data.any?
      if pbConfirmMessageSerious(_INTL("Delete all saved data?"))
        pbMessage(_INTL("Once data has been deleted, there is no way to recover it.") + "\1")
        if pbConfirmMessageSerious(_INTL("Delete the saved data anyway?"))
          pbMessage(_INTL("Deleting all data. Don't turn off the power.") + "\\wtnp[0]")
          self.delete_save_data
        end
      end
    else
      pbMessage(_INTL("No save file was found."))
    end
    @scene.pbEndScene
    $scene = pbCallTitle
  end

  def delete_save_data
    begin
      (1..Settings::MAX_SAVE_SLOTS).each { |slot| SaveData.delete_file(slot) }
      pbMessage(_INTL("The saved data was deleted."))
    rescue SystemCallError
      pbMessage(_INTL("All saved data could not be deleted."))
    end
  end

  # Shows a slot picker for starting a new game.
  # Auto-picks slot 1 when no saves exist. Shows all slots (with overwrite
  # warning for occupied ones) when saves are present.
  # Returns the chosen slot number, or -1 if cancelled.
  def choose_slot_for_new_game
    return 1 if Settings::MAX_SAVE_SLOTS == 1 || @slot_data.empty?
    commands = (1..Settings::MAX_SAVE_SLOTS).map do |slot|
      if @slot_data.key?(slot)
        _INTL("Slot {1}: {2} [Overwrite]", slot, @slot_data[slot][:player].name)
      else
        _INTL("Slot {1}: Empty", slot)
      end
    end
    commands << _INTL("Cancel")
    choice = pbMessage(_INTL("Choose a save slot for your new game:"), commands, commands.length)
    return -1 if choice == commands.length - 1
    slot = choice + 1
    if @slot_data.key?(slot)
      return -1 unless pbConfirmMessageSerious(
        _INTL("Slot {1} already has save data. It will be overwritten. Continue?", slot)
      )
    end
    return slot
  end

  def pbStartLoadScreen
    commands        = []
    slot_data_array = []
    cmd_slots       = []   # slot numbers in the order their continue cards appear
    cmd_mystery_gift = -1
    cmd_new_game    = -1
    cmd_options     = -1
    cmd_language    = -1
    cmd_debug       = -1
    cmd_quit        = -1

    show_continue = @slot_data.any?

    if show_continue
      @slot_data.each do |slot, data|
        player = data[:player]
        map_id = data[:map_factory]&.map&.map_id || 0
        # Single slot keeps the familiar "Continue" label; multiple slots get "Slot N".
        label = @slot_data.length > 1 ? _INTL("Slot {1}", slot) : _INTL("Continue")
        cmd_slots << slot
        commands  << label
        slot_data_array << { trainer: player, stats: data[:stats], map_id: map_id }
      end
      if @save_data[:player]&.mystery_gift_unlocked
        commands[cmd_mystery_gift = commands.length] = _INTL("Mystery Gift")
        slot_data_array << nil
      end
    end

    commands[cmd_new_game = commands.length]  = _INTL("New Game")
    slot_data_array << nil
    commands[cmd_options = commands.length]   = _INTL("Options")
    slot_data_array << nil
    if Settings::LANGUAGES.length >= 2
      commands[cmd_language = commands.length] = _INTL("Language")
      slot_data_array << nil
    end
    if $DEBUG
      commands[cmd_debug = commands.length] = _INTL("Debug")
      slot_data_array << nil
    end
    commands[cmd_quit = commands.length] = _INTL("Quit Game")
    slot_data_array << nil

    @scene.pbStartScene(commands, slot_data_array)
    @scene.pbSetParty(slot_data_array) if show_continue
    @scene.pbStartScene2

    loop do
      command = @scene.pbChoose(commands)
      pbPlayDecisionSE if command != cmd_quit
      # Any command index less than cmd_slots.length is a continue card.
      if show_continue && command < cmd_slots.length
        @scene.pbEndScene
        slot = cmd_slots[command]
        Game.load(@slot_data[slot], slot)
        return
      end
      case command
      when cmd_mystery_gift
        pbFadeOutIn { pbDownloadMysteryGift(@save_data[:player]) }
      when cmd_new_game
        @scene.pbEndScene
        slot = choose_slot_for_new_game
        next if slot < 0
        $game_temp.save_slot = slot
        Game.start_new
        return
      when cmd_options
        pbFadeOutIn do
          scene = PokemonOption_Scene.new
          screen = PokemonOptionScreen.new(scene)
          screen.pbStartScreen(true)
        end
      when cmd_language
        @scene.pbEndScene
        $PokemonSystem.language = pbChooseLanguage
        MessageTypes.load_message_files(Settings::LANGUAGES[$PokemonSystem.language][1])
        if show_continue
          @slot_data.each do |slot, data|
            data[:pokemon_system] = $PokemonSystem
            File.open(SaveData.file_path(slot), "wb") { |f| Marshal.dump(data, f) }
          end
        end
        $scene = pbCallTitle
        return
      when cmd_debug
        pbFadeOutIn { pbDebugMenu(false) }
      when cmd_quit
        pbPlayCloseMenuSE
        @scene.pbEndScene
        $scene = nil
        return
      else
        pbPlayBuzzerSE
      end
    end
  end
end
