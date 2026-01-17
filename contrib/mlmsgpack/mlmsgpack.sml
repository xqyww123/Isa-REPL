functor MessagePack(S : sig
                      type instream
                      type outstream
                      val input1 : instream -> (Word8.word * instream) option
                      val inputN : instream * int -> Word8Vector.vector * instream
                      val output : outstream * Word8Vector.vector -> unit
                      val output1 : outstream * Word8.word -> unit
                    end) :> sig
  structure Pack : sig
    type raw_packer = S.outstream -> unit
    type 'a packer = 'a -> raw_packer

    val doPack : 'a packer -> 'a packer

    val fromFn : 'a packer -> 'a packer

    val packList   : 'a packer -> 'a list   packer
    val packVector : 'a packer -> 'a vector packer
    val packArray  : 'a packer -> 'a array  packer
    val packArrayTabulate : 'a packer -> (int * (int -> 'a)) packer 

    val packPair   : 'a packer * 'b packer -> ('a * 'b) packer
    val packTuple3 : 'a packer * 'b packer * 'c packer -> ('a * 'b * 'c) packer
    val packTuple4 : 'a packer * 'b packer * 'c packer * 'd packer -> ('a * 'b * 'c * 'd) packer
    val packTuple5 : 'a packer * 'b packer * 'c packer * 'd packer * 'e packer -> ('a * 'b * 'c * 'd * 'e) packer
    val packTuple6 : 'a packer * 'b packer * 'c packer * 'd packer * 'e packer * 'f packer -> ('a * 'b * 'c * 'd * 'e * 'f) packer
    val packTuple7 : 'a packer * 'b packer * 'c packer * 'd packer * 'e packer * 'f packer * 'g packer
                      -> ('a * 'b * 'c * 'd * 'e * 'f * 'g) packer
    val packTuple8 : 'a packer * 'b packer * 'c packer * 'd packer * 'e packer * 'f packer * 'g packer * 'i packer
                      -> ('a * 'b * 'c * 'd * 'e * 'f * 'g * 'i) packer
    val packTuple9 : 'a packer * 'b packer * 'c packer * 'd packer * 'e packer * 'f packer * 'g packer * 'i packer * 'h packer
                      -> ('a * 'b * 'c * 'd * 'e * 'f * 'g * 'i * 'h) packer

    val packPairList : ('a packer * 'b packer) -> ('a * 'b) list packer
    val packMapTabulate : ('a packer * 'b packer) -> (int * (int -> 'a * 'b)) packer

    val packUnit   : unit packer
    val packBool   : bool packer
    val packInt    : int packer
    val packReal   : real packer

    val packString : string packer
    val packBytesToStr : Word8Vector.vector packer
    val packBytes  : Word8Vector.vector packer

    val packExtOfType : int -> Word8Vector.vector packer

    val packOption : 'a packer -> 'a option packer
  end
  structure Unpack : sig
    type 'a unpacker = S.instream -> 'a * S.instream
    exception Unpack

    val doUnpack : 'a unpacker -> S.instream -> 'a * S.instream
  
    val fromFn : (S.instream -> 'a * S.instream) -> 'a unpacker

    val || : 'a unpacker * 'a unpacker -> 'a unpacker
    val >> : 'a unpacker * ('a -> 'b) -> 'b unpacker

    val unpackArrayFold : 'a unpacker -> ('a * 'b -> 'b) -> 'b -> 'b unpacker
    val unpackList   : 'a unpacker -> 'a list unpacker
    val unpackVector : 'a unpacker -> 'a vector unpacker
    val unpackArray  : 'a unpacker -> 'a array unpacker

    val unpackPair : 'a unpacker * 'b unpacker -> ('a * 'b) unpacker
    val unpackPair_dep : 'a unpacker -> ('a -> 'b unpacker) -> ('a * 'b) unpacker
    val unpackPair_dep': 'a unpacker -> ('a -> 'b unpacker) -> 'b unpacker
    val unpackTuple3 : 'a unpacker * 'b unpacker * 'c unpacker -> ('a * 'b * 'c) unpacker
    val unpackTuple4 : 'a unpacker * 'b unpacker * 'c unpacker * 'd unpacker -> ('a * 'b * 'c * 'd) unpacker
    val unpackTuple5 : 'a unpacker * 'b unpacker * 'c unpacker * 'd unpacker * 'e unpacker -> ('a * 'b * 'c * 'd * 'e) unpacker
    val unpackTuple6 : 'a unpacker * 'b unpacker * 'c unpacker * 'd unpacker * 'e unpacker * 'f unpacker -> ('a * 'b * 'c * 'd * 'e * 'f) unpacker

    val unpackMapFold : ('a unpacker * 'b unpacker) -> ('a * 'b * 'c -> 'c) -> 'c -> 'c unpacker
    val unpackPairList : ('a unpacker * 'b unpacker) -> ('a * 'b) list unpacker
  
    val unpackUnit : unit unpacker
    val unpackBool : bool unpacker
    val unpackInt : int unpacker
    val unpackLargeInt : LargeInt.int unpacker
    val unpackReal : real unpacker

    val unpackString : string unpacker
    val unpackBytesFromStr : Word8Vector.vector unpacker
    val unpackBytes : Word8Vector.vector unpacker
    val unpackExt : (int * Word8Vector.vector) unpacker
    val unpackExtOfType : int -> Word8Vector.vector unpacker

    val unpackOption : 'a unpacker -> 'a option unpacker
  end
