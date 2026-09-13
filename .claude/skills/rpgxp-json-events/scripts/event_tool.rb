# Inspect this project's Data/*.json without reading whole 600KB map files
# into context.
#
# Usage:
#   ruby event_tool.rb maps                    # list every map id + name + size
#   ruby event_tool.rb list Map009             # events in a map
#   ruby event_tool.rb show Map009 5 [page]    # one event page, command by command
#   ruby event_tool.rb grep "Prof. Oak"        # find text/script across all maps
#   ruby event_tool.rb switches [filter]       # named switches from System.json
#   ruby event_tool.rb variables [filter]      # named variables from System.json
#   ruby event_tool.rb commons                 # common events
#   ruby event_tool.rb find-free-id Map009     # next unused event id in a map

require 'json'

REPO = File.expand_path('../../../..', __dir__)
DATA = File.join(REPO, 'Data')

def load_json(name)
  name = "#{name}.json" unless name.end_with?('.json')
  path = File.exist?(name) ? name : File.join(DATA, name)
  abort "Not found: #{path}" unless File.exist?(path)
  JSON.parse(File.read(path))
end

# Strings may be plain or wrapped as {"__type":"text_b",...}
def txt(v)
  return v['text'] if v.is_a?(Hash) && v['__type'] == 'text_b'
  return "<binary>" if v.is_a?(Hash) && v['__type'] == 'bytes'
  v
end

def events_of(map)
  (map['ivars']['@events']['entries'] || []).sort_by { |k, _| k }
end

def brief(params, limit = 200)
  s = JSON.generate(params)
  s.length > limit ? "#{s[0, limit]}..." : s
end

cmd = ARGV[0]

case cmd
when 'maps'
  infos = load_json('MapInfos')
  rows = infos['entries'].map do |id, mi|
    iv = mi['ivars']
    [id, txt(iv['@name']), iv['@parent_id'], iv['@order']]
  end
  rows.sort_by! { |r| r[0] }
  rows.each do |id, name, parent, order|
    file = File.join(DATA, format('Map%03d.json', id))
    size = File.exist?(file) ? "#{(File.size(file) / 1024.0).round}KB" : 'MISSING'
    printf("Map%03d  %-38s parent=%-3d order=%-3d %s\n", id, name.to_s[0, 38], parent, order, size)
  end

when 'list'
  abort 'usage: event_tool.rb list MapXXX' unless ARGV[1]
  map = load_json(ARGV[1])
  iv = map['ivars']
  puts "#{ARGV[1]}  #{iv['@width']}x#{iv['@height']}  tileset=#{iv['@tileset_id']}  bgm=#{txt(iv['@bgm']['ivars']['@name']).inspect}"
  puts "#{events_of(map).length} event(s):"
  events_of(map).each do |id, ev|
    e = ev['ivars']
    pages = e['@pages']
    cmds = pages.sum { |p| p['ivars']['@list'].length }
    trig = pages.map { |p| p['ivars']['@trigger'] }.uniq.join(',')
    gfx = pages.map { |p| txt(p['ivars']['@graphic']['ivars']['@character_name']) }.reject { |g| g.to_s.empty? }.uniq.first
    printf("  id=%-4d (%2d,%2d) pages=%-2d cmds=%-4d trigger=%-5s %-28s %s\n",
           id, e['@x'], e['@y'], pages.length, cmds, trig,
           txt(e['@name']).to_s[0, 28], gfx ? "[#{gfx}]" : '')
  end

