# Converts .json files (produced by rxdata_to_json.rb, possibly hand-edited
# since) back into .rxdata files (Ruby Marshal format), OVERWRITING the
# .rxdata file next to each input .json.
#
# NOTE: this project's .gitignore excludes Data/* except Data/Scripts.rxdata
# and Data/Scripts/ -- so most .rxdata files (maps, System, CommonEvents,
# Tilesets, ...) are NOT tracked by git and an overwrite here is NOT
# recoverable via `git diff`/`git checkout`. Keep your own copy of anything
# under Data/ before overwriting it if you want a way back.
#
# Usage:
#   ruby json_to_rxdata.rb Data/Map001.json     # single file
#   ruby json_to_rxdata.rb Data                 # every *.json directly in a folder
#   ruby json_to_rxdata.rb Data/Map001.json Data/System.json
#
# See rxdata_common.rb for how this works and its known limitations
# (RXJson::KNOWN_BUILTIN_SUBCLASSES).

require_relative 'rxdata_common'

def collect_json_files(args)
  files = []
  args.each do |arg|
    if File.directory?(arg)
      files.concat(Dir.glob(File.join(arg, '*.json')))
    elsif File.file?(arg)
      files << arg
    else
      warn "Skipping (not found): #{arg}"
    end
  end
  files.sort
end

if ARGV.empty?
  puts "Usage: ruby json_to_rxdata.rb <file-or-dir> [<file-or-dir> ...]"
  puts "Converts .json files back to .rxdata next to each input file (OVERWRITES)."
  exit 1
end

collect_json_files(ARGV).each do |path|
  out_path = path.sub(/\.json\z/i, '.rxdata')
  print "#{path} -> #{out_path} ... "
  begin
    RXJson.json_to_rxdata(path, out_path)
    puts "ok"
  rescue => e
    puts "FAILED: #{e.class}: #{e.message}"
  end
end
