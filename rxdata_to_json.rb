# Converts .rxdata files (Ruby Marshal format) to human/Claude-editable
# .json files, written alongside the input with the same basename.
#
# Usage:
#   ruby rxdata_to_json.rb Data/Map001.rxdata     # single file
#   ruby rxdata_to_json.rb Data                   # every *.rxdata directly in a folder
#   ruby rxdata_to_json.rb Data/Map001.rxdata Data/System.rxdata Data/CommonEvents.rxdata
#
# See rxdata_common.rb for how this works and its known limitations
# (RXJson::KNOWN_BUILTIN_SUBCLASSES).

require_relative 'rxdata_common'

def collect_rxdata_files(args)
  files = []
  args.each do |arg|
    if File.directory?(arg)
      files.concat(Dir.glob(File.join(arg, '*.rxdata')))
    elsif File.file?(arg)
      files << arg
    else
      warn "Skipping (not found): #{arg}"
    end
  end
  files.sort
end

if ARGV.empty?
  puts "Usage: ruby rxdata_to_json.rb <file-or-dir> [<file-or-dir> ...]"
  puts "Converts .rxdata files to .json next to each input file."
  exit 1
end

collect_rxdata_files(ARGV).each do |path|
  out_path = path.sub(/\.rxdata\z/i, '.json')
  print "#{path} -> #{out_path} ... "
  begin
    RXJson.rxdata_to_json(path, out_path)
    puts "ok"
  rescue => e
    puts "FAILED: #{e.class}: #{e.message}"
  end
end
