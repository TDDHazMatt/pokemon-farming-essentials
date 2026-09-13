# Structural validator for this project's Data/*.json map mirrors.
#
# Checks the invariants that RPG Maker XP / Essentials rely on but that JSON
# itself can't express, so a hand-edit is caught here rather than by a broken
# map in-game (or a silent no-op event).
#
# Usage:
#   ruby validate_events.rb                      # every Map*.json + CommonEvents
#   ruby validate_events.rb Data/Map009.json     # one or more specific files
#
# Exit code 1 if any ERROR was found (warnings alone exit 0).

require 'json'

REPO = File.expand_path('../../../..', __dir__)
DATA = File.join(REPO, 'Data')

# Command codes the interpreter actually implements
# (Data/Scripts/003_Game processing/004_Interpreter_Commands.rb), plus the
# structural/continuation codes it deliberately ignores.
KNOWN_CODES = [
  0, 101, 102, 103, 104, 105, 106, 108, 111, 112, 113, 115, 116, 117, 118, 119,
  121, 122, 123, 124, 125, 126, 127, 128, 129, 131, 132, 133, 134, 135, 136,
  201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 221, 222, 223, 224, 225,
  231, 232, 233, 234, 235, 236, 241, 242, 245, 246, 247, 248, 249, 250, 251,
  301, 302, 303, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322,
  331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 351, 352, 353, 354, 355,
  401, 402, 403, 404, 408, 411, 412, 413, 509, 601, 602, 603, 655
].freeze

# Essentials removed these Conditional Branch (111) types; they silently
# evaluate false.
DEAD_BRANCH_TYPES = { 4 => 'actor', 5 => 'enemy', 8 => 'item', 9 => 'weapon', 10 => 'armor' }.freeze

PAGE_IVARS = %w[
  @always_on_top @condition @direction_fix @graphic @list @move_frequency
  @move_route @move_speed @move_type @step_anime @through @trigger @walk_anime
].freeze

CONDITION_IVARS = %w[
  @self_switch_ch @self_switch_valid @switch1_id @switch1_valid @switch2_id
  @switch2_valid @variable_id @variable_valid @variable_value
].freeze

GRAPHIC_IVARS = %w[
  @blend_type @character_hue @character_name @direction @opacity @pattern @tile_id
].freeze

