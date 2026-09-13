# Converts every "appropriate" Data/*.json file (see
# RXJson::NAMED_DATA_FILES / appropriate_data_basenames in
# rxdata_common.rb) back to .rxdata, in one go -- the mirror of
# convert_all_to_json.rb. Run this after hand-editing any of the .json
# files, before playtesting.
#
# Safety:
#   - if a .rxdata is already NEWER than its .json (e.g. the game's
#     built-in debug data editors saved directly to it, or you ran the
#     game and it re-saved something), that file is SKIPPED by default
#     so this can't clobber those changes -- pass --force to convert it
#     anyway, or run convert_all_to_json.rb first to pull that into json.
#   - after writing each .rxdata, it's immediately reloaded to confirm
#     it's structurally valid Marshal data, catching a broken hand-edit
#     (missing field, wrong type, ...) before it reaches the game.
#
# Usage:
#   ruby convert_all_to_rxdata.rb
#   ruby convert_all_to_rxdata.rb --force

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

  if !File.exist?(js_path)
    puts "#{name}: no #{js_path}, skipping"
    skipped_missing += 1
    next
  end

  if !force && File.exist?(rx_path) && File.mtime(rx_path) > File.mtime(js_path)
    puts "#{name}: SKIPPED -- #{rx_path} is newer than #{js_path} " \
         "(would overwrite changes made directly to the .rxdata). Run " \
         "convert_all_to_json.rb first to pull those into the .json, " \
         "or pass --force to discard them and regenerate the .rxdata " \
         "from the .json instead."
    skipped_newer += 1
    next
  end

  print "#{name}: json -> rxdata ... "
  begin
    RXJson.json_to_rxdata(js_path, rx_path)
    # Re-load what was just written so a broken hand-edit (missing
    # field, wrong type, unbalanced structure JSON.parse didn't catch
    # as a syntax error, ...) is caught here, not by the game.
    RXJson.load_with_bootstrap(File.binread(rx_path))
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
