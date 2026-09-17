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

  # Returns the chosen command's index, or CYCLE_VIEW_COMMAND if the player
  # pressed D to cycle between normal saves / daily autosaves / milestone
  # autosaves instead of picking a command (see PokemonLoadScreen#pbStartLoadScreen).
  CYCLE_VIEW_COMMAND = -2

  def pbChoose(commands)
    @sprites["cmdwindow"].commands = commands
    loop do
      Graphics.update
      Input.update
      pbUpdate
      if Input.trigger?(Input::USE)
        return @sprites["cmdwindow"].index
      elsif Input.trigger_d?
        return CYCLE_VIEW_COMMAND
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
  # Pressing D on this screen (PokemonLoad_Scene::CYCLE_VIEW_COMMAND) cycles
  # through these in order, wrapping back to :normal. :daily and :milestone
  # browse the rotating autosave pools from 012_Overworld/014_Overworld_AutoSave.rb
  # instead of the player's own numbered save slots - a rollback option that
  # doesn't depend on the debug menu (which real players can't reach anyway,
  # and which turned out to be unsafe to load a save from mid-game).
  VIEW_ORDER = [:normal, :daily, :milestone].freeze

  def initialize(scene)
    @scene = scene
    @view = :normal
    @slot_data = load_slot_data_for_view(@view)
    @save_data = @slot_data.values.first || {}
  end

  def slot_numbers_for_view(view)
    case view
    when :daily
      return (1..AutoSaveState::DAILY_SLOT_COUNT).map { |i| AutoSaveState::DAILY_SLOT_BASE + i }
    when :milestone
      return (1..AutoSaveState::MILESTONE_SLOT_CAP).map { |i| AutoSaveState::MILESTONE_SLOT_BASE + i }
    else
      return (1..Settings::MAX_SAVE_SLOTS).to_a
    end
  end

  def load_slot_data_for_view(view)
    data = {}
    slot_numbers_for_view(view).each do |slot|
      next unless SaveData.exists?(slot)
      path = SaveData.file_path(slot)
      d = (view == :normal) ? load_save_file(path) : load_autosave_file(path)
      data[slot] = d unless d.empty?
    end
    return data
  end

  # Like load_save_file, but for the daily/milestone autosave pools: a corrupt
  # or incompatible autosave should just be silently skipped from the list,
  # never trigger load_save_file's prompt_save_deletion (which offers to wipe
  # the player's actual 1..MAX_SAVE_SLOTS saves, or exit the game entirely -
  # appropriate for a corrupt primary save at boot, not for one incidental
  # slot out of 17 rollback options).
  def load_autosave_file(file_path)
    save_data = SaveData.read_from_file(file_path)
    return save_data if SaveData.valid?(save_data)
    if File.file?(file_path + ".bak")
      backup = SaveData.read_from_file(file_path + ".bak")
      return backup if SaveData.valid?(backup)
    end
    return {}
  rescue StandardError
    return {}
  end

  def label_for_slot(slot)
    case @view
    when :daily
      return _INTL("Daily {1}", slot - AutoSaveState::DAILY_SLOT_BASE)
    when :milestone
      return _INTL("Milestone {1}", slot - AutoSaveState::MILESTONE_SLOT_BASE)
    else
      return (@slot_data.length > 1) ? _INTL("Slot {1}", slot) : _INTL("Continue")
    end
  end

  def view_display_name(view)
    case view
    when :daily     then return _INTL("Daily Autosaves")
    when :milestone then return _INTL("Milestone Autosaves")
    else                 return _INTL("Your Saves")
    end
  end

  # Advances to the next view in VIEW_ORDER and redraws the screen with it.
  def cycle_view!
    @view = VIEW_ORDER[(VIEW_ORDER.index(@view) + 1) % VIEW_ORDER.length]
    @slot_data = load_slot_data_for_view(@view)
    @save_data = @slot_data.values.first || {} if @view == :normal
    @scene.pbEndScene
    pbMessage(_INTL("Now viewing: {1}", view_display_name(@view)))
    build_and_show_screen
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
    # @slot_data holds whatever view is currently browsed (see cycle_view!) -
    # this needs the player's real numbered slots specifically, regardless of
    # whether a daily/milestone autosave view happens to be showing right now.
    normal_slot_data = (@view == :normal) ? @slot_data : load_slot_data_for_view(:normal)
    return 1 if Settings::MAX_SAVE_SLOTS == 1 || normal_slot_data.empty?
    commands = (1..Settings::MAX_SAVE_SLOTS).map do |slot|
      if normal_slot_data.key?(slot)
        _INTL("Slot {1}: {2} [Overwrite]", slot, normal_slot_data[slot][:player].name)
      else
        _INTL("Slot {1}: Empty", slot)
      end
    end
    commands << _INTL("Cancel")
    choice = pbMessage(_INTL("Choose a save slot for your new game:"), commands, commands.length)
    return -1 if choice == commands.length - 1
    slot = choice + 1
    if normal_slot_data.key?(slot)
      return -1 unless pbConfirmMessageSerious(
        _INTL("Slot {1} already has save data. It will be overwritten. Continue?", slot)
      )
    end
    return slot
  end

  # Builds the command list/panels for the current @view and shows them.
  # Called both for the initial screen and every time cycle_view! redraws
  # after a D press. Populates @commands/@cmd_slots/@show_continue and the
  # cmd_* index ivars pbStartLoadScreen's loop switches on.
  def build_and_show_screen
    commands        = []
    slot_data_array = []
    cmd_slots       = []   # slot numbers in the order their continue cards appear
    @cmd_mystery_gift = -1
    @cmd_new_game     = -1
    @cmd_options      = -1
    @cmd_language     = -1
    @cmd_debug        = -1
    @cmd_quit         = -1

    @show_continue = @slot_data.any?

    if @show_continue
      @slot_data.each do |slot, data|
        player = data[:player]
        map_id = data[:map_factory]&.map&.map_id || 0
        cmd_slots << slot
        commands  << label_for_slot(slot)
        slot_data_array << { trainer: player, stats: data[:stats], map_id: map_id }
      end
      if @view == :normal && @save_data[:player]&.mystery_gift_unlocked
        commands[@cmd_mystery_gift = commands.length] = _INTL("Mystery Gift")
        slot_data_array << nil
      end
    end

    commands[@cmd_new_game = commands.length]  = _INTL("New Game")
    slot_data_array << nil
    commands[@cmd_options = commands.length]   = _INTL("Options")
    slot_data_array << nil
    if Settings::LANGUAGES.length >= 2
      commands[@cmd_language = commands.length] = _INTL("Language")
      slot_data_array << nil
    end
    if $DEBUG
      commands[@cmd_debug = commands.length] = _INTL("Debug")
      slot_data_array << nil
    end
    commands[@cmd_quit = commands.length] = _INTL("Quit Game")
    slot_data_array << nil

    @commands  = commands
    @cmd_slots = cmd_slots

    @scene.pbStartScene(commands, slot_data_array)
    @scene.pbSetParty(slot_data_array) if @show_continue
    @scene.pbStartScene2
  end

  def pbStartLoadScreen
    build_and_show_screen

    loop do
      command = @scene.pbChoose(@commands)
      if command == PokemonLoad_Scene::CYCLE_VIEW_COMMAND
        cycle_view!
        next
      end
      pbPlayDecisionSE if command != @cmd_quit
      # Any command index less than @cmd_slots.length is a continue card.
      if @show_continue && command < @cmd_slots.length
        @scene.pbEndScene
        slot = @cmd_slots[command]
        Game.load(@slot_data[slot], slot)
        return
      end
      case command
      when @cmd_mystery_gift
        pbFadeOutIn { pbDownloadMysteryGift(@save_data[:player]) }
      when @cmd_new_game
        @scene.pbEndScene
        slot = choose_slot_for_new_game
        next if slot < 0
        $game_temp.save_slot = slot
        Game.start_new
        return
      when @cmd_options
        pbFadeOutIn do
          scene = PokemonOption_Scene.new
          screen = PokemonOptionScreen.new(scene)
          screen.pbStartScreen(true)
        end
      when @cmd_language
        @scene.pbEndScene
        $PokemonSystem.language = pbChooseLanguage
        MessageTypes.load_message_files(Settings::LANGUAGES[$PokemonSystem.language][1])
        if @show_continue
          @slot_data.each do |slot, data|
            data[:pokemon_system] = $PokemonSystem
            File.open(SaveData.file_path(slot), "wb") { |f| Marshal.dump(data, f) }
          end
        end
        $scene = pbCallTitle
        return
      when @cmd_debug
        pbFadeOutIn { pbDebugMenu(false) }
      when @cmd_quit
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
