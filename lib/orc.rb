require 'set'
require 'ffi'

# Basic bindings to the API
module Orc
  extend FFI::Library

  ffi_lib 'liborc-0.4'

  enum :orcCompilerResult, [:OK,                        0x000,
                            :UNKNOWN_COMPILE,           0x100,
                            :MISSING_RULE,              0x101,
                            :UNKNOWN_PARSE,             0x200,
                            :PARSE,                     0x201,
                            :VARIABLE,                  0x202]

  attach_function :orc_init, [], :void

  attach_function :orc_program_new, [], :pointer
  attach_function :orc_program_free, [:pointer], :void

  attach_function :orc_program_set_name, [:pointer, :string], :void
  attach_function :orc_program_get_name, [:pointer], :string

  attach_function :orc_program_add_source, [:pointer, :int, :string], :int
  attach_function :orc_program_add_destination, [:pointer, :int, :string], :int
  attach_function :orc_program_add_constant,
                  [:pointer, :int, :int, :string],
                  :int
  attach_function :orc_program_add_temporary,
                  [:pointer, :int, :string],
                  :int

  attach_function :orc_program_append_str, 
                  [:pointer, :string, :string, :string, :string],
                  :void

  attach_function :orc_program_compile, [:pointer], :orcCompilerResult
  
  attach_function :orc_executor_new, [:pointer], :pointer
  attach_function :orc_executor_free, [:pointer], :void

  attach_function :orc_executor_set_n, [:pointer, :int], :void
  attach_function :orc_executor_set_array_str,
                  [:pointer, :string, :pointer],
                  :void

  attach_function :orc_executor_run, [:pointer], :void
end

# Do initialization now so callers don't need to.
Orc.orc_init()


# Class to represent a single ORC procedure (i.e. "program" in ORC
# terminology.)
class OrcProgram
  include Orc

  # Pointer registry, used for finalization.
  @@pointers = {}

  def initialize
    @fn = orc_program_new()     # The underlying OrcProgram struct
    @sources = []               # List of source names
    @dests = []                 # List of destination names

    # Setup finalization so @fn is freed on garbage collect.
    @@pointers[self.object_id] = @fn
    ObjectSpace.define_finalizer(self, self.class.method(:cleanup).to_proc)
  end

  # Explicit delete
  def delete
    self.class.cleanup(self.object_id)
  end

  # Define code in the block
  def code(&blk)
    append(OpSequence.new.append(&blk))
    return self
  end

  # Append code (in an OpSequence) to this procedure
  def append(code)
    fnCheck()

    dupCheck(@sources, code.sources, " in sources.")
    dupCheck(@dests, code.dests, " in destinations.")

    @sources += code.sources
    @dests += code.dests

    dupCheck(@sources, @dests, " in source and destination.")

    code.appendToProg(@fn)

    return self
  end

  # Execute the current procedure.  'n' is the size of the input and
  # output arrays; args is a hash mapping source and distination names
  # to Ruby strings.  All sources and destinations must be accounted
  # for.  Note that it is up to the caller to ensure that the strings
  # are large enough to contain the results of 'n' operations; this
  # class does not check that.
  def run(n, args)
    fnCheck()

    args = stringifyKeys(args)
    argsCheck(args)

    status = orc_program_compile(@fn)
    return status unless (status == :OK)

    exc = orc_executor_new(@fn)

    orc_executor_set_n(exc, n)

    for ary in @sources+@dests
      raise "Non-string value for run argument '#{ary}'" unless 
        ary.is_a?(String)
      orc_executor_set_array_str(exc, ary, args[ary])
    end

    orc_executor_run(exc)

    orc_executor_free(exc)

    return status
  end

  private 

  # Delete the underlying ORC data object associated with this object.
  # This is called by the finalizer or delete().
  def self.cleanup(id)
    ptr = @@pointers[id]
    return unless ptr

    orc_program_free(ptr)
    @@pointers.delete(id)
  end

  # Raise an exception if 'orig' and 'new' have a duplicate element.
  # Appends contents of 'in' to the message.
  def dupCheck(orig, new, extra = "")
    return unless orig.size > 0 && new.size > 0
    dups = Set[*orig] & Set[*new]
    raise "Duplicate entry '#{dups.take(1)}'#{extra}" if dups.size > 0
  end

  # Assert that @fn (the ORC library OrcProgram struct) exists.
  def fnCheck
    raise "No valid Orc object." unless @fn
  end

  # Ensure that args references exectly all of the sources and
  # destinations defined.
  def argsCheck(args)
    got = Set[*args.keys]
    wanted = Set[*@sources + @dests]

    return if got == wanted
    
    diff = (got & wanted).take(1)
    desc = got.size > wanted.size ? "Unexpected" : "Missing"

    raise "#{desc} key '#{diff}' in 'run' arguments."
  end

  # Return a copy of args with the keys converted to strings.
  def stringifyKeys(args)
    sargs = {}
    args.keys.each {|k| sargs[k.to_s] = args[k]}
    return sargs
  end

