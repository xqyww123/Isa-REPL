functor RealPrinter(S : sig
                      type outstream
                      val output1 : outstream * Word8.word -> unit
                      val output : outstream * Word8Vector.vector -> unit
                    end) :> sig
  val bytesPerElem : int
  (* print int n outs *)
  val print : real -> S.outstream -> unit
end = struct
  structure UintPrinterIntWord = UintPrinterIntWord(S)
  val bytesPerElem = 8
  local
    fun printNormal real outs =
      let
        val {man = significand, exp = exponent} = Real.toManExp real
        val signigicand' = Real.copySign (significand * Math.pow (2.0, 53.0), 1.0) (* packed to double *)
        val shift = Math.pow (2.0, 24.0)
        val siginigicandH = signigicand' / shift / shift
        val siginigicandM = Real.rem (signigicand' / shift, shift)
        val siginigicandL = Real.rem (signigicand', shift)
        val siginigicandH' = Real.toInt IEEEReal.TO_ZERO siginigicandH mod 16 (* remove left-most bit *)
        val siginigicandM' = Real.toInt IEEEReal.TO_ZERO siginigicandM
        val siginigicandL' = Real.toInt IEEEReal.TO_ZERO siginigicandL
        val sign = if Real.signBit real then 0x8000 (* 1 << 15 *) else 0
        val exponent' = (exponent + 1023 - 1) * 16 (* << 4 *)
        val h = sign + exponent' + siginigicandH'
      in
        (* print ("sign:"^Int.toString sign^"\n");
        print ("man:"^Real.toString real^"\n");
        print ("exponent:"^Int.toString exponent^"\n");
        print ("exponent':"^Int.toString exponent'^"\n");
        print ("significandH':"^Int.toString siginigicandH'^"\n");
        print ("significandM':"^Int.toString siginigicandM'^"\n");
        print ("significandL':"^Int.toString siginigicandM'^"\n"); *)
        UintPrinterIntWord.print h 2 outs;
        UintPrinterIntWord.print siginigicandM' 3 outs;
        UintPrinterIntWord.print siginigicandL' 3 outs
      end
    fun printSubnormal real outs =
      let
        val signigicand' = Real.copySign (real * (2.0 * Math.pow (2.0, 1000.0)) * (2.0 * Math.pow(2.0, 72.0)), 1.0)
        val shift = Math.pow (2.0, 24.0)
        val siginigicandH = signigicand' / shift / shift
        val siginigicandM = Real.rem (signigicand' / shift, shift)
        val siginigicandL = Real.rem (signigicand', shift)
        val siginigicandH' = Real.toInt IEEEReal.TO_ZERO siginigicandH mod 16 (* remove left-most bit *)
        val siginigicandM' = Real.toInt IEEEReal.TO_ZERO siginigicandM
        val siginigicandL' = Real.toInt IEEEReal.TO_ZERO siginigicandL
        val sign = if Real.signBit real then 0x8000 (* 1 << 15 *) else 0
        val exponent' = 0
        val h = sign + exponent' + siginigicandH'
      in
        UintPrinterIntWord.print h 2 outs;
        UintPrinterIntWord.print siginigicandM' 3 outs;
        UintPrinterIntWord.print siginigicandL' 3 outs
      end
  in
    fun print real outs =
      if Real.isNan real then
        S.output (outs, Byte.stringToBytes "\127\248\000\000\000\000\000\000")
      else if not (Real.isFinite real) then
        if Real.signBit real then
          S.output (outs, Byte.stringToBytes "\255\240\000\000\000\000\000\000")
        else
          S.output (outs, Byte.stringToBytes "\127\240\000\000\000\000\000\000")
      else if Real.isNormal real then
        printNormal real outs
      else
        printSubnormal real outs
  end
end
