# Shared helpers for rxdata <-> JSON conversion.
#
# Background: .rxdata files are Ruby's Marshal format (header "\x04\x08").
# Marshal's generic "object" record (type 'o') just needs the receiving
# class/module constant to EXIST -- it allocates the instance without
# calling #initialize and sets ivars directly via instance_variable_set.
# So for plain data classes (RPG::Map, RPG::Event, RPG::EventCommand,
# PBAnimation, ...) an empty stub class is sufficient for both loading and
# re-dumping, even though the real classes are C-extension/mkxp-builtin
# classes that don't exist in plain Ruby at all.
#
# Classes with a custom marshal protocol (type 'u', via _dump/_load) are
# the exception -- Table, Color, Tone are RGSS/mkxp-builtin classes with
# their own binary formats. We reimplement those for real (so map tile
# grids are human-inspectable), and fall back to an opaque-but-lossless
# raw-bytes wrapper for anything else with a custom dump we didn't
# special-case.

require 'json'

# ---------------------------------------------------------------------
# Known custom-marshal ("_dump"/"_load") classes from the RGSS runtime.
# These MUST live at the top level (::Table, not RXJson::Table) because
# Marshal always resolves class names from an absolute path.
# ---------------------------------------------------------------------

class Table
  attr_accessor :xsize, :ysize, :zsize, :data

  def initialize(x = 0, y = 1, z = 1)
    @xsize, @ysize, @zsize = x, y, z
    @data = Array.new(x * y * z, 0)
  end

  def _dump(_depth = -1)
    dim = (@zsize > 1 ? 3 : (@ysize > 1 ? 2 : 1))
    [dim, @xsize, @ysize, @zsize, @data.length, @data.pack('s*')].pack('LLLLLa*')
  end

  def self._load(str)
    _dim, xsize, ysize, zsize, count, rest = str.unpack('LLLLLa*')
    data = rest[0, count * 2].unpack('s*')
    t = allocate
    t.xsize, t.ysize, t.zsize, t.data = xsize, ysize, zsize, data
    t
  end
end

class Color
  attr_accessor :red, :green, :blue, :alpha

  def _dump(_depth = -1)
    [@red, @green, @blue, @alpha].pack('dddd')
  end

  def self._load(str)
    r, g, b, a = str.unpack('dddd')
    c = allocate
    c.red, c.green, c.blue, c.alpha = r, g, b, a
    c
  end
end

class Tone
  attr_accessor :red, :green, :blue, :gray

  def _dump(_depth = -1)
    [@red, @green, @blue, @gray].pack('dddd')
  end

  def self._load(str)
    r, g, b, gr = str.unpack('dddd')
    t = allocate
    t.red, t.green, t.blue, t.gray = r, g, b, gr
    t
  end
end

