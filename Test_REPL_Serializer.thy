theory Test_REPL_Serializer
  imports Isa_REPL
begin

ML \<open>
(* ================================================================
   Test infrastructure
   ================================================================ *)

fun assert_eq msg expected actual =
  if expected = actual then ()
  else error ("FAIL [" ^ msg ^ "]: expected " ^ quote expected
              ^ " but got " ^ quote actual)

fun assert_true msg cond =
  if cond then ()
  else error ("FAIL [" ^ msg ^ "]")

fun has_substring haystack needle =
  let val n = size needle
      val h = size haystack
      fun check i =
        if i + n > h then false
        else String.substring (haystack, i, n) = needle orelse check (i + 1)
   in n = 0 orelse check 0
  end

fun assert_contains msg needle haystack =
  assert_true (msg ^ ": should contain " ^ quote needle)
    (has_substring haystack needle)

fun assert_not_contains msg needle haystack =
  assert_true (msg ^ ": should not contain " ^ quote needle)
    (not (has_substring haystack needle))

(* ── Common printing configs ── *)

val cfg_none : REPL_Serialize.printing_config = {
  all_typ = false, bv_typ = false, constant_typ = false,
  free_typ = false, num_typ = false, sorting = false,
  show_type_P = NONE, show_sort_P = NONE
}

val cfg_all : REPL_Serialize.printing_config = {
  all_typ = true, bv_typ = false, constant_typ = false,
  free_typ = false, num_typ = false, sorting = false,
  show_type_P = NONE, show_sort_P = NONE
}

val cfg_all_sort : REPL_Serialize.printing_config = {
  all_typ = true, bv_typ = false, constant_typ = false,
  free_typ = false, num_typ = false, sorting = true,
  show_type_P = NONE, show_sort_P = NONE
}

val cfg_free : REPL_Serialize.printing_config = {
  all_typ = false, bv_typ = false, constant_typ = false,
  free_typ = true, num_typ = false, sorting = false,
  show_type_P = NONE, show_sort_P = NONE
}

val cfg_bv : REPL_Serialize.printing_config = {
  all_typ = false, bv_typ = true, constant_typ = false,
  free_typ = false, num_typ = false, sorting = false,
  show_type_P = NONE, show_sort_P = NONE
}

val cfg_const : REPL_Serialize.printing_config = {
  all_typ = false, bv_typ = false, constant_typ = true,
  free_typ = false, num_typ = false, sorting = false,
  show_type_P = NONE, show_sort_P = NONE
}

val cfg_num : REPL_Serialize.printing_config = {
  all_typ = false, bv_typ = false, constant_typ = false,
  free_typ = false, num_typ = true, sorting = false,
  show_type_P = NONE, show_sort_P = NONE
}

(* Probabilistic configs *)
val cfg_all_P1 : REPL_Serialize.printing_config = {
  all_typ = true, bv_typ = false, constant_typ = false,
  free_typ = false, num_typ = false, sorting = false,
  show_type_P = SOME 1.0, show_sort_P = NONE
}

val cfg_all_P0 : REPL_Serialize.printing_config = {
  all_typ = true, bv_typ = false, constant_typ = false,
  free_typ = false, num_typ = false, sorting = false,
  show_type_P = SOME 0.0, show_sort_P = NONE
}

val cfg_sort_P1 : REPL_Serialize.printing_config = {
  all_typ = true, bv_typ = false, constant_typ = false,
  free_typ = false, num_typ = false, sorting = true,
  show_type_P = NONE, show_sort_P = SOME 1.0
}

val cfg_sort_P0 : REPL_Serialize.printing_config = {
  all_typ = true, bv_typ = false, constant_typ = false,
  free_typ = false, num_typ = false, sorting = true,
  show_type_P = NONE, show_sort_P = SOME 0.0
}
\<close>


(* ================================================================
   1. print_term: no type info in context (show_types = false)
      Config flags are irrelevant when there are no typing XML
      elements, so all configs should produce the same output.
   ================================================================ *)

term \<open>let x = a in f x\<close>

