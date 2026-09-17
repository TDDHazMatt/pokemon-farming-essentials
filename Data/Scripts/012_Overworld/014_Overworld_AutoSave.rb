#===============================================================================
# Autosaves the game on a fixed schedule, independent of the player's own
# manual save slots. SaveData.file_path(slot) (see Data/Scripts/002_Save
# data/001_SaveData.rb) resolves ANY slot number to "GameN.rxdata", not just
# the 1..Settings::MAX_SAVE_SLOTS the title screen's Continue list scans - so
# the slot ranges below live entirely outside that range and never show up
# there or collide with a player's manual save.
#
# Each primary save slot gets its OWN pair of rotating pools, namespaced by
# primary slot number (see slot_for below) so slot 2's autosaves can never
# collide with slot 1's or slot 3's:
#   - Daily:     one autosave every day at 12:01 AM (in-game time - see
#                pbGetTimeNow, 003_Overworld_Time.rb), keeping the most
#                recent 7, wrapping oldest-out.
#   - Milestone: one extra autosave every Monday 12:01 AM that the week's
#                bills end up fully paid off (see 013_Overworld_WeeklyBills.rb
#                - pbTriggerMilestoneAutosave is called from there), keeping
#                the most recent 10, wrapping oldest-out - a deeper rollback
#                net for when things are actually going well.
#
# $PokemonGlobal.autosave_state (this class) is itself part of that primary
# save's own data (see 002_Overworld_Metadata.rb), so each primary slot
# naturally keeps its own independent rotation position/schedule.
#
# Retrievable from the title screen's Load list - press D to cycle between
# normal saves / that save's daily autosaves / that save's milestone
# autosaves (see 016_UI/013_UI_Load.rb).
#===============================================================================
class AutoSaveState
  DAILY_SLOT_COUNT   = 7
  MILESTONE_SLOT_CAP = 10

  attr_reader :next_daily_due, :next_daily_index, :next_milestone_index, :milestone_count

  def initialize(primary_slot = nil)
    @primary_slot          = primary_slot || $game_temp&.save_slot || 1
    @next_daily_due        = self.class.next_1201am(pbGetTimeNow).to_i
    @next_daily_index      = 1   # cycles 1..DAILY_SLOT_COUNT
    @next_milestone_index  = 1   # cycles 1..MILESTONE_SLOT_CAP
    @milestone_count       = 0   # total milestone saves ever made (for display only)
  end

  # Saves made before this ivar existed deserialize with @primary_slot unset -
  # self-heal from the currently active slot rather than crash on nil math.
  def primary_slot
    return @primary_slot ||= ($game_temp&.save_slot || 1)
  end

  def self.next_1201am(time)
    candidate = Time.local(time.year, time.month, time.day, 0, 1, 0)
    candidate += 86400 if candidate <= time
    return candidate
  end

  # Every rollback slot number is namespaced as 1000*primary_slot + a 3-digit
  # band (1xx daily, 2xx milestone) + index, so it's derivable purely from
  # (primary_slot, index) without needing any saved state - the title screen's
  # Load list uses these same two class methods to list a given primary
  # slot's rollback saves without having to load that save first.
  def self.daily_slot_numbers(primary_slot)
    return (1..DAILY_SLOT_COUNT).map { |i| primary_slot * 1000 + 100 + i }
  end

  def self.milestone_slot_numbers(primary_slot)
    return (1..MILESTONE_SLOT_CAP).map { |i| primary_slot * 1000 + 200 + i }
  end

  def daily_due?(time = pbGetTimeNow)
    return time.to_i >= @next_daily_due
  end

  def daily_slot
    return primary_slot * 1000 + 100 + @next_daily_index
  end

  def advance_daily!
    @next_daily_due   += 86400
    @next_daily_index  = (@next_daily_index % DAILY_SLOT_COUNT) + 1
  end

  # Claims the next milestone slot (wrapping after MILESTONE_SLOT_CAP) and
  # returns it.
  def claim_milestone_slot!
    slot = primary_slot * 1000 + 200 + @next_milestone_index
    @next_milestone_index = (@next_milestone_index % MILESTONE_SLOT_CAP) + 1
    @milestone_count += 1
    return slot
  end
end

def pbAutoSaveState
  $PokemonGlobal.autosave_state ||= AutoSaveState.new
  return $PokemonGlobal.autosave_state
end

# Writes a full save snapshot straight to the given numbered slot, bypassing
# the player-facing save screen entirely (no confirmation, no "Now saving..."
# animation - see SaveData.save_to_file). Written to a temp file and renamed
# into place so an autosave interrupted mid-write can't leave a corrupt slot
# behind (SaveData.save_to_file itself has no such protection).
def pbPerformAutoSave(slot)
  path     = SaveData.file_path(slot)
  tmp_path = path + ".tmp"
  SaveData.save_to_file(tmp_path)
  File.rename(tmp_path, path)
rescue IOError, SystemCallError
  # Nothing actionable to tell the player mid-walk - the next scheduled
  # autosave (daily, at least) will simply try again.
end

def pbTriggerMilestoneAutosave
  pbPerformAutoSave(pbAutoSaveState.claim_milestone_slot!)
end

EventHandlers.add(:on_player_step_taken, :check_daily_autosave_due,
  proc {
    state = pbAutoSaveState
    if state.daily_due?
      pbPerformAutoSave(state.daily_slot)
      state.advance_daily!
    end
  }
)
