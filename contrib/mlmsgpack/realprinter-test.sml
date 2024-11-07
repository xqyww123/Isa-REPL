(*
  This test suite compares results of RealPrinter and that of PackRealBig.
  This file depends on MLton.
 *)

structure Test = struct
  structure RealPrinterIntListIO = RealPrinter(IntListIO)

  fun printIntList l = (
    print "[ ";
    List.app (fn i => print (Int.toString i ^ " ")) l;
    print "]\n")

  fun test value =
    let
      val outs1 = IntListIO.mkOutstream ()
      val outs2 = IntListIO.mkOutstream ()
    in
      RealPrinterIntListIO.print value outs1;
      IntListIO.output (outs2, PackRealBig.toBytes value);
      let
        val list1 = IntListIO.toList outs1
        val list2 = IntListIO.toList outs2
      in
        if list1 = list2 then true
      else (
        printIntList list1;
        printIntList list2;
        false)
      end
    end
  
  val tests = [
    Math.pi,
    Math.pi * ~1.0,
    Real.maxFinite,
    Real.maxFinite * ~1.0,
    Real.minPos,
    Real.minPos * ~1.0,
    Real.minNormalPos * ~1.0,
    Real.posInf,
    Real.negInf,
    0.0 / 0.0,
    ~0.0 / 0.0,
    PackRealBig.fromBytes (Word8Vector.fromList [0wx00, 0wx0F, 0wxFF, 0wxFF, 0wxFF, 0wxFF, 0wxFF, 0wxFF]),
    PackRealBig.fromBytes (Word8Vector.fromList [0wx80, 0wx0F, 0wxFF, 0wxFF, 0wxFF, 0wxFF, 0wxFF, 0wxFF]),
    0.0,
    ~0.0
  ]

  local 
    open MLton.Random
  in
    val _ = case useed () of
              NONE => ()
            | SOME s => srand s
  
    fun randomReal () =
      let 
        val word8 = Word8.fromLarge o Word.toLarge
        fun randomByte _ = word8 (rand ())
        val randomBytes = Word8Array.vector (Word8Array.tabulate (8, randomByte))
      in
        PackRealBig.fromBytes randomBytes
      end
  end

  fun doIt () =
    let
      fun run value =
        if test value then print "." else print "F" handle _ => print "E"
      fun randomTest n =
        if n = 0 then ()
        else (run (randomReal ()); randomTest (n - 1))
    in
      List.app run tests;
      randomTest 100
    end
end

fun main () = 
  let
    val realPrecision = Int.toString Real.precision
    val largeRealPrecision = Int.toString LargeReal.precision
    fun println s = print (s ^ "\n")
  in
    println ("Real.precision      = " ^ realPrecision);
    println ("LargeReal.precision = " ^ largeRealPrecision);
    Test.doIt ();
    println "\ndone."
  end

val _ = main ()