class Validator
  attr_reader :errors, :warnings

  def initialize
    @errors = []
    @warnings = []
  end

  def err(where, msg)  = @errors << "#{where}: #{msg}"
  def warn_(where, msg) = @warnings << "#{where}: #{msg}"

  def obj?(n, klass = nil)
    n.is_a?(Hash) && n['__type'] == 'object' && (klass.nil? || n['class'] == klass)
  end

  def validate_file(path)
    base = File.basename(path)
    begin
      root = JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      err(base, "invalid JSON - #{e.message}")
      return
    end

    if base =~ /\AMap\d+\.json\z/i
      validate_map(base, root)
    elsif base == 'CommonEvents.json'
      validate_common_events(base, root)
    else
      warn_(base, 'no structural rules for this file; only JSON syntax checked')
    end
  end

  def validate_map(base, root)
    unless obj?(root, 'RPG::Map')
      err(base, "top level must be an RPG::Map object, got #{root.is_a?(Hash) ? root['class'].inspect : root.class}")
      return
    end
    iv = root['ivars'] || {}
    w = iv['@width']
    h = iv['@height']

    tbl = iv['@data']
    if tbl.is_a?(Hash) && tbl['__type'] == 'Table'
      expect = tbl['xsize'].to_i * tbl['ysize'].to_i * tbl['zsize'].to_i
      got = tbl['data'].is_a?(Array) ? tbl['data'].length : -1
      err(base, "@data Table size mismatch: xsize*ysize*zsize=#{expect} but data has #{got} values") if expect != got
      err(base, "@data xsize (#{tbl['xsize']}) != @width (#{w})") if w && tbl['xsize'] != w
      err(base, "@data ysize (#{tbl['ysize']}) != @height (#{h})") if h && tbl['ysize'] != h
      bad = tbl['data'].is_a?(Array) ? tbl['data'].reject { |v| v.is_a?(Integer) } : []
      err(base, "@data contains #{bad.length} non-integer value(s), e.g. #{bad.first.inspect}") unless bad.empty?
    end

    events = iv['@events']
    unless events.is_a?(Hash) && events['__type'] == 'hash' && events['entries'].is_a?(Array)
      err(base, '@events must be a {"__type":"hash","entries":[...]} node')
      return
    end

    seen_ids = {}
    events['entries'].each_with_index do |pair, i|
      unless pair.is_a?(Array) && pair.length == 2
        err(base, "@events.entries[#{i}] must be a [id, event] pair")
        next
      end
      key, ev = pair
      unless obj?(ev, 'RPG::Event')
        err(base, "@events.entries[#{i}] value must be an RPG::Event object")
        next
      end
      eiv = ev['ivars'] || {}
      name = eiv['@name'].is_a?(Hash) ? eiv['@name']['text'] : eiv['@name']
      where = "#{base} event #{key} (#{name.inspect})"

      err(where, "hash key #{key.inspect} != @id #{eiv['@id'].inspect}") if key != eiv['@id']
      err(where, "duplicate event id #{key}") if seen_ids[key]
      seen_ids[key] = true

      x = eiv['@x']
      y = eiv['@y']
      if w && h && x.is_a?(Integer) && y.is_a?(Integer) && (x.negative? || y.negative? || x >= w || y >= h)
        err(where, "position (#{x},#{y}) is outside the map (#{w}x#{h})")
      end

      pages = eiv['@pages']
      unless pages.is_a?(Array) && !pages.empty?
        err(where, '@pages must be a non-empty array')
        next
      end
      pages.each_with_index { |pg, pi| validate_page("#{where} page #{pi}", pg) }
    end
  end

  def validate_common_events(base, root)
    unless root.is_a?(Array)
      err(base, 'CommonEvents.json must be an array (index = id, [0] null)')
      return
    end
    err(base, 'index 0 must be null') unless root[0].nil?
    root.each_with_index do |ce, i|
      next if ce.nil?
      unless obj?(ce, 'RPG::CommonEvent')
        err("#{base}[#{i}]", 'must be an RPG::CommonEvent object')
        next
      end
      civ = ce['ivars'] || {}
      err("#{base}[#{i}]", "@id #{civ['@id'].inspect} != array index #{i}") if civ['@id'] != i
      validate_list("#{base}[#{i}] (#{civ['@name'].inspect})", civ['@list'])
    end
  end

  def validate_page(where, pg)
    unless obj?(pg, 'RPG::Event::Page')
      err(where, 'must be an RPG::Event::Page object')
      return
    end
    iv = pg['ivars'] || {}
    missing = PAGE_IVARS - iv.keys
    err(where, "page is missing ivars: #{missing.join(', ')}") unless missing.empty?

    if (cond = iv['@condition'])
      if obj?(cond, 'RPG::Event::Page::Condition')
        cmissing = CONDITION_IVARS - (cond['ivars'] || {}).keys
        err(where, "@condition missing ivars: #{cmissing.join(', ')}") unless cmissing.empty?
        ch = cond['ivars']['@self_switch_ch']
        err(where, "@self_switch_ch must be A-D, got #{ch.inspect}") unless %w[A B C D].include?(ch)
      else
        err(where, '@condition must be an RPG::Event::Page::Condition object')
      end
    end

    if (gr = iv['@graphic'])
      if obj?(gr, 'RPG::Event::Page::Graphic')
        gmissing = GRAPHIC_IVARS - (gr['ivars'] || {}).keys
        err(where, "@graphic missing ivars: #{gmissing.join(', ')}") unless gmissing.empty?
        dir = gr['ivars']['@direction']
        err(where, "@graphic.@direction must be 2/4/6/8, got #{dir.inspect}") unless [2, 4, 6, 8].include?(dir)
      else
        err(where, '@graphic must be an RPG::Event::Page::Graphic object')
      end
    end

    trig = iv['@trigger']
    err(where, "@trigger must be 0-4, got #{trig.inspect}") unless (0..4).cover?(trig)
    mt = iv['@move_type']
    err(where, "@move_type must be 0-3, got #{mt.inspect}") unless (0..3).cover?(mt)
    ms = iv['@move_speed']
    err(where, "@move_speed must be 1-6, got #{ms.inspect}") unless (1..6).cover?(ms)
    # 1-6; 6 means continuous movement (zero delay) and is Game_Character's own
    # default, even though the RPG Maker XP editor only offers 1-5.
    mf = iv['@move_frequency']
    err(where, "@move_frequency must be 1-6, got #{mf.inspect}") unless (1..6).cover?(mf)

    validate_move_route(where, iv['@move_route'])
    validate_list(where, iv['@list'])
  end

  def validate_move_route(where, mr)
    unless obj?(mr, 'RPG::MoveRoute')
      err(where, '@move_route must be an RPG::MoveRoute object')
      return
    end
    iv = mr['ivars'] || {}
    list = iv['@list']
    unless list.is_a?(Array) && !list.empty?
      err(where, '@move_route.@list must be a non-empty array')
      return
    end
    list.each_with_index do |mc, i|
      err("#{where} move_route[#{i}]", 'must be an RPG::MoveCommand object') unless obj?(mc, 'RPG::MoveCommand')
    end
    last = list.last
    if obj?(last, 'RPG::MoveCommand') && last['ivars']['@code'] != 0
      err(where, "@move_route.@list must end with a @code:0 MoveCommand (ends with #{last['ivars']['@code']})")
    end
  end

  # The heart of it: command-list structure.
  def validate_list(where, list)
    unless list.is_a?(Array) && !list.empty?
      err(where, '@list must be a non-empty array')
      return
    end

    cmds = []
    list.each_with_index do |c, i|
      unless obj?(c, 'RPG::EventCommand')
        err("#{where} @list[#{i}]", 'must be an RPG::EventCommand object')
        return
      end
      iv = c['ivars'] || {}
      %w[@code @indent @parameters].each do |k|
        err("#{where} @list[#{i}]", "missing #{k}") unless iv.key?(k)
      end
      err("#{where} @list[#{i}]", "@parameters must be an array, got #{iv['@parameters'].class}") unless iv['@parameters'].is_a?(Array)
      cmds << [iv['@code'], iv['@indent'], iv['@parameters'], i]
    end

    # Terminator
    lcode, lindent, = cmds.last
    err(where, "@list must end with {\"@code\":0,\"@indent\":0} (ends with code #{lcode} at indent #{lindent})") if lcode != 0 || lindent != 0

    open_blocks = []   # [code, indent, index]
    cmds.each_with_index do |(code, indent, params, idx), n|
      loc = "#{where} @list[#{idx}] (code #{code})"

      warn_(loc, 'unknown command code - the interpreter will ignore it') unless KNOWN_CODES.include?(code)
      err(loc, "@indent must be a non-negative Integer, got #{indent.inspect}") unless indent.is_a?(Integer) && indent >= 0

      if n.zero?
        err(loc, "the first command must be at indent 0, got #{indent.inspect}") if indent != 0
      else
        prev_indent = cmds[n - 1][1]
        err(loc, "indent jumps from #{prev_indent} to #{indent} (may only increase by 1)") if indent.is_a?(Integer) && prev_indent.is_a?(Integer) && indent > prev_indent + 1
      end

      # Continuation codes must follow their opener
      prev_code = n.positive? ? cmds[n - 1][0] : nil
      if code == 401 && ![101, 401].include?(prev_code)
        err(loc, "401 text continuation must follow a 101 or 401 (follows #{prev_code.inspect})")
      end
      if code == 655 && ![355, 655].include?(prev_code)
        err(loc, "655 script continuation must follow a 355 or 655 (follows #{prev_code.inspect})")
      end
      if code == 509 && ![209, 509].include?(prev_code)
        err(loc, "509 move-route mirror must follow a 209 or 509 (follows #{prev_code.inspect})")
      end

      # Block opening / closing
      case code
      when 111, 102, 112
        open_blocks << [code, indent, idx]
      when 411   # Else
        err(loc, '411 Else without a matching 111 at the same indent') unless open_blocks.any? { |oc, oi, _| oc == 111 && oi == indent }
      when 412   # Branch End
        m = open_blocks.rindex { |oc, oi, _| oc == 111 && oi == indent }
        if m then open_blocks.delete_at(m)
        else err(loc, '412 Branch End without a matching 111 at the same indent')
        end
      when 402, 403
        err(loc, "#{code} must be inside a 102 Show Choices block at the same indent") unless open_blocks.any? { |oc, oi, _| oc == 102 && oi == indent }
      when 404
        m = open_blocks.rindex { |oc, oi, _| oc == 102 && oi == indent }
        if m then open_blocks.delete_at(m)
        else err(loc, '404 without a matching 102 at the same indent')
        end
      when 413
        m = open_blocks.rindex { |oc, oi, _| oc == 112 && oi == indent }
        if m then open_blocks.delete_at(m)
        else err(loc, '413 Repeat Above without a matching 112 at the same indent')
        end
      end

      # Branch body must be terminated by a code 0 at indent+1. The sole
      # exception is the first 402, which sits directly after its 102.
      if [411, 412, 404, 403, 413].include?(code) || (code == 402 && prev_code != 102)
        pcode, pindent = cmds[n - 1].first(2)
        unless pcode == 0 && pindent == indent + 1
          err(loc, "branch body before this must end with a code 0 at indent #{indent + 1} (found code #{pcode} at indent #{pindent})")
        end
      end

      # Per-command parameter sanity for the commands most often hand-written
      next unless params.is_a?(Array)
      case code
      when 101, 401, 108, 408, 355, 655, 118, 119
        err(loc, "expects 1 string parameter, got #{params.inspect[0, 80]}") unless params.length == 1 && text_like?(params[0])
      when 102
        # Normally [[choices], cancel_type]. A few events in this project carry
        # a harmless third parameter that no script reads; accept it.
        ok = [2, 3].include?(params.length) && params[0].is_a?(Array) &&
             params[0].all? { |c| text_like?(c) } && params[1].is_a?(Integer)
        err(loc, 'expects [[choice,...], cancel_type]') unless ok
        err(loc, "cancel_type must be 0-5, got #{params[1].inspect}") if params[1].is_a?(Integer) && !(0..5).cover?(params[1])
      when 111
        if params[0] == 12
          err(loc, 'script conditional expects [12, "ruby code"]') unless params.length == 2 && text_like?(params[1])
        elsif DEAD_BRANCH_TYPES.key?(params[0])
          warn_(loc, "conditional type #{params[0]} (#{DEAD_BRANCH_TYPES[params[0]]}) is disabled in Essentials and always evaluates false - use type 12 with a script")
        end
      when 123
        err(loc, 'expects ["A".."D", 0|1]') unless params.length == 2 && %w[A B C D].include?(params[0]) && [0, 1].include?(params[1])
      when 121
        err(loc, 'expects [first_id, last_id, 0|1]') unless params.length == 3 && params[0].is_a?(Integer) && params[1].is_a?(Integer) && [0, 1].include?(params[2])
      when 201
        err(loc, 'expects [0|1, map_id, x, y, direction, fade]') unless params.length == 6
        err(loc, "direction must be 0/2/4/6/8, got #{params[4].inspect}") if params.length == 6 && ![0, 2, 4, 6, 8].include?(params[4])
      when 106
        err(loc, 'expects [duration]') unless params.length == 1 && params[0].is_a?(Integer)
      when 209
        err(loc, 'expects [char, RPG::MoveRoute]') unless params.length == 2 && obj?(params[1], 'RPG::MoveRoute')
      when 241, 245, 249, 250
        err(loc, 'expects [RPG::AudioFile]') unless params.length == 1 && obj?(params[0], 'RPG::AudioFile')
      when 223, 224
        err(loc, 'expects [Tone|Color, duration]') unless params.length == 2 && params[0].is_a?(Hash) && %w[Tone Color].include?(params[0]['__type'])
      end
    end

    open_blocks.each do |code, indent, idx|
      closer = { 111 => '412', 102 => '404', 112 => '413' }[code]
      err("#{where} @list[#{idx}] (code #{code})", "block opened at indent #{indent} is never closed by a #{closer}")
    end

    # 509 mirror count must equal route length - 1
    cmds.each_with_index do |(code, indent, params, idx), n|
      next unless code == 209 && params.is_a?(Array) && obj?(params[1], 'RPG::MoveRoute')
      route = params[1]['ivars']['@list']
      next unless route.is_a?(Array)
      mirrors = 0
      k = n + 1
      while cmds[k] && cmds[k][0] == 509
        mirrors += 1
        k += 1
      end
      if mirrors != route.length - 1
        err("#{where} @list[#{idx}] (code 209)",
            "has #{mirrors} following 509 mirror command(s) but the route holds #{route.length - 1} " \
            "move command(s) plus its terminator - RPG Maker XP's editor needs one 509 per move command")
      end
    end
  end

  def text_like?(v)
    v.is_a?(String) || (v.is_a?(Hash) && %w[text_b bytes].include?(v['__type']))
  end
end

# ---------------------------------------------------------------------------

files =
  if ARGV.empty?
    Dir.glob(File.join(DATA, 'Map[0-9]*.json')).sort + [File.join(DATA, 'CommonEvents.json')].select { |f| File.exist?(f) }
  else
    ARGV.map { |a| File.exist?(a) ? a : File.join(DATA, a) }
  end

v = Validator.new
files.each do |f|
  unless File.exist?(f)
    puts "SKIP (not found): #{f}"
    next
  end
  v.validate_file(f)
end

puts "Validated #{files.length} file(s)."
unless v.warnings.empty?
  puts "\n#{v.warnings.length} warning(s):"
  v.warnings.first(40).each { |w| puts "  WARN  #{w}" }
  puts "  ... #{v.warnings.length - 40} more" if v.warnings.length > 40
end

if v.errors.empty?
  puts "\nOK - no structural errors."
  exit 0
else
  puts "\n#{v.errors.length} error(s):"
  v.errors.first(60).each { |e| puts "  ERROR #{e}" }
  puts "  ... #{v.errors.length - 60} more" if v.errors.length > 60
  exit 1
end