end


# Class to represent a sequence of Orc opcodes.  Also implements a DSL
# for the definition of instruction sequences.
class OpSequence
  include Orc

  attr_reader :sources, :dests

  def initialize
    @ops = []           # List of opcodes
    @sources = []       # List of source names
    @dests = []         # List of destination names
  end

  # This is the DSL interface.  The block is evaluated in this
  # instance.
  def append(&blk)
    instance_eval &blk
  end

  # Return a string containing the contents in a quasi-human-readable
  # form.
  def text
    result = ""
    actions = {
      orc_program_add_temporary:  "temp ",
      orc_program_add_source:     "source ",
      orc_program_add_destination:"dest ",
      orc_program_add_constant:   "const ",
      orc_program_append_str:     "",
    }

    for entry in @ops
      cmd  = entry[0]
      args = entry[1 .. -1]
      args.pop if args[-1] == ""

      result += actions[cmd]
      result += args.shift.to_s + ' ' if cmd == :orc_program_append_str

      result += args.join(", ")
      result += "\n"
    end

    return result
  end

  # Append the contents (i.e. instruction sequence) to the ORC program
  # at prgPtr.  Note that this is a C object.
  def appendToProg(prgPtr)
    for entry in @ops
      method = entry[0]
      args = entry[1 .. -1]
      args.unshift prgPtr

      self.send(method, *args)
    end
  end

  #
  # DSL functions
  #

  # Declare a temporary named by string "name".  "size" is the size of
  # the variable in bytes.
  def temp(size, name)
    @ops.push [:orc_program_add_temporary, size, name]
    return self
  end

  # Declare a source array named by "name" where "size" is the element
  # data size in bytes.
  def source(size, name)
    @ops.push [:orc_program_add_source, size, name]
    @sources.push name
    return self
  end

  # Declare a destination array named by "name" where "size" is the
  # element data size in bytes.
  def dest(size, name)
    @ops.push [:orc_program_add_destination, size, name]
    @dests.push name
    return self
  end

  # Declare a constant named by "name" where "size" is its size in
  # bytes and "value" (an integer) is its value
  def const(size, name, value)
    @ops.push [:orc_program_add_constant, size, name, value]
    return self
  end

  private

  # Append an opcode to the list.
  def add_op(name, a1, a2, a3)
    @ops.push [:orc_program_append_str, name, a1, a2, a3]
    return self
  end


  public

  # Define all of the opcode methods
  [ [:absb, 2], [:addb, 3], [:addssb, 3], [:addusb, 3], [:andb, 3],
    [:andnb, 3], [:avgsb, 3], [:avgub, 3], [:cmpeqb, 3], [:cmpgtsb, 2],
    [:copyb, 2], [:loadb, 2], [:loadoffb, 2], [:loadupdb, 2], [:loadupib, 2],
    [:loadpb, 2], [:ldresnearb, 2], [:ldresnearl, 2], [:ldreslinb, 2],
    [:ldreslinl, 2], [:maxsb, 3], [:maxub, 3], [:minsb, 3], [:minub, 3],
    [:mullb, 3], [:mulhsb, 3], [:mulhub, 3], [:orb, 3], [:shlb, 3],
    [:shrsb, 3], [:shrub, 3], [:signb, 2], [:storeb, 2], [:subb, 3],
    [:subssb, 3], [:subusb, 3], [:xorb, 3], [:absw, 2], [:addw, 3],
    [:addssw, 3], [:addusw, 3], [:andw, 3], [:andnw, 3], [:avgsw, 3],
    [:avguw, 3], [:cmpeqw, 3], [:cmpgtsw, 2], [:copyw, 2], [:div255w, 2],
    [:divluw, 3], [:loadw, 2], [:loadoffw, 2], [:loadpw, 2], [:maxsw, 3],
    [:maxuw, 3], [:minsw, 3], [:minuw, 3], [:mullw, 3], [:mulhsw, 3],
    [:mulhuw, 3], [:orw, 3], [:shlw, 3], [:shrsw, 3], [:shruw, 3],
    [:signw, 2], [:storew, 2], [:subw, 3], [:subssw, 3], [:subusw, 3],
    [:xorw, 3], [:absl, 2], [:addl, 3], [:addssl, 3], [:addusl, 3],
    [:andl, 3], [:andnl, 3], [:avgsl, 3], [:avgul, 3], [:cmpeql, 3],
    [:cmpgtsl, 2], [:copyl, 2], [:loadl, 2], [:loadoffl, 2], [:loadpl, 2],
    [:maxsl, 3], [:maxul, 3], [:minsl, 3], [:minul, 3], [:mulll, 3],
    [:mulhsl, 3], [:mulhul, 3], [:orl, 3], [:shll, 3], [:shrsl, 3],
    [:shrul, 3], [:signl, 2], [:storel, 2], [:subl, 3], [:subssl, 3],
    [:subusl, 3], [:xorl, 3], [:loadq, 2], [:loadpq, 2], [:storeq, 2],
    [:splatw3q, 2], [:copyq, 2], [:cmpeqq, 3], [:cmpgtsq, 2], [:andq, 3],
    [:andnq, 3], [:orq, 3], [:xorq, 3], [:addq, 3], [:subq, 3], [:shlq, 3],
    [:shrsq, 3], [:shruq, 3], [:convsbw, 2], [:convubw, 2], [:splatbw, 2],
    [:splatbl, 2], [:convswl, 2], [:convuwl, 2], [:convslq, 2],
    [:convulq, 2], [:convwb, 2], [:convhwb, 2], [:convssswb, 2],
    [:convsuswb, 2], [:convusswb, 2], [:convuuswb, 2], [:convlw, 2],
    [:convhlw, 2], [:convssslw, 2], [:convsuslw, 2], [:convusslw, 2],
    [:convuuslw, 2], [:convql, 2], [:convsssql, 2], [:convsusql, 2],
    [:convussql, 2], [:convuusql, 2], [:mulsbw, 3], [:mulubw, 3],
    [:mulswl, 3], [:muluwl, 3], [:mulslq, 3], [:mululq, 3], [:accw, 2],
    [:accl, 2], [:accsadubl, 2], [:swapw, 2], [:swapl, 2], [:swapwl, 2],
    [:swapq, 2], [:swaplq, 2], [:select0wb, 2], [:select1wb, 2],
    [:select0lw, 2], [:select1lw, 2], [:select0ql, 2], [:select1ql, 2],
    [:mergelq, 2], [:mergewl, 2], [:mergebw, 2], [:splitql, 2], [:splitlw, 2],
    [:splitwb, 2], [:addf, 3], [:subf, 3], [:mulf, 3], [:divf, 3],
    [:sqrtf, 2], [:maxf, 3], [:minf, 3], [:cmpeqf, 3], [:cmpltf, 3],
    [:cmplef, 3], [:convfl, 2], [:convlf, 2], [:addd, 3], [:subd, 3],
    [:muld, 3], [:divd, 3], [:sqrtd, 2], [:maxd, 3], [:mind, 3], [:cmpeqd, 3],
    [:cmpltd, 3], [:cmpled, 3], [:convdl, 2], [:convld, 2], [:convfd, 2], 
    [:convdf, 2] 
  ]. each do |entry|
    name, nargs = entry
    name = name.to_s

    if nargs == 2
      blk = proc {|a1, a2| add_op name, a1, a2, ""}
    else
      blk = proc {|a1, a2, a3| add_op name, a1, a2, a3}
    end

    define_method(entry[0], blk)
  end
end


