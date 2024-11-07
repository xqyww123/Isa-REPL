signature I = sig
  eqtype int

  val toLarge   : int -> LargeInt.int
  val fromLarge : LargeInt.int -> int
  val fromInt : Int.int -> int
  
  val + : int * int -> int
  val * : int * int -> int
  val div : int * int -> int
end

signature W = sig
  eqtype word
  
  val wordSize : int
  
  val toLarge      : word -> LargeWord.word
  val fromLarge     : LargeWord.word -> word
  val toLargeInt  : word -> LargeInt.int
  val toLargeIntX : word -> LargeInt.int
  val toInt  : word -> int
  val toIntX : word -> int
  val fromInt : int -> word
  
  val andb : word * word -> word
  val orb  : word * word -> word
  val notb : word -> word
  val << : word * Word.word -> word
  val >> : word * Word.word -> word
  
  val + : word * word -> word
  val * : word * word -> word
end

(* 
  requirement:
    Int.precision >= 28 andalso Word.wordSize >= 16
*)
val true = case Int.precision of
             SOME p => p >= 28
           | NONE => true
           andalso Word.wordSize >= 16

(*
  UintScanner scans unsigned integer from Word8Vector and construct I.int value
    I: result integer type
*)
functor UintScanner(I : I) :> sig
  val scan : Word8Vector.vector -> I.int
end = struct
  (* with the expectation that the compiler will optimize this idiom *)
  val fromWord8ToI = I.fromLarge o Word8.toLargeInt
  fun scan bytes =
    let
      fun f (byte, int) = I.+ (I.* (int, I.fromInt 256), fromWord8ToI byte)
    in
      Word8Vector.foldl f (I.fromInt 0) bytes
    end
end

(*
   IntScanner scans signed integer from Word8Vector and construct I.int value
     I: result integer type
     W: word type used for intermediate working memory
     toInt: a function that converts a W value into I
*)
functor IntScanner(structure I : I;
                   structure W : W;
                   val toInt : W.word -> I.int) :> sig
  val scan : Word8Vector.vector -> I.int
end = struct
  (* with the expectation that the compiler will optimize this idiom *)
  val fromWord8ToW = W.fromLarge o Word8.toLarge
  val word8 = Word8.fromLarge o Word.toLarge
  fun scan bytes =
    let
      val length = Word8Vector.length bytes
      val isMinus = Word8Vector.sub (bytes, 0) >= word8 0wx80
      fun loop index mask value =
        let
          val index' = index + 1
          val mask' = W.<< (mask, 0w8)
          val msb = fromWord8ToW (Word8Vector.sub (bytes, index))
          val sum = W.+ (value, msb)
        in
