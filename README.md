orc-ruby
========

This is the beginning of an interface to ORC from Ruby.  It is nowhere
near complete and should be thought of as a starting point/toy only.

ORC (the OIL Runtime Compiler) is a library that compiles a low-level
pseudo-assembly language into native code at run time, generally using
using whatever SIMD extensions the processor has available (e.g. MMX,
SSE).  (See http://code.entropywave.com/orc/ for details.)  This
module allows Ruby programs to create ORC functions and call them on
binary data stored in Ruby strings.  This makes it possible to do
extremely high-performance number crunching in Ruby, especially on
media files.

This module provides an interface to a subset of the ORC 4.0 API.  It
also implements a more advanced class for managing ORC procedures
(i.e. "programs") and a DSL for writing ORC code.

See 'string_incr.rb' and 'string_incr2.rb' for examples.

For more details, you'll need to dig through the source code.  (This
code is nowhere near ready for documentation.)

This code requires the 'ffi' gem.






