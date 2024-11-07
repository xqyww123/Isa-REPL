functor RealPrinter(S : sig type outstream end) :> sig
  val bytesPerElem : int
  val print : real -> S.outstream -> unit
end = struct
  val bytesPerElem = 8
  fun print real outs = raise Fail "RealPrinter.print unimplemented."
end