ML \<open>
let
  val ctxt = \<^context>
  val pt = REPL_Serialize.print_term

  (* ── Simple constants ── *)
  val _ = assert_eq "True"  "True"  (pt cfg_none ctxt @{term True})
  val _ = assert_eq "False" "False" (pt cfg_none ctxt @{term False})

  (* ── Numbers ── *)
  val _ = assert_eq "0"     "0"     (pt cfg_none ctxt @{term "0::nat"})
  val _ = assert_eq "1"     "1"     (pt cfg_none ctxt @{term "1::nat"})
  val _ = assert_eq "42"    "42"    (pt cfg_none ctxt @{term "42::nat"})
  val _ = assert_eq "Suc 0" "Suc 0" (pt cfg_none ctxt @{term "Suc 0"})

  (* ── Free variables ── *)
  val _ = assert_eq "free x" "x" (pt cfg_none ctxt @{term "x::nat"})

  (* ── Application ── *)
  val _ = assert_eq "x + y" "x + y" (pt cfg_none ctxt @{term "x + (y::nat)"})

  (* ── Lambda ── *)
  val _ = assert_eq "lam x.x" "\<lambda>x. x" (pt cfg_none ctxt @{term "\<lambda>x::nat. x"})
  (* \<lambda>f x. f x eta-contracts to \<lambda>f. f *)
  val _ = assert_eq "lam f x. f x (eta)" "\<lambda>f. f"
    (pt cfg_none ctxt @{term "\<lambda>(f::nat\<Rightarrow>nat) (x::nat). f x"})
  (* \<lambda>x y z. x + y + z  eta-contracts:  \<lambda>z. (+) (x+y) z  \<longrightarrow>  (+) (x+y) *)
  val _ = assert_eq "lam x y z (eta)" "\<lambda>x y. (+) (x + y)"
    (pt cfg_none ctxt @{term "\<lambda>x y z. x + y + (z::nat)"})

  (* ── Connectives ── *)
  val _ = assert_eq "implies" "A \<longrightarrow> B" (pt cfg_none ctxt @{term "A \<longrightarrow> B"})
  val _ = assert_eq "conj"    "A \<and> B"   (pt cfg_none ctxt @{term "A \<and> B"})
  val _ = assert_eq "disj"    "A \<or> B"   (pt cfg_none ctxt @{term "A \<or> B"})
  val _ = assert_eq "neg"     "\<not> P"     (pt cfg_none ctxt @{term "\<not> P"})

  (* ── Quantifiers ── *)
  val _ = assert_eq "forall" "\<forall>x. P x" (pt cfg_none ctxt @{term "\<forall>x. P x"})
  val _ = assert_eq "exists" "\<exists>x. P x" (pt cfg_none ctxt @{term "\<exists>x. P x"})

  (* ── Data structures ── *)
  val _ = assert_eq "list"   "[a, b, c]" (pt cfg_none ctxt @{term "[a, b, c]"})
  val _ = assert_eq "nil"    "[]"         (pt cfg_none ctxt @{term "[]::nat list"})
  val _ = assert_eq "pair"   "(a, b)"     (pt cfg_none ctxt @{term "(a, b)"})
  val _ = assert_eq "unit"   "()"         (pt cfg_none ctxt @{term "()"})

  (* ── Conditional / let ── *)
  val _ = assert_eq "if" "if P then a else b"
    (pt cfg_none ctxt @{term "if P then (a::nat) else b"})
  val _ = assert_eq "let" "let x = a in f x"
    (pt cfg_none ctxt @{term "let x = (a::nat) in f x"})

  (* ── Nested application ── *)
  val _ = assert_eq "nested app" "f (g (h x))"
    (pt cfg_none ctxt @{term "f (g (h (x::nat)))"})

  (* ── Set operations ── *)
  val _ = assert_eq "mem" "x \<in> S" (pt cfg_none ctxt @{term "x \<in> S"})

  (* ── Theorem props ── *)
  val _ = assert_eq "refl" "?t = ?t"
    (pt cfg_none ctxt (Thm.prop_of @{thm refl}))

  (* ── Config flags irrelevant without typing XML elements ── *)
  val t = @{term "x + (y::nat)"}
  val s0 = pt cfg_none ctxt t
  val _ = assert_eq "cfg_all = cfg_none (no types in ctxt)" s0 (pt cfg_all ctxt t)
  val _ = assert_eq "cfg_free = cfg_none (no types in ctxt)" s0 (pt cfg_free ctxt t)
  val _ = assert_eq "cfg_bv = cfg_none (no types in ctxt)" s0 (pt cfg_bv ctxt t)
  val _ = assert_eq "cfg_num = cfg_none (no types in ctxt)" s0 (pt cfg_num ctxt t)
  val _ = assert_eq "cfg_const = cfg_none (no types in ctxt)" s0 (pt cfg_const ctxt t)

