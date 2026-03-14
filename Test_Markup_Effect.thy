theory Test_Markup_Effect
  imports Isa_REPL
begin

text \<open>
  Phenomenon: @{ML REPL_Serialize.print_term} with num_typ=true shows type
  annotations for numbers in jEdit but NOT in batch mode (isabelle build).

  Diagnostic: dump raw YXML, parsed XML trees, and print_term outputs
  across all combinations of show_markup / show_types / config flags.
  No assertions — purely observational. All results written to file.
\<close>

ML \<open>
val cfg_num : REPL_Serialize.printing_config = {
  all_typ = false, bv_typ = false, constant_typ = false,
  free_typ = false, num_typ = true, sorting = false,
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

val results : string list Unsynchronized.ref = Unsynchronized.ref []
fun log s = (tracing s; results := s :: !results)
\<close>


(* ================================================================
   1. Default show_markup value in this build mode
   ================================================================ *)

ML \<open>
let val v = Config.get \<^context> Printer.show_markup
 in log ("== Default Printer.show_markup = " ^ Bool.toString v)
end
\<close>


(* ================================================================
   2. Raw YXML / XML structure for 1::'a::one
      This is the key diagnostic: what does the YXML actually
      look like with markup=true vs markup=false?
   ================================================================ *)

ML \<open>
let
  val t = @{term "1::'a::one"}

  fun dump label ctxt =
    let val yxml = Syntax.string_of_term ctxt t
        val body = YXML.parse_body yxml
     in log ("  " ^ label ^ " raw YXML : " ^ yxml)
      ; log ("  " ^ label ^ " XML trees: " ^ String.concat (map XML.string_of body))
    end

  val _ = log "== Raw YXML / XML for (1::'a::one)"

  val _ = dump "markup=T types=T"
    (\<^context> |> Config.put Printer.show_markup true
               |> Config.put Printer.show_types true)

  val _ = dump "markup=T types=F"
    (\<^context> |> Config.put Printer.show_markup true
               |> Config.put Printer.show_types false)

  val _ = dump "markup=F types=T"
    (\<^context> |> Config.put Printer.show_markup false
               |> Config.put Printer.show_types true)

  val _ = dump "markup=F types=F"
    (\<^context> |> Config.put Printer.show_markup false
               |> Config.put Printer.show_types false)

  val _ = dump "default   types=T"
    (\<^context> |> Config.put Printer.show_types true)

  val _ = dump "default   types=F"
    (\<^context>)

in () end
\<close>


(* ================================================================
   3. Raw YXML / XML structure for x::nat (free variable, for
      comparison with the number case)
   ================================================================ *)

ML \<open>
let
  val t = @{term "x::nat"}

  fun dump label ctxt =
    let val yxml = Syntax.string_of_term ctxt t
        val body = YXML.parse_body yxml
     in log ("  " ^ label ^ " raw YXML : " ^ yxml)
      ; log ("  " ^ label ^ " XML trees: " ^ String.concat (map XML.string_of body))
    end

  val _ = log "== Raw YXML / XML for (x::nat)"

  val _ = dump "markup=T types=T"
    (\<^context> |> Config.put Printer.show_markup true
               |> Config.put Printer.show_types true)

  val _ = dump "markup=T types=F"
    (\<^context> |> Config.put Printer.show_markup true
               |> Config.put Printer.show_types false)

  val _ = dump "markup=F types=T"
    (\<^context> |> Config.put Printer.show_markup false
               |> Config.put Printer.show_types true)

in () end
\<close>


(* ================================================================
   4. print_term output: num_typ on 1::'a::one
      All 4 combinations of show_markup x show_types,
      with both num_typ=true and num_typ=false.
   ================================================================ *)

ML \<open>
let
  val pt = REPL_Serialize.print_term
  val t = @{term "1::'a::one"}

  fun test label ctxt =
    let val s_num  = pt cfg_num  ctxt t
        val s_none = pt cfg_none ctxt t
        val s_all  = pt cfg_all  ctxt t
     in log ("  " ^ label)
      ; log ("    num_typ  : " ^ s_num)
      ; log ("    cfg_none : " ^ s_none)
      ; log ("    all_typ  : " ^ s_all)
      ; log ("    num_typ selective: " ^ Bool.toString (s_num <> s_none))
      ; log ("    all_typ selective: " ^ Bool.toString (s_all <> s_none))
    end

  val _ = log "== print_term on (1::'a::one)"

  val _ = test "markup=T types=T"
    (\<^context> |> Config.put Printer.show_markup true
               |> Config.put Printer.show_types true)

  val _ = test "markup=T types=F"
    (\<^context> |> Config.put Printer.show_markup true
               |> Config.put Printer.show_types false)

  val _ = test "markup=F types=T"
    (\<^context> |> Config.put Printer.show_markup false
               |> Config.put Printer.show_types true)

  val _ = test "markup=F types=F"
    (\<^context> |> Config.put Printer.show_markup false
               |> Config.put Printer.show_types false)

  val _ = test "default types=T"
    (\<^context> |> Config.put Printer.show_types true)

  val _ = test "default (no changes)"
    (\<^context>)

in () end
\<close>


(* ================================================================
   5. print_term output: free_typ on x::nat (comparison)
   ================================================================ *)

ML \<open>
let
  val pt = REPL_Serialize.print_term
  val t = @{term "x::nat"}

  fun test label ctxt =
    let val s_free = pt cfg_free ctxt t
        val s_none = pt cfg_none ctxt t
        val s_all  = pt cfg_all  ctxt t
     in log ("  " ^ label)
      ; log ("    free_typ : " ^ s_free)
      ; log ("    cfg_none : " ^ s_none)
      ; log ("    all_typ  : " ^ s_all)
      ; log ("    free_typ selective: " ^ Bool.toString (s_free <> s_none))
      ; log ("    all_typ selective:  " ^ Bool.toString (s_all <> s_none))
    end

  val _ = log "== print_term on (x::nat)"

  val _ = test "markup=T types=T"
    (\<^context> |> Config.put Printer.show_markup true
               |> Config.put Printer.show_types true)

  val _ = test "markup=T types=F"
    (\<^context> |> Config.put Printer.show_markup true
               |> Config.put Printer.show_types false)

  val _ = test "markup=F types=T"
    (\<^context> |> Config.put Printer.show_markup false
               |> Config.put Printer.show_types true)

  val _ = test "default types=T"
    (\<^context> |> Config.put Printer.show_types true)

in () end
\<close>


(* ================================================================
   6. Multiple number forms
   ================================================================ *)

ML \<open>
let
  val pt = REPL_Serialize.print_term

  val ctxt_on = \<^context>
    |> Config.put Printer.show_markup true
    |> Config.put Printer.show_types true

  val cases = [
    ("0::nat",    @{term "0::nat"}),
    ("1::nat",    @{term "1::nat"}),
    ("1::'a",     @{term "1::'a::one"}),
    ("42::nat",   @{term "42::nat"}),
    ("0::int",    @{term "0::int"})
  ]

  val _ = log "== Multiple numbers (markup=T types=T)"

  val _ = List.app (fn (label, t) =>
    let val s_num  = pt cfg_num  ctxt_on t
        val s_none = pt cfg_none ctxt_on t
        val s_all  = pt cfg_all  ctxt_on t
     in log ("  " ^ label)
      ; log ("    num_typ  : " ^ s_num)
      ; log ("    cfg_none : " ^ s_none)
      ; log ("    all_typ  : " ^ s_all)
      ; log ("    num selective: " ^ Bool.toString (s_num <> s_none))
    end
  ) cases

in () end
\<close>


(* ================================================================
   7. Mixed term: all config flags
   ================================================================ *)

ML \<open>
let
  val pt = REPL_Serialize.print_term
  val t = @{term "\<lambda>x::nat. Suc x + 1 + y"}

  val ctxt = \<^context>
    |> Config.put Printer.show_markup true
    |> Config.put Printer.show_types true

  val _ = log "== Mixed term (lambda x. Suc x + 1 + y), markup=T types=T"
  val _ = log ("  cfg_none  : " ^ pt cfg_none  ctxt t)
  val _ = log ("  num_typ   : " ^ pt cfg_num   ctxt t)
  val _ = log ("  free_typ  : " ^ pt cfg_free  ctxt t)
  val _ = log ("  bv_typ    : " ^ pt cfg_bv    ctxt t)
  val _ = log ("  const_typ : " ^ pt cfg_const ctxt t)
  val _ = log ("  all_typ   : " ^ pt cfg_all   ctxt t)

in () end
\<close>


(* ================================================================
   8. YXML for mixed term (to see typing element structure)
   ================================================================ *)

ML \<open>
let
  val t = @{term "\<lambda>x::nat. Suc x + 1 + y"}

  val ctxt = \<^context>
    |> Config.put Printer.show_markup true
    |> Config.put Printer.show_types true

  val yxml = Syntax.string_of_term ctxt t
  val body = YXML.parse_body yxml

  val _ = log "== YXML for mixed term (markup=T types=T)"
  val _ = log ("  raw YXML : " ^ yxml)
  val _ = log ("  XML trees: " ^ String.concat (map XML.string_of body))

in () end
\<close>


(* ================================================================
   9. Stress test: print all global facts with print_term
   ================================================================ *)

ML \<open>
let
  val ctxt = \<^context>
  val thy = Proof_Context.theory_of ctxt
  val facts = Global_Theory.facts_of thy
  val all = Facts.fold_static (fn (name, thms) => fn acc => (name, thms) :: acc) facts []
  val total = length all
  val _ = log ("== Stress test: printing all " ^ string_of_int total ^ " global facts with print_term")

  val cfg : REPL_Serialize.printing_config = {
    all_typ = false, bv_typ = true, constant_typ = false,
    free_typ = false, num_typ = true, sorting = false,
    show_type_P = NONE, show_sort_P = NONE
  }

  val failed = Unsynchronized.ref ([] : (string * string) list)
  val succeeded = Unsynchronized.ref 0
  val out_path = Path.explode "/tmp/test_print_term_all_facts.txt"
  val out = Unsynchronized.ref ([] : string list)

  val _ = List.app (fn (name, thms) =>
    List.app (fn thm =>
      let val t = Thm.prop_of thm
          val s = REPL_Serialize.print_term cfg ctxt t
       in out := (name ^ ": " ^ s) :: !out;
          succeeded := !succeeded + 1
      end
          handle Fail msg =>
            failed := (name, "Fail: " ^ msg) :: !failed
               | Match =>
            failed := (name, "Match") :: !failed
               | ERROR msg =>
            failed := (name, "ERROR: " ^ msg) :: !failed
      ) thms) all

  val _ = File.write out_path (String.concatWith "\n" (rev (!out)) ^ "\n")
  val _ = log ("  Succeeded: " ^ string_of_int (!succeeded))
  val _ = log ("  Failed:    " ^ string_of_int (length (!failed)))
  val _ = log ("  Output:    " ^ Path.implode out_path)
  val _ = List.app (fn (name, msg) =>
    log ("    FAIL " ^ name ^ ": " ^ msg)) (List.take (!failed, Int.min (50, length (!failed))))

in () end
\<close>


(* ================================================================
   Write all results to file
   ================================================================ *)

ML \<open>
let
  val lines = rev (!results)
  val content = String.concatWith "\n" lines ^ "\n"
  val path = Path.explode  "/tmp/test_markup_effect_results.txt"
  val _ = File.write path content
  val _ = tracing ("Results written to " ^ Path.implode path)
in () end
\<close>

end