end = struct

  structure UintPrinterIntWord = UintPrinterIntWord(S)
  structure UintPrinterIntLargeWord = UintPrinterIntLargeWord(S)
  structure UintPrinterInfInt = UintPrinterInfInt(S)

  structure IntPrinterIntWord = UintPrinterIntWord
  structure IntPrinterIntLargeWord = UintPrinterIntLargeWord
  structure IntPrinterInfInt = UintPrinterInfInt

  structure RealPrinter = RealPrinter(S)

  val word8 = Word8.fromLarge o Word.toLarge
  fun fixArray length = Word8.orb (word8 0wx90, Word8.fromInt length)
  fun fixMap   length = Word8.orb (word8 0wx80, Word8.fromInt length)

  structure Pack = struct
    exception Pack

    type raw_packer = S.outstream -> unit
    type 'a packer = 'a -> S.outstream -> unit

    fun doPack p value outs = p value outs

    fun fromFn f = f

    local
      (* with the expectation that the compiler will optimize this idiom *)
      val fromWord8ToWord = Word.fromLarge o Word8.toLarge
      val fromWordToWord8 = Word8.fromLarge o Word.toLarge
      fun outputLength (fix, len16, len32) length outs =
        if length < 0x10 then
          (* Fix *) 
          S.output1 (outs, fix length)
        else if length < 0x10000 then
          (* 16 *)
          (S.output1 (outs, len16);
          UintPrinterIntWord.print length 2 outs)
        else if length div 0x10000 div 0x10000 = 0 then
          (* 32 *)
          (S.output1 (outs, len32);
          if Word.wordSize >= 32 then
            UintPrinterIntWord.print length 4 outs
          else if LargeWord.wordSize >= 32 then
            UintPrinterIntLargeWord.print length 4 outs
          else
            UintPrinterInfInt.print length 4 outs)
        else 
          raise Size;
      fun outputArrayLength length outs =
        outputLength (fixArray, word8 0wxdc, word8 0wxdd) length outs
      fun outputMapLength length outs =
        outputLength (fixMap,   word8 0wxde, word8 0wxdf) length outs
    in
      fun packList   p values outs = (outputArrayLength (List.length values)   outs; List.app   (fn v => p v outs) values)
      fun packVector p values outs = (outputArrayLength (Vector.length values) outs; Vector.app (fn v => p v outs) values)
      fun packArray  p values outs = (outputArrayLength (Array.length values)  outs; Array.app  (fn v => p v outs) values)
      fun packArrayTabulate p (n, f) outs =
        let
          fun loop i =
            if i >= n then ()
            else
              p (f i) outs
        in
          outputArrayLength n outs;
          loop 0
        end
  
      fun packPair (p1, p2) (v1, v2) outs =
        (outputArrayLength 2 outs;
        p1 v1 outs; p2 v2 outs)
      fun packTuple3 (p1, p2, p3) (v1, v2, v3) outs =
        (outputArrayLength 3 outs;
        p1 v1 outs; p2 v2 outs; p3 v3 outs)
      fun packTuple4 (p1, p2, p3, p4) (v1, v2, v3, v4) outs =
        (outputArrayLength 4 outs;
        p1 v1 outs; p2 v2 outs; p3 v3 outs; p4 v4 outs)
      fun packTuple5 (p1, p2, p3, p4, p5) (v1, v2, v3, v4, v5) outs =
        (outputArrayLength 5 outs;
        p1 v1 outs; p2 v2 outs; p3 v3 outs; p4 v4 outs; p5 v5 outs)
      fun packTuple6 (p1, p2, p3, p4, p5, p6) (v1, v2, v3, v4, v5, v6) outs =
        (outputArrayLength 6 outs;
        p1 v1 outs; p2 v2 outs; p3 v3 outs; p4 v4 outs; p5 v5 outs; p6 v6 outs)
      fun packTuple7 (p1, p2, p3, p4, p5, p6, p7) (v1, v2, v3, v4, v5, v6, v7) outs =
        (outputArrayLength 7 outs;
        p1 v1 outs; p2 v2 outs; p3 v3 outs; p4 v4 outs; p5 v5 outs; p6 v6 outs; p7 v7 outs)
      fun packTuple8 (p1, p2, p3, p4, p5, p6, p7, p8) (v1, v2, v3, v4, v5, v6, v7, v8) outs =
        (outputArrayLength 8 outs;
        p1 v1 outs; p2 v2 outs; p3 v3 outs; p4 v4 outs; p5 v5 outs; p6 v6 outs; p7 v7 outs; p8 v8 outs)
      fun packTuple9 (p1, p2, p3, p4, p5, p6, p7, p8, p9)
                     (v1, v2, v3, v4, v5, v6, v7, v8, v9) outs =
        (outputArrayLength 9 outs;
        p1 v1 outs; p2 v2 outs; p3 v3 outs; p4 v4 outs; p5 v5 outs; p6 v6 outs; p7 v7 outs;
        p8 v8 outs; p9 v9 outs)

      fun packPairList (p1, p2) values outs =
        (outputMapLength (List.length values) outs;
        app (fn (v1, v2) => (p1 v1 outs; p2 v2 outs)) values)
      fun packMapTabulate (p1, p2) (n, f) outs =
        let
          fun loop i =
            if i >= n then ()
            else
              let val (v1, v2) = f i in
                p1 v1 outs;
                p2 v2 outs
             end
        in
          outputMapLength n outs;
          loop 0
        end

      fun packUnit () outs = S.output1 (outs, word8 0wxc0)
      fun packBool bool outs =
        if bool then S.output1 (outs, word8 0wxc3)
                else S.output1 (outs, word8 0wxc2)
  
      fun packInt int outs = 
        if (int >= 0   andalso int <= 127) orelse
           (int >= ~32 andalso int <=  ~1) then
          S.output1 (outs, Word8.fromInt int)
        else if int > 0 then
          (* positive *)
          if int < 0x100 then
            (* uint 8 *)
            (S.output1 (outs, word8 0wxcc);
            S.output1 (outs, Word8.fromInt int))
          else if int < 0x10000 then
            (* uint 16 *)
            (S.output1 (outs, word8 0wxcd);
            UintPrinterIntWord.print int 2 outs)
          else if int div 0x10000 div 0x10000 = 0 then
            (* uint 32 *)
            (S.output1 (outs, word8 0wxce);
            if Word.wordSize >= 32 then
              UintPrinterIntWord.print int 4 outs
            else if LargeWord.wordSize >= 32 then
              UintPrinterIntLargeWord.print int 4 outs
            else
              (* is there any implementation s.t. LargeWord.wordSize < 32 ? *)
              UintPrinterInfInt.print int 4 outs)
          else if int div 0x10000 div 0x10000 div 0x10000 div 0x10000 = 0 then
            (* uint 64 *)
            (S.output1 (outs, word8 0wxcf);
            if Word.wordSize >= 64 then
              UintPrinterIntWord.print int 8 outs
            else if LargeWord.wordSize >= 64 then
              UintPrinterIntLargeWord.print int 8 outs
            else
              UintPrinterInfInt.print int 8 outs)
          else
            raise Overflow
        else
          (* negative *)
          if int >= ~128 then
            (* int 8 *)
            (S.output1 (outs, word8 0wxd0);
            S.output1 (outs, Word8.fromInt int))
          else if int >= ~32768 then
            (* int 16 *)
            (S.output1 (outs, word8 0wxd1);
            IntPrinterIntWord.print int 2 outs)
          else if int div 0x8000 div 0x10000 = ~1 then
            (* int 32 *)
            (S.output1 (outs, word8 0wxd2);
            if Word.wordSize >= 32 then
              IntPrinterIntWord.print int 4 outs
            else if LargeWord.wordSize >= 32 then
              IntPrinterIntLargeWord.print int 4 outs
            else
              IntPrinterInfInt.print int 4 outs)
          else if int div 0x8000 div 0x10000 div 0x10000 div 0x10000 = ~1 then
            (* int 64 *)
            (S.output1 (outs, word8 0wxd3);
            if Word.wordSize >= 64 then
              IntPrinterIntWord.print int 8 outs
            else if LargeWord.wordSize >= 64 then
              IntPrinterIntLargeWord.print int 8 outs
            else
              IntPrinterInfInt.print int 8 outs)
          else
            raise Overflow
    end

    fun packReal real outs =
      (if RealPrinter.bytesPerElem = 8 then
        S.output1 (outs, word8 0wxcb)
      else if RealPrinter.bytesPerElem = 4 then
        S.output1 (outs, word8 0wxca)
      else
        raise Pack;
      RealPrinter.print real outs)

    local
      fun packRaw (raw8, raw16, raw32, typ) bytes outs =
        let val length = Word8Vector.length bytes in
          if length < 0x100 then
            (* raw 8 *)
            (S.output1 (outs, raw8);
            S.output1 (outs, Word8.fromInt length))
          else if length div 0x10000 = 0 then
            (* raw 16 *)
            (S.output1 (outs, raw16);
            UintPrinterIntWord.print length 2 outs)
          else if length div 0x10000 div 0x10000 = 0 then
            (* raw 32 *)
            (S.output1 (outs, raw32);
            if Word.wordSize >= 32 then
              UintPrinterIntWord.print length 4 outs
            else if LargeWord.wordSize >= 32 then
              UintPrinterIntLargeWord.print length 4 outs
            else
              UintPrinterInfInt.print length 4 outs)
          else
            raise Size;
          S.output (outs, typ);
          S.output (outs, bytes)
        end
      val emptyBytes = Word8Vector.fromList []
    in
      fun packBytesToStr bytes outs =
        let val length = Word8Vector.length bytes in
          if length < 32 then
            (* FixStr *)
            (S.output1 (outs, (Word8.orb (word8 0wxa0, Word8.fromInt length)));
            S.output (outs, bytes))
          else
            packRaw (word8 0wxd9, word8 0wxda, word8 0wxdb, emptyBytes) bytes outs
        end
      fun packString string outs = packBytesToStr (Byte.stringToBytes string) outs
      fun packBytes bytes outs = packRaw (word8 0wxc4, word8 0wxc5, word8 0wxc6, emptyBytes) bytes outs

      fun packExtOfType typ bytes outs =
        let
          val length = Word8Vector.length bytes
          val typByte = Word8.fromInt typ
        in
          if length = 1 then
            (S.output1 (outs, word8 0wxd4); S.output1 (outs, typByte); S.output (outs, bytes))
          else if length = 2 then
            (S.output1 (outs, word8 0wxd5); S.output1 (outs, typByte); S.output (outs, bytes))
          else if length = 4 then
            (S.output1 (outs, word8 0wxd6); S.output1 (outs, typByte); S.output (outs, bytes))
          else if length = 8 then
            (S.output1 (outs, word8 0wxd7); S.output1 (outs, typByte); S.output (outs, bytes))
          else if length = 16 then
            (S.output1 (outs, word8 0wxd8); S.output1 (outs, typByte); S.output (outs, bytes))
          else
            let
              val typVector = Word8Vector.tabulate (1, fn _ => typByte)
            in
              packRaw (word8 0wxc7, word8 0wxc8, word8 0wxc9, typVector) bytes outs
            end
        end
    end

    fun packOption p option outs =
      case option of 
        SOME value => p value outs
      | NONE => packUnit () outs

  end

  structure Unpack = struct
    exception Unpack

    type 'a unpacker = S.instream -> 'a * S.instream

    fun doUnpack u ins = u ins

    fun fromFn f = f
  
    (* alternate *)
    infix 0 ||
    fun (u1 || u2) ins = \<^try>\<open>u1 ins catch _  => u2 ins\<close>

    (* concatenate *)
    infix 5 --
    fun (u1 -- u2) ins = 
      let val (v1, ins1) = u1 ins
          val (v2, ins2) = u2 ins1
      in
        ((v1, v2), ins2)
      end

    (* transformation *)
    infix 3 >>
    fun (u >> f) ins =
      let val (v, ins') = u ins in
        (f v, ins')
      end

    fun expect expected ins =
      case S.input1 ins of
        SOME (byte, ins') => if byte = expected then ins' else raise Unpack
      | NONE => raise Unpack

    local
      fun isFixArray byte = Word8.andb (byte, word8 0wxf0) = word8 0wx90
      fun isFixMap byte = Word8.andb (byte, word8 0wxf0) = word8 0wx80
      fun lengthOfFix byte = Word8.toInt (Word8.andb (byte, word8 0wx0f))
      fun scanFixArray ins =
        case S.input1 ins of
          SOME (byte, ins')
            => if isFixArray byte then (lengthOfFix byte, ins')
               else raise Unpack
        | NONE => raise Unpack
      fun scanArray16 ins = 
        let
          val ins' = expect (word8 0wxdc) ins
          val (bytes, ins'') = S.inputN (ins', 2)
          val length = UintScannerInt.scan bytes handle Overflow => raise Size
        in
          (length, ins'')
        end
      fun scanArray32 ins = 
        let
          val ins' = expect (word8 0wxdd) ins
          val (bytes, ins'') = S.inputN (ins', 4)
          val length = UintScannerInt.scan bytes handle Overflow => raise Size
        in
          (length, ins'')
        end
      fun scanFixMap ins =
        case S.input1 ins of
          SOME (byte, ins')
            => if isFixMap byte then (lengthOfFix byte, ins')
               else raise Unpack
        | NONE => raise Unpack
      fun scanMap16 ins = 
        let
          val ins' = expect (word8 0wxde) ins
          val (bytes, ins'') = S.inputN (ins', 2)
          val length = UintScannerInt.scan bytes handle Overflow => raise Size
        in
          (length, ins'')
        end
      fun scanMap32 ins = 
        let
          val ins' = expect (word8 0wxdf) ins
          val (bytes, ins'') = S.inputN (ins', 4)
          val length = UintScannerInt.scan bytes handle Overflow => raise Size
        in
          (length, ins'')
        end
      fun unpackFold length u f init ins =
        let
          fun loop ins n acc =
            if n = 0 then (acc, ins)
            else
              let val (value, ins') = u ins in
                loop ins' (n - 1) (f (value, acc))
              end
        in
          loop ins length init
        end
    in
      fun unpackArrayFold u f init ins =
        let
          val (length, ins') = (scanFixArray || scanArray16 || scanArray32) ins
        in
          unpackFold length u f init ins'
        end

      fun unpackList u ins = (unpackArrayFold u (op::) [] >> rev) ins 
      fun unpackVector u ins = (unpackList u >> Vector.fromList) ins
      fun unpackArray u ins = (unpackList u >> Array.fromList) ins

      fun unpackMapFold (u1, u2) f init ins =
        let
          val (length, ins') = (scanFixMap || scanMap16 || scanMap32) ins
        in
          unpackFold length (u1 -- u2) (fn ((a, b), c) => f (a, b, c)) init ins'
        end

      fun unpackPairList (u1, u2) ins =
        unpackMapFold (u1, u2) (fn (k, v, l) => (k, v)::l) [] ins
    end
 
    fun unpackPair (u1, u2) ins =
      let
        val ins0 = expect (fixArray 2) ins
        val (v1, ins1) = u1 ins0
        val (v2, ins2) = u2 ins1
      in
        ((v1, v2), ins2)
      end

     fun unpackPair_dep u1 u2 ins =
      let
        val ins0 = expect (fixArray 2) ins
        val (v1, ins1) = u1 ins0
        val (v2, ins2) = u2 v1 ins1
      in
        ((v1, v2), ins2)
      end

      fun unpackPair_dep' u1 u2 ins =
      let
        val ins0 = expect (fixArray 2) ins
        val (v1, ins1) = u1 ins0
        val (v2, ins2) = u2 v1 ins1
      in
        (v2, ins2)
      end
  
    fun unpackTuple3 (u1, u2, u3) ins =
      let
        val ins0 = expect (fixArray 3) ins
        val (v1, ins1) = u1 ins0
        val (v2, ins2) = u2 ins1
        val (v3, ins3) = u3 ins2
      in
        ((v1, v2, v3), ins3)
      end
  
    fun unpackTuple4 (u1, u2, u3, u4) ins =
      let
        val ins0 = expect (fixArray 4) ins
        val (v1, ins1) = u1 ins0
        val (v2, ins2) = u2 ins1
        val (v3, ins3) = u3 ins2
        val (v4, ins4) = u4 ins3
      in
        ((v1, v2, v3, v4), ins4)
      end
  
    fun unpackTuple5 (u1, u2, u3, u4, u5) ins =
      let
        val ins0 = expect (fixArray 5) ins
        val (v1, ins1) = u1 ins0
        val (v2, ins2) = u2 ins1
        val (v3, ins3) = u3 ins2
        val (v4, ins4) = u4 ins3
        val (v5, ins5) = u5 ins4
      in
        ((v1, v2, v3, v4, v5), ins5)
      end
  
    fun unpackTuple6 (u1, u2, u3, u4, u5, u6) ins =
      let
        val ins0 = expect (fixArray 6) ins
        val (v1, ins1) = u1 ins0
        val (v2, ins2) = u2 ins1
        val (v3, ins3) = u3 ins2
        val (v4, ins4) = u4 ins3
        val (v5, ins5) = u5 ins4
        val (v6, ins6) = u6 ins5
      in
        ((v1, v2, v3, v4, v5, v6), ins6)
      end
  
    local 
      fun isPositiveFixnum byte =
        byte >= (word8 0wx00) andalso byte <= (word8 0wx7f)
      fun isNegativeFixnum byte =
        byte >= (word8 0wxe0) andalso byte <= (word8 0wxff)
      fun isUint8  byte = byte = word8 0wxcc
      fun isUint16 byte = byte = word8 0wxcd
      fun isUint32 byte = byte = word8 0wxce
      fun isUint64 byte = byte = word8 0wxcf
      fun isInt8   byte = byte = word8 0wxd0
      fun isInt16  byte = byte = word8 0wxd1
      fun isInt32  byte = byte = word8 0wxd2
      fun isInt64  byte = byte = word8 0wxd3
      fun isFloat  byte = byte = word8 0wxca
      fun isDouble byte = byte = word8 0wxcb

      val fromWord8toWord = Word.fromLarge o Word8.toLarge
  
      fun unpackFixnum pred f ins =
        case S.input1 ins of
          SOME (byte, ins') => if pred byte then (f byte, ins') else raise Unpack
        | NONE => raise Unpack
      fun unpackPositiveFixnum f ins = unpackFixnum isPositiveFixnum f ins
      fun unpackNegativeFixnum f ins = unpackFixnum isNegativeFixnum f ins
  
      val unpackCategory1 = unpackFixnum
 
      fun unpackCategory2 pred f ins =
        case S.input1 ins of
          SOME (byte, ins') =>
            if pred byte then
              let
                val length = Word8.toInt (Word8.<< (word8 0w1, fromWord8toWord (Word8.andb (byte, word8 0wx03))))
                val (bytes, ins'') = S.inputN (ins', length)
              in
                (f bytes, ins'')
              end
            else raise Unpack
        | NONE => raise Unpack
      fun unpackUint8  f ins = unpackCategory2 isUint8  f ins
      fun unpackUint16 f ins = unpackCategory2 isUint16 f ins
      fun unpackUint32 f ins = unpackCategory2 isUint32 f ins
      fun unpackUint64 f ins = unpackCategory2 isUint64 f ins
      fun unpackInt8   f ins = unpackCategory2 isInt8   f ins
      fun unpackInt16  f ins = unpackCategory2 isInt16  f ins
      fun unpackInt32  f ins = unpackCategory2 isInt32  f ins
      fun unpackInt64  f ins = unpackCategory2 isInt64  f ins

      val minPos = Math.pow (2.0, ~1022.0 - 52.0)
      val minPos32 = Math.pow (2.0, ~126.0 - 23.0)
     
      fun scanFloat bytes =
        let
          val sign = if BitScannerInt.scan 0 1 bytes = 0 then 1.0 else ~1.0
          val biasedExponent = BitScannerInt.scan 1 8 bytes
          val exponent = Real.fromInt (biasedExponent - 127)
          val extraBit = if biasedExponent = 0 then 0 else 0x800000 (* 1 << 23 *)
          val significand' = BitScannerInt.scan 9 23 bytes
          val significand = Real.fromInt (significand' + extraBit) * Math.pow(2.0, ~23.0)
        in
          if biasedExponent = 255 then
            if significand' = 0 then sign / 0.0 else 0.0 / 0.0
          else if biasedExponent = 0 then
            sign * minPos32 * Real.fromInt significand'
          else
            sign * significand * Math.pow(2.0, exponent)
        end
      fun scanDouble bytes =
        let
          val sign = if BitScannerInt.scan 0 1 bytes = 0 then 1.0 else ~1.0
          val biasedExponent = BitScannerInt.scan 1 11 bytes
          val exponent = Real.fromInt (biasedExponent - 1023)
          val extraBit = if biasedExponent = 0 then 0 else 0x4000000 (* 1 << 26 *)
          val significandH' = BitScannerInt.scan 12 26 bytes
          val significandL' = BitScannerInt.scan 38 26 bytes
          val significandH = Real.fromInt (significandH' + extraBit) * Math.pow (2.0, ~26.0)
          val significandL = Real.fromInt significandL' * Math.pow (2.0, ~52.0)
          val significand = significandH + significandL
        in
          if biasedExponent = 2047 then
            if significandH' = 0 andalso significandL' = 0 then sign / 0.0 else 0.0 / 0.0
          else if biasedExponent = 0 then
            sign * minPos * (Real.fromInt significandH' * Math.pow (2.0, 26.0) + Real.fromInt significandL')
          else
            sign * significand * Math.pow(2.0, exponent)
        end

      fun unpackFloat  ins = unpackCategory2 isFloat  scanFloat  ins
      fun unpackDouble ins = unpackCategory2 isDouble scanDouble ins
    in
      fun unpackUnit ins = unpackCategory1 (fn byte => byte = word8 0wxc0) (fn _ => ()) ins
      fun unpackBool ins =
        let
          fun isBool byte = byte = word8 0wxc2 orelse byte = word8 0wxc3
          fun toBool byte = byte = word8 0wxc3
        in
          unpackCategory1 isBool toBool ins
        end
      fun unpackInt ins = (
           unpackPositiveFixnum Word8.toInt
        || unpackNegativeFixnum Word8.toIntX
        || unpackUint8  (fn bytes => Word8.toInt  (Word8Vector.sub (bytes, 0)))
        || unpackInt8   (fn bytes => Word8.toIntX (Word8Vector.sub (bytes, 0)))
        || unpackUint16 UintScannerInt.scan
        || unpackInt16   IntScannerIntWord.scan
        || unpackUint32 UintScannerInt.scan
        || unpackInt32   IntScannerIntLargeWord.scan
        || unpackUint64 UintScannerInt.scan
        || unpackInt64   IntScannerIntLargeWord.scan
      ) ins
      fun unpackLargeInt ins = (
           unpackPositiveFixnum Word8.toLargeInt 
        || unpackNegativeFixnum Word8.toLargeIntX
        || unpackUint8 (fn bytes => Word8.toLargeInt  (Word8Vector.sub (bytes, 0)))
        || unpackInt8  (fn bytes => Word8.toLargeIntX (Word8Vector.sub (bytes, 0)))
        || unpackUint16 UintScannerLargeInt.scan
        || unpackInt16   IntScannerLargeIntWord.scan
        || unpackUint32 UintScannerLargeInt.scan
        || unpackInt32   IntScannerLargeIntLargeWord.scan
        || unpackUint64 UintScannerLargeInt.scan
        || unpackInt64   IntScannerLargeIntLargeWord.scan
      ) ins

      fun unpackReal ins = (
           unpackDouble
        || unpackFloat
      ) ins
    end

    local
      fun isFixRaw byte = Word8.andb (byte, word8 0wxe0) = word8 0wxa0
      fun lengthOfFixRaw byte = Word8.toInt (Word8.andb (byte, word8 0wx1f))

      fun scanFixStr ins =
        case S.input1 ins of
          SOME (byte, ins')
            => if isFixRaw byte then (lengthOfFixRaw byte, ins')
               else raise Unpack
        | NONE => raise Unpack
      fun scanRaw8 pred ins = 
        let
          val ins' = expect pred ins
        in
          case S.input1 ins' of
            SOME (byte, ins'') => (Word8.toInt byte, ins'')
          | NONE => raise Unpack
        end
      fun scanRaw16 pred ins = 
        let
          val ins' = expect pred ins
          val (bytes, ins'') = S.inputN (ins', 2)
          val length = UintScannerInt.scan bytes handle Overflow => raise Size
        in
          (length, ins'')
        end
      fun scanRaw32 pred ins = 
        let
          val ins' = expect pred ins
          val (bytes, ins'') = S.inputN (ins', 4)
          val length = UintScannerInt.scan bytes handle Overflow => raise Size
        in
          (length, ins'')
        end
      val scanStr8  = scanRaw8  (word8 0wxd9)
      val scanStr16 = scanRaw16 (word8 0wxda)
      val scanStr32 = scanRaw32 (word8 0wxdb)
      val scanBin8  = scanRaw8  (word8 0wxc4)
      val scanBin16 = scanRaw16 (word8 0wxc5)
      val scanBin32 = scanRaw32 (word8 0wxc6)

      fun scanFixExt1 ins = (1, expect (word8 0wxd4) ins)
      fun scanFixExt2 ins = (2, expect (word8 0wxd5) ins)
      fun scanFixExt4 ins = (4, expect (word8 0wxd6) ins)
      fun scanFixExt8 ins = (8, expect (word8 0wxd7) ins)
      fun scanFixExt16 ins = (16, expect (word8 0wxd8) ins)
      val scanExt8  = scanRaw8 (word8 0wxc7)
      val scanExt16 = scanRaw16 (word8 0wxc8)
      val scanExt32 = scanRaw32 (word8 0wxc9)
    in
      fun unpackBytesFromStr ins =
        let
          val (length, ins') = (scanFixStr || scanStr8 || scanStr16 || scanStr32) ins
        in
          S.inputN (ins', length)
        end
      val unpackString = unpackBytesFromStr >> Byte.bytesToString
      fun unpackBytes ins =
        let
          val (length, ins') = (scanBin8 || scanBin16 || scanBin32) ins
        in
          S.inputN (ins', length)
        end
      fun unpackExt ins =
        let
          val (length, ins') = (
               scanFixExt1 || scanFixExt2 || scanFixExt4 || scanFixExt8 || scanFixExt16
            || scanExt8 || scanExt16 || scanExt32) ins
          val (typ, ins'') = case S.input1 ins' of SOME x => x | NONE => raise Unpack
          val (bytes, ins''') = S.inputN (ins'', length)
        in
          ((Word8.toInt typ, bytes), ins''')
        end
      fun unpackExtOfType typ ins =
        let
          val (length, ins') = (
               scanFixExt1 || scanFixExt2 || scanFixExt4 || scanFixExt8 || scanFixExt16
            || scanExt8 || scanExt16 || scanExt32) ins
          val ins'' = expect (Word8.fromInt typ) ins'
        in
          S.inputN (ins'', length)
        end
    end

    fun unpackOption u ins =
      (u >> SOME || unpackUnit >> (fn () => NONE)) ins
  
  end
end

structure BytesIO = struct
  type 'a ref = 'a Unsynchronized.ref

  datatype bytes_list = Nil | ConsA of int ref * Word8Array.array * bytes_list | ConsV of Word8Vector.vector * bytes_list
  type instream = Word8VectorSlice.slice
  type outstream = bytes_list ref
  val word8 = Word8.fromLarge o Word.toLarge
  fun input1 slice =
    if Word8VectorSlice.length slice = 0 then NONE
    else SOME (Word8VectorSlice.sub (slice, 0), Word8VectorSlice.subslice (slice, 1, NONE))
  fun inputN (slice, n) =
    let
      val vector = Word8VectorSlice.vector (Word8VectorSlice.subslice (slice, 0, SOME n))
      val slice' = Word8VectorSlice.subslice (slice, n, NONE)
    in
      (vector, slice')
    end

  val chunkSize = Unsynchronized.ref 256

  local
    fun extendAndSet1 (outs as Unsynchronized.ref bytesList, byte) =
      let
        val newArray = Word8Array.array (!chunkSize, word8 0wx00)
      in
        Word8Array.update (newArray, 0, byte);
        outs := ConsA (Unsynchronized.ref 1, newArray, bytesList)
      end
  in
    fun output1 (outs as Unsynchronized.ref (ConsA (posRef as Unsynchronized.ref pos, array, _)), byte) =
      if pos < Word8Array.length array then
        (Word8Array.update (array, pos, byte);
        posRef := pos + 1)
      else extendAndSet1 (outs, byte)
      | output1 (outs, byte) = extendAndSet1 (outs, byte)
  end

  local
    fun extendWithVector (outs as Unsynchronized.ref bytesList, bytes) =
      outs := ConsV (bytes, bytesList)
  in
    fun output (outs as Unsynchronized.ref (ConsA (posRef as Unsynchronized.ref pos, array, _)), bytes) =
      let
        val bytesLength = Word8Vector.length bytes
      in
        if pos + bytesLength <= Word8Array.length array then
          (Word8Array.copyVec { src = bytes, dst = array, di = pos };
          posRef := pos + bytesLength)
        else extendWithVector (outs, bytes)
      end
      | output (outs, bytes) = extendWithVector (outs, bytes)
  end

  fun mkOutstream () = Unsynchronized.ref Nil

  fun fromBytes bytes = Word8VectorSlice.full bytes
  fun fromString string = fromBytes (Byte.stringToBytes string)
  fun toBytes outs =
    let
      fun toVectors Nil vectors = vectors
        | toVectors (ConsV (vector, bytesList)) vectors = toVectors bytesList (vector::vectors)
        | toVectors (ConsA (Unsynchronized.ref pos, array, bytesList)) vectors =
        let
          val vector = Word8Vector.tabulate (pos, fn n => Word8Array.sub (array, n))
        in
          toVectors bytesList (vector::vectors)
        end
      val vectors = toVectors (!outs) []
    in
      Word8Vector.concat vectors
    end
  fun toString outs = Byte.bytesToString (toBytes outs)
end

structure IntListIO = struct
  type instream = int list
  type outstream = int list Unsynchronized.ref
  fun input1 [] = NONE
    | input1 (x::xs) = SOME (Word8.fromInt x, xs)
  fun inputN (ins, n) =
    let
      val vector = Word8Vector.fromList (map Word8.fromInt (List.take (ins, n)))
      val ins' = List.drop (ins, n)
    in
      (vector, ins')
    end
  fun output1 (outs, byte) =
    outs := (Word8.toInt byte)::(!outs)
  fun output (outs, bytes) =
    Word8Vector.app (fn byte => output1 (outs, byte)) bytes
  fun toList outs = List.rev (!outs)
  fun mkOutstream () : outstream = Unsynchronized.ref []
end

structure MessagePackBinIO = MessagePack(BinIO.StreamIO)
structure MessagePackIntListIO = MessagePack(IntListIO)
structure MessagePackBytesIO = MessagePack(BytesIO)
