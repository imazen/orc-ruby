#!/usr/bin/env ruby

# Use ORC to increment each byte in a string.  This version uses the
# actual ORC API rather than OrcProgram.

proc {
  path = File.dirname(__FILE__) + '/lib' # Edit if necessary
  $LOAD_PATH.unshift(path)    # So we can load the other source files
}.call()

require 'orc'
include Orc

prg = orc_program_new()

orc_program_set_name prg, "MainPrg"

nn = orc_program_get_name(prg)
puts "Name set to #{nn}"

puts "Constructing program."
orc_program_add_source          prg, 1, "input"
orc_program_add_destination     prg, 1, "output"
orc_program_add_constant        prg, 1, 1, "one"

orc_program_append_str          prg, "addssb", "output", "input", "one"

puts "Compiling."

status = orc_program_compile prg
puts "Status: #{status}"

src = "abcdefghijklmn"
dest = "\x0" * src.size

puts "Before: [#{src}] -> [#{dest}]"

puts "Running."

exe = orc_executor_new prg

orc_executor_set_n exe, dest.size
orc_executor_set_array_str exe, "input", src
orc_executor_set_array_str exe, "output", dest

orc_executor_run exe

orc_executor_free exe

puts "After: [#{src}] -> [#{dest}]"

orc_program_free(prg)




