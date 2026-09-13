# Converts every "appropriate" Data/*.rxdata file (see
# RXJson::NAMED_DATA_FILES / appropriate_data_basenames in
# rxdata_common.rb -- all Map*.rxdata plus MapInfos, CommonEvents,
# Tilesets, System, Animations, PkmnAnimations, PluginScripts) to .json,
# in one go, without you having to remember/type the exact file list.
#
# Safety: if a .json is already NEWER than its .rxdata (i.e. you hand-
# edited the json and haven't converted it back yet), that file is
# SKIPPED by default so this can't clobber your edits -- pass --force to
# convert it anyway, or run convert_all_to_rxdata.rb first to catch the
# .rxdata up.
#
# Usage:
#   ruby convert_all_to_json.rb
#   ruby convert_all_to_json.rb --force

require_relative 'rxdata_common'

force = ARGV.include?('--force')
data_dir = 'Data'

converted = 0
skipped_newer = 0
skipped_missing = 0
failed = 0

RXJson.appropriate_data_basenames(data_dir).each do |name|
  rx_path = File.join(data_dir, "#{name}.rxdata")
  js_path = File.join(data_dir, "#{name}.json")

  if !File.exist?(rx_path)
    puts "#{name}: no #{rx_path}, skipping"
    skipped_missing += 1
    next
  end

  if !force && File.exist?(js_path) && File.mtime(js_path) > File.mtime(rx_path)
    puts "#{name}: SKIPPED -- #{js_path} is newer than #{rx_path} " \
         "(would overwrite hand edits). Run convert_all_to_rxdata.rb " \
         "first to push those edits into the .rxdata, or pass --force " \
         "to discard them and regenerate the .json from the .rxdata instead."
    skipped_newer += 1
    next
  end

  print "#{name}: rxdata -> json ... "
  begin
    RXJson.rxdata_to_json(rx_path, js_path)
    puts "ok"
    converted += 1
  rescue => e
    puts "FAILED: #{e.class}: #{e.message}"
    failed += 1
  end
end

puts "---"
puts "converted=#{converted} skipped_newer=#{skipped_newer} skipped_missing=#{skipped_missing} failed=#{failed}"
exit 1 if failed > 0
