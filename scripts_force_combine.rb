require 'zlib'

# Rebuilds Scripts.rxdata from all .rb files in Data/Scripts/ without
# the "already combined" guard in scripts_combine.rb.
# Run this whenever you add new .rb script files.
# Requires Ruby installed (same Ruby used for scripts_combine.rb).

def filename_to_title(filename)
  filename = filename.bytes.pack('U*')
  title = ""
  if filename[/^[^_]*_(.+)$/]
    title = $~[1]
    title = title[0..-4] if title.end_with?(".rb")
    title = title.strip
  end
  title = "unnamed" if !title || title.empty?
  title.gsub!(/&bs;/, "\\")
  title.gsub!(/&fs;/, "/")
  title.gsub!(/&cn;/, ":")
  title.gsub!(/&as;/, "*")
  title.gsub!(/&qm;/, "?")
  title.gsub!(/&dq;/, "\"")
  title.gsub!(/&lt;/, "<")
  title.gsub!(/&gt;/, ">")
  title.gsub!(/&po;/, "|")
  return title
end

def aggregate_from_folder(path, scripts, level = 0)
  files = []
  folders = []
  Dir.foreach(path) do |f|
    next if f == '.' || f == '..'
    if File.directory?(path + "/" + f)
      folders.push(f) if !f[/^\./]
    else
      files.push(f) if f[/\.rb$/i]
    end
  end
  files.sort!
  files.each do |f|
    section_name = filename_to_title(f)
    content = File.open(path + "/" + f, "rb") { |f2| f2.read }
    scripts << [rand(999_999), section_name, Zlib::Deflate.deflate(content)]
  end
  folders.sort!
  folders.each do |f|
    section_name = filename_to_title(f)
    scripts << [rand(999_999), "==================", Zlib::Deflate.deflate("")] if level == 0
    scripts << [rand(999_999), "", Zlib::Deflate.deflate("")] if level == 1
    scripts << [rand(999_999), "[[ " + section_name + " ]]", Zlib::Deflate.deflate("")]
    aggregate_from_folder(path + "/" + f, scripts, level + 1)
  end
end

scripts = []
aggregate_from_folder("Data/Scripts", scripts)

File.open("Data/Scripts.rxdata", "wb") do |f|
  Marshal.dump(scripts, f)
end

puts "Done! Scripts.rxdata rebuilt with #{scripts.length} script sections."