when 'show'
  abort 'usage: event_tool.rb show MapXXX <event_id> [page]' unless ARGV[2]
  map = load_json(ARGV[1])
  eid = ARGV[2].to_i
  pair = events_of(map).find { |k, _| k == eid }
  abort "No event #{eid} in #{ARGV[1]}" unless pair
  ev = pair[1]['ivars']
  puts "EVENT #{eid} #{txt(ev['@name']).inspect} at (#{ev['@x']},#{ev['@y']})  pages=#{ev['@pages'].length}"

  pages = ARGV[3] ? [ARGV[3].to_i] : (0...ev['@pages'].length).to_a
  pages.each do |pi|
    pg = ev['@pages'][pi]
    abort "No page #{pi}" unless pg
    p_iv = pg['ivars']
    c = p_iv['@condition']['ivars']
    g = p_iv['@graphic']['ivars']
    conds = []
    conds << "switch1=#{c['@switch1_id']}" if c['@switch1_valid']
    conds << "switch2=#{c['@switch2_id']}" if c['@switch2_valid']
    conds << "var#{c['@variable_id']}>=#{c['@variable_value']}" if c['@variable_valid']
    conds << "self_switch=#{c['@self_switch_ch']}" if c['@self_switch_valid']
    trig_name = %w[Action PlayerTouch EventTouch Autorun Parallel][p_iv['@trigger']]

    puts "\n--- PAGE #{pi} ---"
    puts "  trigger=#{p_iv['@trigger']} (#{trig_name})  move_type=#{p_iv['@move_type']}  through=#{p_iv['@through']}"
    puts "  conditions: #{conds.empty? ? '(none - always active)' : conds.join(' AND ')}"
    puts "  graphic: #{txt(g['@character_name']).to_s.empty? ? '(invisible)' : txt(g['@character_name'])} dir=#{g['@direction']} tile_id=#{g['@tile_id']}"
    puts "  commands:"
    p_iv['@list'].each_with_index do |cc, i|
      ci = cc['ivars']
      params = ci['@parameters']
      # Show text params unwrapped for readability
      shown =
        if [101, 401, 108, 408, 355, 655, 118, 119].include?(ci['@code']) && params.length == 1
          txt(params[0]).inspect
        else
          brief(params)
        end
      printf("  %4d %s code=%-4d %s\n", i, '  ' * ci['@indent'], ci['@code'], shown)
    end
  end

when 'grep'
  abort 'usage: event_tool.rb grep "text"' unless ARGV[1]
  needle = ARGV[1]
  re = Regexp.new(Regexp.escape(needle), Regexp::IGNORECASE)
  hits = 0
  Dir.glob(File.join(DATA, 'Map[0-9]*.json')).sort.each do |f|
    map = JSON.parse(File.read(f))
    events_of(map).each do |id, ev|
      ev['ivars']['@pages'].each_with_index do |pg, pi|
        pg['ivars']['@list'].each_with_index do |cc, i|
          ci = cc['ivars']
          flat = ci['@parameters'].map { |p| txt(p) }.select { |p| p.is_a?(String) }.join(' ')
          next unless flat =~ re
          hits += 1
          printf("%-14s event %-4d page %d [%3d] code=%-4d %s\n",
                 File.basename(f, '.json'), id, pi, i, ci['@code'], flat[0, 90].inspect)
        end
      end
    end
  end
  puts "(no matches)" if hits.zero?

when 'switches', 'variables'
  sys = load_json('System')['ivars']
  key = cmd == 'switches' ? '@switches' : '@variables'
  filter = ARGV[1] ? Regexp.new(Regexp.escape(ARGV[1]), Regexp::IGNORECASE) : nil
  sys[key].each_with_index do |n, i|
    name = txt(n)
    next if name.nil? || name.to_s.empty?
    next if filter && name !~ filter
    marker = name.to_s.start_with?('s:') ? '  [script switch]' : ''
    printf("%4d: %s%s\n", i, name, marker)
  end

when 'commons'
  load_json('CommonEvents').each_with_index do |ce, i|
    next if ce.nil?
    iv = ce['ivars']
    trig = %w[None Autorun Parallel][iv['@trigger']]
    printf("%3d: %-34s trigger=%-9s switch=%-4d cmds=%d\n",
           i, txt(iv['@name']).to_s[0, 34], trig, iv['@switch_id'], iv['@list'].length)
  end

when 'find-free-id'
  abort 'usage: event_tool.rb find-free-id MapXXX' unless ARGV[1]
  map = load_json(ARGV[1])
  used = events_of(map).map(&:first)
  free = (1..(used.max.to_i + 2)).find { |i| !used.include?(i) }
  puts "used ids: #{used.join(', ')}"
  puts "next free id: #{free}"

else
  puts File.read(__FILE__).lines[0...14].map { |l| l.sub(/^# ?/, '') }.join
end