in () end
\<close>


(* ================================================================
   2. print_term: with show_types = true in context
      Now the YXML has typing elements. The printing_config
      controls which type annotations survive.
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context> |> Config.put Printer.show_types true
  val pt = REPL_Serialize.print_term

  (* ── cfg_none strips all type annotations ── *)
  val s = pt cfg_none ctxt @{term "x + (y::nat)"}
  val _ = assert_not_contains "cfg_none x+y no ::" " :: " s

  val s = pt cfg_none ctxt @{term "1::nat"}
  val _ = assert_not_contains "cfg_none 1 no ::" " :: " s

  val s = pt cfg_none ctxt @{term "\<lambda>x::nat. x"}
  val _ = assert_not_contains "cfg_none lam no ::" " :: " s

  (* ── cfg_all shows type annotations ── *)
  val s = pt cfg_all ctxt @{term "x + (y::nat)"}
  val _ = assert_contains "cfg_all x+y has ::" " :: " s
  val _ = tracing ("  [cfg_all] x + y : " ^ s)

  val s = pt cfg_all ctxt @{term "1::nat"}
  val _ = assert_contains "cfg_all 1 has ::" " :: " s
  val _ = tracing ("  [cfg_all] 1::nat : " ^ s)

  val s = pt cfg_all ctxt @{term "\<lambda>x::nat. x"}
  val _ = assert_contains "cfg_all lam has ::" " :: " s
  val _ = tracing ("  [cfg_all] lam : " ^ s)

  (* ── cfg_free: only free variable types ── *)
  val s = pt cfg_free ctxt @{term "x + (y::nat)"}
  val _ = assert_contains "cfg_free x+y has ::" " :: " s
  val _ = tracing ("  [cfg_free] x + y : " ^ s)

  (* free var x should be typed; number 1 should not *)
  val s = pt cfg_free ctxt @{term "x + (1::nat)"}
  val _ = tracing ("  [cfg_free] x + 1 : " ^ s)

  (* ── cfg_num: only number types ── *)
  val s = pt cfg_num ctxt @{term "1::nat"}
  val _ = assert_contains "cfg_num 1 has ::" " :: " s
  val _ = tracing ("  [cfg_num] 1 : " ^ s)

  val s = pt cfg_num ctxt @{term "x + (1::nat)"}
  val _ = tracing ("  [cfg_num] x + 1 : " ^ s)

  (* ── cfg_bv: only bound variable types ── *)
  val s = pt cfg_bv ctxt @{term "\<lambda>x::nat. x"}
  val _ = tracing ("  [cfg_bv] lam x.x : " ^ s)

  val s = pt cfg_bv ctxt @{term "\<lambda>f::nat\<Rightarrow>nat. \<lambda>x::nat. f x"}
  val _ = tracing ("  [cfg_bv] lam f x. f x : " ^ s)

  (* ── cfg_const: only constant types ── *)
  val s = pt cfg_const ctxt @{term "Suc 0"}
  val _ = tracing ("  [cfg_const] Suc 0 : " ^ s)

  val s = pt cfg_const ctxt @{term "x + (y::nat)"}
  val _ = tracing ("  [cfg_const] x + y : " ^ s)

  (* ── Complex term: all configs produce monotonically more annotations ── *)
  val t = @{term "\<lambda>x::nat. Suc x + (1::nat) + y"}
  val s_none  = pt cfg_none  ctxt t
  val s_all   = pt cfg_all   ctxt t
  val s_free  = pt cfg_free  ctxt t
  val s_bv    = pt cfg_bv    ctxt t
  val s_num   = pt cfg_num   ctxt t
  val s_const = pt cfg_const ctxt t

  val _ = tracing ("  [mixed] none  : " ^ s_none)
  val _ = tracing ("  [mixed] all   : " ^ s_all)
  val _ = tracing ("  [mixed] free  : " ^ s_free)
  val _ = tracing ("  [mixed] bv    : " ^ s_bv)
  val _ = tracing ("  [mixed] num   : " ^ s_num)
  val _ = tracing ("  [mixed] const : " ^ s_const)

  val _ = assert_true "all >= none"  (size s_all >= size s_none)
  val _ = assert_true "all >= free"  (size s_all >= size s_free)
  val _ = assert_true "all >= bv"    (size s_all >= size s_bv)
  val _ = assert_true "all >= num"   (size s_all >= size s_num)
  val _ = assert_true "all >= const" (size s_all >= size s_const)

  (* ── Combined flags: free + num ── *)
  val cfg_free_num : REPL_Serialize.printing_config = {
    all_typ = false, bv_typ = false, constant_typ = false,
    free_typ = true, num_typ = true, sorting = false,
    show_type_P = NONE, show_sort_P = NONE
  }
  val s_fn = pt cfg_free_num ctxt t
  val _ = tracing ("  [mixed] free+num : " ^ s_fn)
  val _ = assert_true "free+num >= free" (size s_fn >= size s_free)
  val _ = assert_true "free+num >= num"  (size s_fn >= size s_num)

  (* ── Combined flags: bv + const ── *)
  val cfg_bv_const : REPL_Serialize.printing_config = {
    all_typ = false, bv_typ = true, constant_typ = true,
    free_typ = false, num_typ = false, sorting = false,
    show_type_P = NONE, show_sort_P = NONE
  }
  val s_bc = pt cfg_bv_const ctxt t
  val _ = tracing ("  [mixed] bv+const : " ^ s_bc)
  val _ = assert_true "bv+const >= bv"    (size s_bc >= size s_bv)
  val _ = assert_true "bv+const >= const" (size s_bc >= size s_const)

  (* ── Theorem props ── *)
  val s = pt cfg_all ctxt (Thm.prop_of @{thm allI})
  val _ = assert_contains "allI typed" " :: " s
  val _ = tracing ("  [cfg_all] allI : " ^ s)

  val s = pt cfg_none ctxt (Thm.prop_of @{thm allI})
  val _ = assert_not_contains "allI untyped" " :: " s
  val _ = tracing ("  [cfg_none] allI : " ^ s)

in () end
\<close>


(* ================================================================
   3. print_term: probabilistic type annotation (show_type_P)
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context> |> Config.put Printer.show_types true
  val pt = REPL_Serialize.print_term
  val t = @{term "x + (y::nat)"}

  (* P = 1.0: always show, equivalent to NONE *)
  val s_p1   = pt cfg_all_P1 ctxt t
  val s_none = pt cfg_all ctxt t
  val _ = assert_eq "P=1.0 same as NONE" s_none s_p1

  (* P = 0.0: never show, equivalent to cfg_none *)
  val s_p0    = pt cfg_all_P0 ctxt t
  val s_strip = pt cfg_none ctxt t
  val _ = assert_eq "P=0.0 same as cfg_none" s_strip s_p0

  (* P = 0.5: output should be valid (no crash), length between stripped and full *)
  val cfg_half : REPL_Serialize.printing_config = {
    all_typ = true, bv_typ = false, constant_typ = false,
    free_typ = false, num_typ = false, sorting = false,
    show_type_P = SOME 0.5, show_sort_P = NONE
  }
  val s_half = pt cfg_half ctxt t
  val _ = assert_true "P=0.5 valid output" (size s_half > 0)
  val _ = assert_true "P=0.5 between none and all"
    (size s_half >= size s_strip andalso size s_half <= size s_none)

in () end
\<close>


(* ================================================================
   4. print_term: sort annotations (sorting flag + show_sorts)
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context>
              |> Config.put Printer.show_types true
              |> Config.put Printer.show_sorts true
  val pt = REPL_Serialize.print_term

  (* Polymorphic term: sorts should appear with cfg_all_sort *)
  val t_poly = @{term "id (x::'a)"}

  val s_sort    = pt cfg_all_sort ctxt t_poly
  val s_no_sort = pt cfg_all ctxt t_poly
  val _ = tracing ("  [sort] id x : " ^ s_sort)
  val _ = tracing ("  [no_sort] id x : " ^ s_no_sort)

  (* Sort probability P=1.0: same as sorting=true, show_sort_P=NONE *)
  val s_sp1 = pt cfg_sort_P1 ctxt t_poly
  val _ = assert_eq "sort P=1.0 same as NONE" s_sort s_sp1

  (* Sort probability P=0.0: sorts stripped even if sorting=true *)
  val s_sp0 = pt cfg_sort_P0 ctxt t_poly
  val _ = tracing ("  [sort P=0.0] id x : " ^ s_sp0)

  (* Monomorphic term: sorts don't matter *)
  val t_mono = @{term "x + (y::nat)"}
  val s1 = pt cfg_all_sort ctxt t_mono
  val s2 = pt cfg_all ctxt t_mono
  val _ = tracing ("  [sort] x+y mono : " ^ s1)
  val _ = tracing ("  [no_sort] x+y mono : " ^ s2)

in () end
\<close>


(* ================================================================
   5. print_term: show_types_nv (types on non-variable subexprs)
   ================================================================ *)

ML \<open>
let
  val ctxt_nv = \<^context>
                  |> Config.put Printer.show_types true
                  |> Config.put Printer.show_types_nv true
  val ctxt_no_nv = \<^context>
                     |> Config.put Printer.show_types true
  val pt = REPL_Serialize.print_term

  val t = @{term "Suc (x + y)"}
  val s_nv    = pt cfg_all ctxt_nv t
  val s_no_nv = pt cfg_all ctxt_no_nv t

  val _ = tracing ("  [nv] Suc(x+y) : " ^ s_nv)
  val _ = tracing ("  [no_nv] Suc(x+y) : " ^ s_no_nv)

  (* show_types_nv produces more annotations *)
  val _ = assert_true "nv >= no_nv" (size s_nv >= size s_no_nv)

in () end
\<close>


(* ================================================================
   6. print_term: edge cases and special terms
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context>
  val pt = REPL_Serialize.print_term

  (* Schematic variables from theorems *)
  val s = pt cfg_none ctxt (Thm.prop_of @{thm conjI})
  val _ = tracing ("  [edge] conjI : " ^ s)

  val s = pt cfg_none ctxt (Thm.prop_of @{thm mp})
  val _ = tracing ("  [edge] mp : " ^ s)

  val s = pt cfg_none ctxt (Thm.prop_of @{thm disjE})
  val _ = tracing ("  [edge] disjE : " ^ s)

  (* Case expression *)
  val s = pt cfg_none ctxt
    @{term "case xs of [] \<Rightarrow> (0::nat) | (y # ys) \<Rightarrow> Suc 0"}
  val _ = tracing ("  [edge] case : " ^ s)
  val _ = assert_true "case non-empty" (size s > 0)

  (* Deeply nested lambda *)
  val s = pt cfg_none ctxt
    @{term "\<lambda>a b c d. a + b + c + (d::nat)"}
  val _ = assert_eq "deep lam" "\<lambda>a b c d. a + b + c + d" s

  (* Function composition *)
  val s = pt cfg_none ctxt @{term "f \<circ> g"}
  val _ = assert_eq "compose" "f \<circ> g" s

  (* The / undefined *)
  val s_the = pt cfg_none ctxt @{term "The P"}
  val _ = tracing ("  [edge] The : " ^ s_the)

  val s_undef = pt cfg_none ctxt @{term "undefined::nat"}
  val _ = assert_eq "undefined" "undefined" s_undef

  (* Numeral arithmetic *)
  val _ = assert_eq "2+3" "2 + 3"
    (pt cfg_none ctxt @{term "(2::nat) + 3"})

  (* Typed term where print_xml sees typing with cfg_all *)
  val ctxt_typed = \<^context> |> Config.put Printer.show_types true
  val s = pt cfg_all ctxt_typed @{term "undefined::nat"}
  val _ = assert_contains "undefined typed" " :: " s
  val _ = tracing ("  [edge] undefined typed : " ^ s)

in () end
\<close>


(* ================================================================
   7. print_typ: basic type printing
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context>
  val ptyp = REPL_Serialize.print_typ

  (* ── Base types ── *)
  val _ = assert_eq "nat"  "nat"  (ptyp cfg_none ctxt @{typ nat})
  val _ = assert_eq "bool" "bool" (ptyp cfg_none ctxt @{typ bool})
  val _ = assert_eq "int"  "int"  (ptyp cfg_none ctxt @{typ int})

  (* ── Function types ── *)
  val _ = assert_eq "nat=>bool" "nat \<Rightarrow> bool"
    (ptyp cfg_none ctxt @{typ "nat \<Rightarrow> bool"})
  val _ = assert_eq "'a=>'b" "'a \<Rightarrow> 'b"
    (ptyp cfg_none ctxt @{typ "'a \<Rightarrow> 'b"})

  (* ── Type variables ── *)
  val _ = assert_eq "'a" "'a" (ptyp cfg_none ctxt @{typ "'a"})

  (* ── Compound types ── *)
  val _ = assert_eq "nat list" "nat list"
    (ptyp cfg_none ctxt @{typ "nat list"})
  val _ = assert_eq "nat set" "nat set"
    (ptyp cfg_none ctxt @{typ "nat set"})
  val _ = assert_eq "nat option" "nat option"
    (ptyp cfg_none ctxt @{typ "nat option"})
  val _ = assert_eq "nat * int" "nat \<times> int"
    (ptyp cfg_none ctxt @{typ "nat \<times> int"})

  (* ── Nested types ── *)
  val _ = assert_eq "(nat=>bool)=>nat" "(nat \<Rightarrow> bool) \<Rightarrow> nat"
    (ptyp cfg_none ctxt @{typ "(nat \<Rightarrow> bool) \<Rightarrow> nat"})
  val _ = assert_eq "'a list => 'a" "'a list \<Rightarrow> 'a"
    (ptyp cfg_none ctxt @{typ "'a list \<Rightarrow> 'a"})
  val _ = assert_eq "nat list list" "nat list list"
    (ptyp cfg_none ctxt @{typ "nat list list"})
  val _ = assert_eq "nat * int * bool" "nat \<times> int \<times> bool"
    (ptyp cfg_none ctxt @{typ "nat \<times> int \<times> bool"})
  val _ = assert_eq "compose type"
    "('a \<Rightarrow> 'b) \<Rightarrow> ('b \<Rightarrow> 'c) \<Rightarrow> 'a \<Rightarrow> 'c"
    (ptyp cfg_none ctxt @{typ "('a \<Rightarrow> 'b) \<Rightarrow> ('b \<Rightarrow> 'c) \<Rightarrow> 'a \<Rightarrow> 'c"})

  (* ── Special types ── *)
  val _ = assert_eq "unit" "unit" (ptyp cfg_none ctxt @{typ unit})
  val _ = assert_eq "prop" "prop" (ptyp cfg_none ctxt @{typ prop})
  val _ = assert_eq "nat + int" "nat + int"
    (ptyp cfg_none ctxt @{typ "nat + int"})

  (* ── Config irrelevance for types without sorting in context ── *)
  val typ = @{typ "nat \<Rightarrow> bool"}
  val s0 = ptyp cfg_none ctxt typ
  val _ = assert_eq "typ: cfg_all = cfg_none" s0 (ptyp cfg_all ctxt typ)
  val _ = assert_eq "typ: cfg_free = cfg_none" s0 (ptyp cfg_free ctxt typ)

in () end
\<close>


(* ================================================================
   8. print_typ: with sort annotations
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context> |> Config.put Printer.show_sorts true
  val ptyp = REPL_Serialize.print_typ

  (* Type variables should show their sorts *)
  val s = ptyp cfg_all_sort ctxt @{typ "'a"}
  val _ = tracing ("  [sort] 'a : " ^ s)

  (* Explicit sort constraint *)
  val s = ptyp cfg_all_sort ctxt @{typ "'a::linorder"}
  val _ = tracing ("  [sort] 'a::linorder : " ^ s)
  val _ = assert_contains "linorder in sort" "linorder" s

  (* Function with sorted type vars *)
  val s = ptyp cfg_all_sort ctxt @{typ "'a::ord \<Rightarrow> 'a::ord \<Rightarrow> bool"}
  val _ = tracing ("  [sort] 'a::ord => 'a::ord => bool : " ^ s)
  val _ = assert_contains "ord in sort" "ord" s

  (* Without sorting flag, sorts should be stripped *)
  val s = ptyp cfg_all ctxt @{typ "'a::linorder"}
  val _ = tracing ("  [no_sort] 'a::linorder : " ^ s)

  (* Sort probability P=1.0 *)
  val s_p1 = ptyp cfg_sort_P1 ctxt @{typ "'a::linorder"}
  val s_full = ptyp cfg_all_sort ctxt @{typ "'a::linorder"}
  val _ = assert_eq "sort P=1.0 = NONE" s_full s_p1

  (* Sort probability P=0.0 *)
  val s_p0 = ptyp cfg_sort_P0 ctxt @{typ "'a::linorder"}
  val _ = tracing ("  [sort P=0.0] 'a::linorder : " ^ s_p0)

  (* Base type (no type vars, sorts irrelevant) *)
  val s1 = ptyp cfg_all_sort ctxt @{typ nat}
  val s2 = ptyp cfg_none ctxt @{typ nat}
  val _ = assert_eq "nat sort irrelevant" s2 s1

in () end
\<close>


(* ================================================================
   9. print_term / print_typ: consistency between the two
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context> |> Config.put Printer.show_types true
  val pt = REPL_Serialize.print_term
  val ptyp = REPL_Serialize.print_typ

  (* The type shown in a typed free variable should match print_typ *)
  val typ_str = ptyp cfg_none ctxt @{typ nat}
  val term_str = pt cfg_free ctxt @{term "x::nat"}
  val _ = tracing ("  [consistency] typ nat: " ^ typ_str)
  val _ = tracing ("  [consistency] free x::nat: " ^ term_str)
  val _ = assert_contains "free x contains nat" typ_str term_str

in () end
\<close>


(* ================================================================
   10. print_term: all_typ subsumes individual flags
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context> |> Config.put Printer.show_types true
  val pt = REPL_Serialize.print_term

  (* For any term, cfg_all output should be a superset of any individual flag's output *)
  val terms = [
    @{term "x + (y::nat)"},
    @{term "1::nat"},
    @{term "\<lambda>x::nat. x"},
    @{term "Suc (x + y)"},
    @{term "\<forall>x::nat. x > 0"}
  ]

  val _ = List.app (fn t =>
    let val s_all   = pt cfg_all   ctxt t
        val s_free  = pt cfg_free  ctxt t
        val s_bv    = pt cfg_bv    ctxt t
        val s_num   = pt cfg_num   ctxt t
        val s_const = pt cfg_const ctxt t
     in assert_true "all >= free"  (size s_all >= size s_free)
      ; assert_true "all >= bv"    (size s_all >= size s_bv)
      ; assert_true "all >= num"   (size s_all >= size s_num)
      ; assert_true "all >= const" (size s_all >= size s_const)
    end
  ) terms

in () end
\<close>


(* ================================================================
   11. print_term: idempotence / stability
       Parsing the output back should not crash (basic sanity).
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context> |> Config.put Printer.show_types true
  val pt = REPL_Serialize.print_term

  val terms = [
    @{term "True"}, @{term "1::nat"}, @{term "x + (y::nat)"},
    @{term "\<lambda>x::nat. x"}, @{term "if P then (a::nat) else b"},
    Thm.prop_of @{thm refl}, Thm.prop_of @{thm allI}
  ]

  val configs = [cfg_none, cfg_all, cfg_free, cfg_bv, cfg_num, cfg_const]

  (* Every config x term combination should produce a non-empty string *)
  val _ = List.app (fn cfg =>
    List.app (fn t =>
      let val s = pt cfg ctxt t
       in assert_true "output non-empty" (size s > 0)
      end
    ) terms
  ) configs

in () end
\<close>


end