module RXJson
  # Lossless fallback for any other custom-dumped (type 'u') class: keep
  # the raw bytes verbatim so round-tripping is always byte-exact even for
  # formats we haven't reverse engineered.
  class OpaqueDump
    attr_accessor :raw
    def _dump(_depth = -1)
      @raw
    end
    def self._load(str)
      o = allocate
      o.raw = str
      o
    end
  end

  # Classes in this project's own scripts that subclass a builtin
  # (Marshal type 'C') instead of being plain data objects (type 'o').
  # Found by grepping Data/Scripts for "class X < Array/Hash/String"
  # (currently: BattleAnimationPlayer.rb's PBAnimation/PBAnimations).
  # Marshal never names the class in its error for this case, so unlike
  # the 'o'/'u' bootstrap below, these can't be discovered automatically
  # -- if loading a new file dies with "dump format error (user class)",
  # grep the scripts for the culprit and add it here.
  KNOWN_BUILTIN_SUBCLASSES = {
    'PBAnimation' => Array,
    'PBAnimations' => Array
  }

  # ---------------------------------------------------------------------
  # The "appropriate" data files: the .rxdata that's actually live (used
  # by some script -- checked by grepping Data/Scripts for each filename)
  # and doesn't already have a better-suited editable form. Explicitly
  # NOT included:
  #   - Scripts.rxdata: handled separately by scripts_extract.rb/
  #     scripts_combine.rb via Data/Scripts/*.rb, which is the real
  #     source; Scripts.rxdata itself is just a loader stub.
  #   - Actors/Armors/Classes/Enemies/Items/Skills/States/Troops/
  #     Weapons.rxdata: leftover default RPG Maker XP demo data, never
  #     loaded by any script in this project.
  #   - items.dat/moves.dat/species.dat/etc: compiled caches of PBS/*.txt
  #     (already plain text, the real source) that the game recompiles
  #     on its own -- editing the cache directly would just get
  #     overwritten.
  NAMED_DATA_FILES = %w[
    MapInfos CommonEvents Tilesets System Animations PkmnAnimations PluginScripts
  ]

  # Basenames (no extension) of every appropriate data file, found by
  # unioning whichever of .rxdata/.json currently exist for the Map*
  # pattern (so a file that only exists as .json right now -- e.g. a
  # brand new map that hasn't been converted back yet -- isn't dropped)
  # plus the always-included NAMED_DATA_FILES.
  def self.appropriate_data_basenames(data_dir = 'Data')
    names = Dir.glob(File.join(data_dir, 'Map[0-9]*.rxdata')).map { |f| File.basename(f, '.rxdata') }
    names += Dir.glob(File.join(data_dir, 'Map[0-9]*.json')).map { |f| File.basename(f, '.json') }
    (names + NAMED_DATA_FILES).uniq.sort
  end

  # ---------------------------------------------------------------------
  # Bootstrap: define any class/module Marshal.load asks for on the fly.
  # ---------------------------------------------------------------------

  def self.ensure_const(path)
    parts = path.split('::')
    mod = Object
    parts.each_with_index do |part, i|
      if mod.const_defined?(part, false)
        mod = mod.const_get(part)
      else
        newmod =
          if i < parts.length - 1
            Module.new
          else
            Class.new(KNOWN_BUILTIN_SUBCLASSES[part] || Object)
          end
        mod.const_set(part, newmod)
        mod = newmod
      end
    end
    mod
  end

  def self.load_with_bootstrap(bytes)
    loop do
      begin
        return Marshal.load(bytes)
      rescue ArgumentError => e
        m = e.message.match(/undefined class\/module (\S+)/)
        if !m && e.message == 'dump format error (user class)'
          raise "#{e.message} -- some class in this file subclasses " \
                "Array/Hash/String (Marshal type 'C') but isn't in " \
                "RXJson::KNOWN_BUILTIN_SUBCLASSES yet. Grep Data/Scripts " \
                "for \"< Array\", \"< Hash\" or \"< String\" to find the " \
                "culprit and add it to the hint table."
        end
        raise unless m
        ensure_const(m[1])
      rescue NameError => e
        # e.g. "uninitialized constant Foo" while resolving a nested path
        m = e.message.match(/uninitialized constant (?:.*::)?(\S+)/)
        raise unless m
        ensure_const(m[1])
      rescue NoMethodError => e
        # Custom-dumped (type 'u') class whose real _load we don't have.
        m = e.message.match(/undefined method [`']_load' for (?:class )?(\S+)/)
        raise unless m
        klass = ensure_const(m[1].sub(/^#<Class:(.*)>$/, '\1'))
        klass.define_singleton_method(:_load) { |str| RXJson::OpaqueDump._load(str) }
      rescue TypeError => e
        # Same situation (custom-dumped class missing _load), different
        # wording depending on Ruby version / whether the class predates
        # this call as a bare stub.
        m = e.message.match(/class (\S+) needs to have method '_load'/)
        raise unless m
        klass = ensure_const(m[1])
        klass.define_singleton_method(:_load) { |str| RXJson::OpaqueDump._load(str) }
      end
    end
  end

  # ---------------------------------------------------------------------
  # Generic Ruby-object <-> JSON-safe-hash conversion.
  #
  # JSON has no symbol/hash-with-nonstring-key/custom-object types, so we
  # tag everything unambiguously with a "__type" wrapper and recurse. This
  # is deliberately verbose/explicit over "clever" so it's trivial to
  # eyeball-verify and to hand-edit.
  # ---------------------------------------------------------------------

  # RGSS/mkxp writes strings with NO encoding ivar at all (a holdover from
  # Ruby 1.8), so Marshal.load tags every one of them ASCII-8BIT --
  # #valid_encoding? is trivially true for ASCII-8BIT (binary accepts any
  # byte sequence), so it can't be used to detect this on its own. In
  # practice the actual bytes are plain UTF-8 text (dialogue, names, ...),
  # so we sniff that by re-tagging and checking validity, and mark it
  # 'text_b' so from_json_safe re-tags it back to ASCII-8BIT on the way
  # out instead of leaving it UTF-8 -- Essentials' message code calls
  # String#length/#[] on this text, which count bytes under ASCII-8BIT but
  # characters under UTF-8, so keeping the original tag is required for
  # identical behavior, not just cosmetic.
  #
  # Separately: a string can already be TAGGED e.g. UTF-8 while its bytes
  # are NOT valid UTF-8 (seen in Scripts.rxdata's zlib-compressed blob --
  # Ruby source files default to UTF-8, and \xHH escapes let a literal
  # embed raw bytes that don't validate). #encode is a same-encoding no-op
  # that skips validation entirely, so trusting the existing tag let
  # invalid bytes straight through into JSON.generate, which rejects them.
  # So: validity is always checked from raw bytes regardless of the
  # incoming tag, and the original tag name travels with the payload so
  # it round-trips back exactly rather than being normalized away.
  def self.string_payload(obj)
    # Pure 7-bit-ASCII content (the overwhelming majority of strings here:
    # event names, switch ids, filenames, ...) behaves identically under
    # ASCII-8BIT/US-ASCII/UTF-8 alike, so it's always safe -- and much
    # more readable -- as a bare JSON string. from_json_safe re-tags bare
    # strings back to ASCII-8BIT on the way in, matching the RGSS norm.
    return obj.encode('UTF-8') if obj.ascii_only?
    return obj.encode('UTF-8') if obj.encoding != Encoding::ASCII_8BIT && obj.valid_encoding?

    raw = obj.b # fresh copy, same bytes, ASCII-8BIT tag
    utf8 = raw.dup.force_encoding('UTF-8')
    if utf8.valid_encoding?
      { '__type' => 'text_b', 'text' => utf8, 'enc' => obj.encoding.name }
    else
      { '__type' => 'bytes', 'b64' => [raw].pack('m0'), 'enc' => obj.encoding.name }
    end
  end

  # Ivars belonging to an object that is ALSO a builtin subclass (Marshal
  # type 'C', e.g. "class PBAnimation < Array") -- these ride alongside
  # the core Array/Hash/String payload rather than replacing it.
  def self.extra_ivars(obj, seen)
    ivars = {}
    obj.instance_variables.sort.each do |iv|
      ivars[iv.to_s] = to_json_safe(obj.instance_variable_get(iv), seen)
    end
    ivars
  end

  def self.to_json_safe(obj, seen = {})
    case obj
    when nil, true, false, Integer, Float
      return obj
    when Table
      return { '__type' => 'Table', 'xsize' => obj.xsize, 'ysize' => obj.ysize,
                'zsize' => obj.zsize, 'data' => obj.data }
    when Color
      return { '__type' => 'Color', 'red' => obj.red, 'green' => obj.green,
                'blue' => obj.blue, 'alpha' => obj.alpha }
    when Tone
      return { '__type' => 'Tone', 'red' => obj.red, 'green' => obj.green,
                'blue' => obj.blue, 'gray' => obj.gray }
    when OpaqueDump
      return { '__type' => 'opaque_raw', 'b64' => [obj.raw].pack('m0') }
    when Symbol
      return { '__type' => 'symbol', 'name' => obj.to_s }
    end

    id = obj.object_id
    raise "circular reference in #{obj.class}" if seen[id]
    seen[id] = true
    result =
      case obj
      when String
        if obj.class == String
          string_payload(obj)
        else
          { '__type' => 'string_subclass', 'class' => obj.class.name,
            'text' => string_payload(obj.to_s), 'ivars' => extra_ivars(obj, seen) }
        end
      when Array
        if obj.class == Array
          obj.map { |e| to_json_safe(e, seen) }
        else
          { '__type' => 'array_subclass', 'class' => obj.class.name,
            'elements' => obj.map { |e| to_json_safe(e, seen) },
            'ivars' => extra_ivars(obj, seen) }
        end
      when Hash
        if obj.class == Hash
          { '__type' => 'hash',
            'entries' => obj.map { |k, v| [to_json_safe(k, seen), to_json_safe(v, seen)] } }
        else
          { '__type' => 'hash_subclass', 'class' => obj.class.name,
            'entries' => obj.map { |k, v| [to_json_safe(k, seen), to_json_safe(v, seen)] },
            'ivars' => extra_ivars(obj, seen) }
        end
      else
        { '__type' => 'object', 'class' => obj.class.name, 'ivars' => extra_ivars(obj, seen) }
      end
    seen.delete(id)
    result
  end

  def self.from_json_safe(node)
    case node
    when nil, true, false, Integer, Float
      node
    when String
      # Mirrors string_payload's ascii_only? fast path: a bare string is
      # always either pure ASCII (re-tag ASCII-8BIT, the RGSS norm) or
      # came from a genuinely non-ASCII-8BIT-tagged source that validated
      # in its own encoding (leave as the UTF-8 JSON.parse gave us, which
      # matches -- see string_payload's second return).
      node.ascii_only? ? node.b : node
    when Array
      node.map { |e| from_json_safe(e) }
    when Hash
      case node['__type']
      when 'symbol'
        node['name'].to_sym
      when 'bytes'
        node['b64'].unpack1('m0').force_encoding(node['enc'] || Encoding::ASCII_8BIT)
      when 'text_b'
        node['text'].b.force_encoding(node['enc'] || Encoding::ASCII_8BIT)
      when 'hash'
        h = {}
        node['entries'].each { |k, v| h[from_json_safe(k)] = from_json_safe(v) }
        h
      when 'Table'
        t = Table.allocate
        t.xsize, t.ysize, t.zsize = node['xsize'], node['ysize'], node['zsize']
        t.data = node['data']
        t
      when 'Color'
        c = Color.allocate
        c.red, c.green, c.blue, c.alpha = node['red'], node['green'], node['blue'], node['alpha']
        c
      when 'Tone'
        t = Tone.allocate
        t.red, t.green, t.blue, t.gray = node['red'], node['green'], node['blue'], node['gray']
        t
      when 'opaque_raw'
        OpaqueDump._load(node['b64'].unpack1('m0'))
      when 'object'
        klass = ensure_const(node['class'])
        obj = klass.allocate
        node['ivars'].each { |k, v| obj.instance_variable_set(k.to_sym, from_json_safe(v)) }
        obj
      when 'array_subclass'
        klass = ensure_const(node['class'])
        obj = klass.allocate
        obj.replace(node['elements'].map { |e| from_json_safe(e) })
        node['ivars'].each { |k, v| obj.instance_variable_set(k.to_sym, from_json_safe(v)) }
        obj
      when 'hash_subclass'
        klass = ensure_const(node['class'])
        obj = klass.allocate
        node['entries'].each { |k, v| obj[from_json_safe(k)] = from_json_safe(v) }
        node['ivars'].each { |k, v| obj.instance_variable_set(k.to_sym, from_json_safe(v)) }
        obj
      when 'string_subclass'
        klass = ensure_const(node['class'])
        obj = klass.allocate
        obj.replace(from_json_safe(node['text']))
        node['ivars'].each { |k, v| obj.instance_variable_set(k.to_sym, from_json_safe(v)) }
        obj
      else
        raise "unknown __type #{node['__type'].inspect}"
      end
    else
      raise "unhandled JSON node #{node.class}"
    end
  end

  def self.rxdata_to_json(in_path, out_path)
    bytes = File.open(in_path, 'rb') { |f| f.read }
    obj = load_with_bootstrap(bytes)
    safe = to_json_safe(obj)
    File.write(out_path, pretty_print(safe))
  end

  def self.json_to_rxdata(in_path, out_path)
    safe = JSON.parse(File.read(in_path))
    obj = from_json_safe(safe)
    # Dump to memory first: a bad hand-edit can build a JSON-valid object
    # graph that still fails inside Marshal.dump (e.g. Table#_dump's
    # pack('s*') choking on a non-numeric tile value). If we streamed
    # straight into out_path, opening it in 'wb' truncates the existing
    # (often git-ignored, unrecoverable) .rxdata before the error is even
    # raised. Writing the already-complete bytes can still fail (disk
    # full, permissions), but it never truncates out_path first.
    bytes = Marshal.dump(obj)
    File.binwrite(out_path, bytes)
  end

  # ---------------------------------------------------------------------
  # Custom pretty printer. Identical *data* to JSON.pretty_generate (any
  # standard JSON parser reads it the same way) but wraps long runs of
  # plain numbers (typically Table tile data) onto packed lines instead
  # of one-value-per-line -- a 20x15x3 map is ~900 lines shorter this way,
  # and a Table's data is wrapped one map row (xsize values) per line so
  # the JSON visually mirrors the tile grid. Arrays containing
  # objects/hashes/strings still get one entry per line, since that's
  # what's actually being read/edited (event commands etc).
  # ---------------------------------------------------------------------

  SCALAR_WRAP_WIDTH = 100

  def self.scalar_array?(arr)
    !arr.empty? && arr.all? { |e| e.is_a?(Numeric) || e == true || e == false || e.nil? }
  end

  def self.pretty_print(node, indent = 0)
    pad = '  ' * indent
    child_pad = '  ' * (indent + 1)
    case node
    when Hash
      return '{}' if node.empty?
      if node['__type'] == 'Table' && node['data'].is_a?(Array)
        lines = node.map do |k, v|
          rendered = (k == 'data') ? wrap_by_row(v, node['xsize'], child_pad, pad) : pretty_print(v, indent + 1)
          "#{child_pad}#{JSON.generate(k.to_s)}: #{rendered}"
        end
        return "{\n#{lines.join(",\n")}\n#{pad}}"
      end
      lines = node.map do |k, v|
        "#{child_pad}#{JSON.generate(k.to_s)}: #{pretty_print(v, indent + 1)}"
      end
      "{\n#{lines.join(",\n")}\n#{pad}}"
    when Array
      return '[]' if node.empty?
      if scalar_array?(node)
        wrap_scalar_array(node, child_pad, pad)
      else
        lines = node.map { |e| "#{child_pad}#{pretty_print(e, indent + 1)}" }
        "[\n#{lines.join(",\n")}\n#{pad}]"
      end
    else
      JSON.generate(node)
    end
  end

  # One line per map row (xsize values), so the JSON visually mirrors the
  # tile grid -- z-layers concatenate straight through since Table's flat
  # @data is x-fastest, then y, then z (index = x + y*xsize + z*xsize*ysize).
  def self.wrap_by_row(data, xsize, child_pad, pad)
    return wrap_scalar_array(data, child_pad, pad) if !xsize.is_a?(Integer) || xsize <= 0
    tokens = data.map { |e| JSON.generate(e) }
    lines = tokens.each_slice(xsize).map { |row| child_pad + row.join(', ') }
    "[\n#{lines.join(",\n")}\n#{pad}]"
  end

  def self.wrap_scalar_array(node, child_pad, pad)
    tokens = node.map { |e| JSON.generate(e) }
    lines = []
    cur = []
    cur_len = child_pad.length
    tokens.each do |tok|
      addition = cur.empty? ? tok.length : tok.length + 2
      if !cur.empty? && cur_len + addition > SCALAR_WRAP_WIDTH
        lines << cur
        cur = []
        cur_len = child_pad.length
      end
      cur << tok
      cur_len += addition
    end
    lines << cur unless cur.empty?
    body = lines.map { |line| child_pad + line.join(', ') }.join(",\n")
    "[\n#{body}\n#{pad}]"
  end
end
