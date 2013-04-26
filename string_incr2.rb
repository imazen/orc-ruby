#!/usr/bin/env ruby

# Use ORC to increment each byte in a string.  This version uses
# OrcProgram instead of the API.  Notice how much shorter and cleaner
# it is.


proc {
  path = File.dirname(__FILE__) + '/lib'
  $LOAD_PATH.unshift(path)    # So we can load the other source files
}.call()

require 'orc'

src = "abcdefghijklmn"
dest = "\x0" * src.size
puts "Before: [#{src}] -> [#{dest}]"


ofn = OrcProgram.new.code {
  source  1, "input"
  dest    1, "output"
  const   1, 1, "one"

  addssb "output", "input", "one"  
}
puts "Running!"
ofn.run src.size, input: src, output: dest

puts "After: [#{src}] -> [#{dest}]"
