functor RealPrinter(S : sig
                      type outstream
                      val output : outstream * Word8Vector.vector -> unit
                    end) :> sig
  val bytesPerElem : int
  (* print int n outs *)
  val print : real -> S.outstream -> unit
end = struct
  val bytesPerElem = PackRealBig.bytesPerElem
  fun print real outs =
    let
      val bytes = PackRealBig.toBytes real
    in
      S.output (outs, bytes)
    end
end