(*          print ("index: " ^ Int.toString index ^ "\n");
          print ("mask: " ^ W.toString mask ^ "\n");
          print ("value: " ^ W.toString value ^ "\n");
          print ("msb: " ^ W.toString msb ^ "\n");
          print ("sum: " ^ W.toString sum ^ "\n");
          print "\n"; *)
          if index' = length then
            if isMinus then toInt (W.orb (sum, mask'))
            else toInt sum
          else loop index' mask' (W.* (sum, W.fromInt 256))
        end
    in
(*      print ("length: " ^ Int.toString length ^ "\n");
      print ("isMinus: " ^ Bool.toString isMinus ^ "\n");
      print "\n"; *)
      loop 0 (W.notb (W.fromInt 0)) (W.fromInt 0)
    end
end

(*
   UintPrinter prints I.int value
     I: integer type
     W: word type used for intermediate working memory
     S: output stream
*)
functor UintPrinter(structure I : I;
                    structure W : W;
                    structure S : sig
                      type outstream
                      val output1 : outstream * Word8.word -> unit
                    end) :> sig
  (* print int n outs *)
  val print : I.int -> int -> S.outstream -> unit
end = struct
  (* with the expectation that the compiler will optimize this idiom *)
  val fromIToW = W.fromLarge o LargeWord.fromLargeInt o I.toLarge
  val fromWToWord8 = Word8.fromLarge o W.toLarge
  fun reverse int n =
    let
      val word = fromIToW int
      fun loop src dest n =
        let
          val n' = n - 1
          val byte = W.andb (src, W.fromInt 0xff)
          val dest' = W.orb (dest, byte)
        in
          if n' = 0 then dest'
          else
            let
              val src' = W.>> (src, 0w8)
              val dest'' = W.<< (dest', 0w8)
            in
              loop src' dest'' n'
            end
        end
    in
      loop word (W.fromInt 0) n
    end
  fun print int n outs =
    let
      val reversed = reverse int n
      fun loop word n =
        if n = 0 then ()
        else
          let
            val byte = fromWToWord8 word
            val word' = W.>> (word, 0w8)
          in
            S.output1 (outs, byte);
            loop word' (n - 1)
          end
    in
      loop reversed n
    end
end

(*
   UintPrinterInf prints I.int value. Word8.word list is used for working memory
     I: integer type
     S: output stream
     fromInt: Word8.fromInt or Word8.fromLargeInt
*)
functor UintPrinterInf(structure I : I;
                       structure S : sig
                         type outstream
                         val output1 : outstream * Word8.word -> unit
                       end;
                       val fromInt : I.int -> Word8.word) :> sig
  val print : I.int -> int -> S.outstream -> unit
end = struct
  fun explode int n =
    let
      fun loop int n bytes =
        if n = 0 then bytes
        else
          let val byte = fromInt int in
            loop (I.div (int, I.fromInt 0x100)) (n - 1) (byte::bytes)
          end
    in
      loop int n []
    end
  fun print int n outs =
    let val exploded = explode int n in
      app (fn byte => S.output1 (outs, byte)) exploded
    end
end

functor BitScanner(structure I : I;
                   val toInt : Word8.word -> I.int) :> sig
  val scan : int -> int -> Word8Vector.vector -> I.int
end = struct
  val fromWordToI = I.fromLarge o Word.toLargeInt
  val word8 = Word8.fromLarge o Word.toLarge
  fun scan src length bytes =
    let
      fun scan src length i dest =
  (*      (print ("src "^Int.toString src^"\n");
        print ("length "^Int.toString length^"\n");
        print ("i "^Int.toString i^"\n");
        print ("dest "^Int.toString dest^"\n");
        print ("=\n"); *)
        if src >= 8 then scan (src - 8) length (i + 1) dest
        else
          let
            val byte = Word8Vector.sub (bytes, i)
            val mask = Word8.>> (word8 0wxff, Word.fromInt src)
            val byte' = Word8.andb (byte, mask) (* omit leading bis *)
          in
           if (length > 8 - src) then
             scan 0 (length - (8 - src)) (i + 1) (I.+ (I.* (dest, I.fromInt 0x100), toInt byte'))
           else
             let val lshift = fromWordToI (Word.<< (0w1, Word.fromInt length)) in
               I.+ (I.* (dest, lshift), toInt (Word8.>> (byte', Word.fromInt (8 - src - length))))
             end
          end
  (* ) *)
    in
      scan src length 0 (I.fromInt 0)
    end
end

(* exported functor applications *)

structure UintScannerInt = UintScanner(Int)
structure UintScannerLargeInt = UintScanner(LargeInt)
structure IntScannerIntWord =
  IntScanner(structure I = Int;
             structure W = Word;
             val toInt = W.toIntX)
structure IntScannerIntLargeWord =
  IntScanner(structure I = Int;
             structure W = LargeWord;
             val toInt = W.toIntX)
structure IntScannerLargeIntWord =
  IntScanner(structure I = LargeInt;
             structure W = Word;
             val toInt = W.toLargeIntX)
structure IntScannerLargeIntLargeWord =
  IntScanner(structure I = LargeInt;
             structure W = LargeWord;
             val toInt = W.toLargeIntX)

signature OS = sig
  type outstream
  val output1 : outstream * Word8.word -> unit
end

functor UintPrinterIntWord(S : OS) :> sig
  val print : Int.int -> int -> S.outstream -> unit
end = UintPrinter(structure I = Int; structure W = Word; structure S = S) 
functor UintPrinterIntLargeWord(S : OS) :> sig
  val print : Int.int -> int -> S.outstream -> unit
end = UintPrinter(structure I = Int; structure W = LargeWord; structure S = S)
functor UintPrinterInfInt(S : OS) :> sig
  val print : Int.int -> int -> S.outstream -> unit
end = UintPrinterInf(structure I = Int; structure S = S; val fromInt = Word8.fromInt)

structure BitScannerInt = BitScanner(structure I = Int; val toInt = Word8.toInt)
structure BitScannerLargeInt = BitScanner(structure I = LargeInt; val toInt = Word8.toLargeInt)
