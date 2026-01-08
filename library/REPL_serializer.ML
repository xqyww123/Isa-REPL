signature REPL_SERIALIZE = sig

val message_type_packer   : REPL.message_type MessagePackBinIO.Pack.packer
val message_packer        : REPL.message MessagePackBinIO.Pack.packer
val flags_packer          : REPL.flags MessagePackBinIO.Pack.packer
val command_output_packer : REPL.command_output MessagePackBinIO.Pack.packer
val command_outputs_packer: REPL.command_outputs MessagePackBinIO.Pack.packer

type pp_name = string

val string_of_term : pp_name -> Context.generic -> term -> string
val term_string : Context.generic -> term MessagePackBinIO.Pack.packer
val s_expression : term -> string
val s_expression_packer : term MessagePackBinIO.Pack.packer
val pack_context : pp_name -> Context.generic -> REPL.context MessagePackBinIO.Pack.packer
val s_expr_typ : typ -> string list -> string list

val term_packer : pp_name -> Context.generic -> term MessagePackBinIO.Pack.packer
val typ_packer  : pp_name -> Context.generic -> typ  MessagePackBinIO.Pack.packer
val pos_packer  : Position.T MessagePackBinIO.Pack.packer

type printing_config = {
        all_typ: bool, bv_typ: bool, constant_typ: bool,
        free_typ: bool, num_typ: bool, sorting: bool,
        show_type_P: real option (*probabilistically show types, under the control of the above flags*),
        show_sort_P: real option (*probabilistically show sorts, under the control of the above flags*)
     }

val print_term   : printing_config -> Proof.context -> term -> string
val print_typ    : printing_config -> Proof.context -> typ  -> string

end

structure REPL_Serialize : REPL_SERIALIZE = struct
open REPL

type printing_config = {
        all_typ: bool, bv_typ: bool, constant_typ: bool,
        free_typ: bool, num_typ: bool, sorting: bool,
        show_type_P: real option (*probabilistically show types, under the control of the above flags*),
        show_sort_P: real option (*probabilistically show sorts, under the control of the above flags*)
     }
exception XML_DUMP_FAIL of XML.tree

fun is_number s =
  if s = "."
  then false
  else let
      val len = String.size s
      val i = Unsynchronized.ref 0
      val ret = Unsynchronized.ref true
   in while !ret andalso !i < len do
        let val c = String.sub (s, !i)
         in ( if c = #"." orelse c = #"-" orelse c = #"~" orelse Char.isDigit c
            then ()
            else ret := false )
          ; i := !i + 1
        end
     ; !ret
  end


fun random () =
  let val m = 0w2147483647  (* 2^31 - 1 *)
      val a = 0w16807       (* multiplier *)
      val seed = Unsynchronized.ref (a * Word64.fromLargeInt (Time.toNanoseconds (Time.now())) mod m)
  in fn () =>
        let val s = !seed
            val next = (a * s) mod m
         in seed := next;
            Real.fromInt (Word64.toInt next) / 2147483647.0
        end
  end


fun print_xml {bv_typ, num_typ, free_typ, constant_typ, all_typ, sorting, show_type_P, show_sort_P} xml =
  let val show_type =
            case show_type_P of SOME P => let val rand = random ()
                                           in fn () => rand () <= P
                                          end
                              | NONE => K true
      val bv_typ = bv_typ orelse all_typ
      val sorting =
            if sorting
            then (case show_sort_P of SOME P => let val rand = random ()
                                                 in fn () => rand () <= P
                                                end
                                    | NONE => K true)
            else K false
      val num_typ = num_typ orelse all_typ
      val free_typ = free_typ orelse all_typ
      val constant_typ = constant_typ orelse all_typ

      open XML
      type ty = tree
      datatype IR = TEXT of string
                  | TYPING of ty * IR list
                  | SORTING of ty * IR list
                  | NUMBER of string
                  | FREE of string
                  | BOUND of string
                  | CONSTANT of {name: string, full_name: string}
                  | CLASS of {name: string, full_name: string}
                  | TYPE  of {name: string, full_name: string}

      fun one_str (Elem (("block", _), [x])) = one_str x
        | one_str (Elem (("delimiter", _), [x])) = one_str x
        | one_str (Elem (("literal", _), [x])) = one_str x
        | one_str (Text s) = s
        | one_str x = raise XML_DUMP_FAIL x

      val lookup = AList.lookup (op =)
      val lookup' = the_default "" oo lookup
      fun dump_xml (Text s) ret = 
            if is_number s
            then NUMBER s :: ret
            else TEXT s :: ret
        | dump_xml (Elem (("break", _), _)) ret = TEXT " " :: ret
        | dump_xml (Elem (("tfree", _), [x])) ret = FREE (one_str x) :: ret
        | dump_xml (Elem (("free", _), [x])) ret = FREE (one_str x) :: ret
        | dump_xml (Elem (("bound", _), [x])) ret = BOUND (one_str x) :: ret
        | dump_xml (origin as Elem (("entity", attrs), [x])) ret =
           (case lookup attrs "kind"
              of SOME "class" => CLASS {name = one_str x, full_name = lookup' attrs "name"}
               | SOME "constant" =>
                    let val name = one_str x
                     in case name
                     of "0" => NUMBER "0"
                      | "1" => NUMBER "1"
                      | _ => CONSTANT {name = name, full_name = lookup' attrs "name"}
                    end
               | SOME "type_name" => TYPE {name = one_str x, full_name = lookup' attrs "name"}
               | _ => raise XML_DUMP_FAIL origin
           ) :: ret
        | dump_xml (Elem (("xml_elem", [("xml_name", "typing")]), [typ, term])) ret =
            TYPING (typ, dump_xml term []) :: ret
        | dump_xml (Elem (("xml_elem", [("xml_name", "sorting")]), [typ, term])) ret =
            SORTING (typ, dump_xml term []) :: ret
        | dump_xml (Elem (_, children)) ret = fold dump_xml children ret

      fun dump_ir ir =
        let fun pass [] ret = ret
              | pass (TYPING (ty, [NUMBER tm]) :: oth) ret =
                  if num_typ andalso show_type ()
                  then "(" :: tm :: " :: " :: dump_ir (dump_xml ty []) @ ")"
                           :: pass oth ret
                  else tm :: pass oth ret
              | pass (TYPING (ty, [FREE tm]) :: oth) ret =
                  if free_typ andalso show_type ()
                  then "(" :: tm :: " :: " :: dump_ir (dump_xml ty []) @ ")"
                    :: pass oth ret
                  else tm :: pass oth ret
              | pass (TYPING (ty, [CONSTANT {name, ...}]) :: oth) ret =
                  if constant_typ andalso show_type ()
                  then "(" :: name :: " :: " :: dump_ir (dump_xml ty []) @ ")"
                    :: pass oth ret
                  else name :: pass oth ret
              | pass (TYPING (ty, [BOUND tm]) :: CONSTANT {name=".",...} :: oth) ret =
                  if bv_typ andalso show_type ()
                  then "(" :: tm :: " :: " :: dump_ir (dump_xml ty []) @ ")."
                           :: pass oth ret
                  else tm :: "." :: pass oth ret
              | pass (TYPING (ty, [BOUND tm]) :: TEXT "." :: oth) ret =
                  if bv_typ andalso show_type ()
                  then "(" :: tm :: " :: " :: dump_ir (dump_xml ty []) @ ")."
                           :: pass oth ret
                  else tm :: "." :: pass oth ret
              | pass (TEXT s :: oth) ret = s :: pass oth ret
              | pass (TYPING (ty, tm) :: oth) ret =
                  if all_typ andalso show_type ()
                  then "(" :: pass tm [] @ " :: " :: dump_ir (dump_xml ty []) @ ")"
                           :: pass oth ret
                  else pass (tm @ oth) ret
              | pass (SORTING (s, tm) :: oth) ret =
                  if sorting ()
                  then "(" :: pass tm [] @ " :: " :: dump_ir (dump_xml s []) @ ")"
                           :: pass oth ret
                  else pass (tm @ oth) ret
              | pass (NUMBER s :: oth) ret = s :: pass oth ret
              | pass (FREE s :: oth) ret = s :: pass oth ret
              | pass (BOUND s :: oth) ret = s :: pass oth ret
              | pass (CONSTANT {name, ...} :: oth) ret = name :: pass oth ret
              | pass (CLASS {name, ...} :: oth) ret = name :: pass oth ret
              | pass (TYPE {name, ...} :: oth) ret = name :: pass oth ret
         in pass (rev ir) []
        end
(*      and dump_str tree = dump_ir (rev (dump_xml tree)) *)
   in String.concat (dump_ir (dump_xml xml []))
  end

fun print_term cfg ctxt term = print_xml cfg (YXML.parse (Syntax.string_of_term ctxt term))
fun print_typ  cfg ctxt term = print_xml cfg (YXML.parse (Syntax.string_of_typ  ctxt term))


type pp_name = string

local open MessagePackBinIO.Pack in

fun flags_packer {is_toplevel, is_theory, is_proof, has_goal}
      = packTuple4 (packBool, packBool, packBool, packBool)
                   (is_toplevel, is_theory, is_proof, has_goal)

fun message_type_packer NORMAL  = packInt 0
  | message_type_packer TRACING = packInt 1
  | message_type_packer WARNING = packInt 2

val message_packer = packPair (message_type_packer, packString)

fun pos_packer pos =
  let open MessagePackBinIO.Unpack MessagePackBinIO.Pack
      val {line, offset, end_offset, props} = Position.dest pos
      val {label, file, id} = props
   in packTuple4 (packInt, packInt, packInt, packTuple3 (packString, packString, packString))
      (line, offset, end_offset, (label, file, id))
  end

fun command_output_packer {
        command_name : string,
        output : message list, (*text printed in Isabelle's output panel*)
        latex  : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        plugin_output: (plugin_name * raw_packer) list,
        errors : string list,
        range  : Position.T * Position.T
} = packTuple9 (packString,
                packList message_packer,
                packOption (packString o REPL.trim_makrup o YXML.string_of_body),
                flags_packer,
                packInt,
                packString,
                packPairList (packString, I),
                packList packString,
                packPair (pos_packer, pos_packer))
    (   command_name,
        output : message list, (*text printed in Isabelle's output panel*)
        latex  : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        plugin_output: (plugin_name * raw_packer) list,
        errors : string list,
        range)


type command_outputs = {
        outputs: command_output list,
        error : string option
}

fun command_outputs_packer {
        outputs: command_output list option,
        error : string option
} = packPair (packOption (packList command_output_packer),
              packOption packString)
    (   outputs: command_output list option,
        error : string option     )


fun string_of_var (s,i) =
      if i = ~1 then s
      else if size(s) = 0 orelse Char.isDigit (String.sub (s, size(s)-1))
      then "?" ^ s ^ "." ^ string_of_int i
      else "?" ^ s  ^ string_of_int i

val pack_var = packString o string_of_var

fun term_string ctxt =
  packString o REPL.trim_makrup o Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt

fun s_expr_typ (TFree (name, sort)) ret = "(var " :: name :: fold_rev (fn C => fn L => " "::C::L) sort (")"::ret)
  | s_expr_typ (TVar  (name, sort)) ret = "(var " :: string_of_var name :: fold_rev (fn C => fn L => " "::C::L) sort (")"::ret)
  | s_expr_typ (Type  (name, typs)) ret =
      if null typs
      then name::ret
      else "(" :: name :: fold_rev (fn T => fn L => " " :: s_expr_typ T L) typs (")"::ret)

fun s_expr ret bvs ctxt term =
  let val (head, args) = Term.strip_comb term
      val nopara = null args andalso (case head of Bound _ => true | _ => false)
      val ret = if nopara then ret else ")" :: ret
   in (
    case head
      of Const (name, ty) => (name :: " " :: s_expr_typ ty (out_args ret bvs ctxt args))
       | Free (name, ty) => ("var " :: name :: " " :: s_expr_typ ty (out_args ret bvs ctxt args))
       | Var (name, ty) => ("var " :: string_of_var name :: " " :: s_expr_typ ty (out_args ret bvs ctxt args))
       | Abs (triple as (name, ty,body)) =>
          if null args
          then let val (name',ctxt') = Name.variant name ctxt
                in ("(\<lambda> " :: name :: " " :: s_expr_typ ty (" " :: s_expr (")"::ret) (name'::bvs) ctxt' body))
               end
          else s_expr (out_args ret bvs ctxt args) bvs ctxt (Abs triple)
       | Bound i => (nth bvs i :: " " :: out_args ret bvs ctxt args)
       | _ $ _ => error "impossible")
   |> (fn L => if nopara then L else "(" :: L)
  end
and out_args ret bvs ctxt args = fold_rev (fn x => fn ret => (" " :: s_expr ret bvs ctxt x)) args ret

fun s_expression term = String.concat (s_expr [] [] Name.context term)
val s_expression_packer = packString o s_expression

fun string_of_term "sexpr" = (fn _ => s_expression)
  | string_of_term "natural" = (fn ctxt =>
      let val ctxt = Config.put_generic Printer.show_markup false ctxt
       in Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt
       #> REPL.trim_makrup
          (*The format is determined by the given context*)
      end)
  | string_of_term "oridinary" = (fn ctxt =>
      let val ctxt = ctxt
                |> Config.put_generic Printer.show_types false
                |> Config.put_generic Printer.show_sorts false
                |> Config.put_generic Printer.show_types_nv false
                |> Config.put_generic Printer.show_markup false
                |> Config.put_generic Printer.show_structs false
                |> Config.put_generic Printer.show_question_marks true
                |> Config.put_generic Printer.show_brackets false
       in Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt
       #> REPL.trim_makrup
      end)
  | string_of_term "pretty" = string_of_term "oridinary"
  | string_of_term "type" = (fn ctxt =>
      let val ctxt = ctxt
                |> Config.put_generic Printer.show_types true
                |> Config.put_generic Printer.show_sorts false
                |> Config.put_generic Printer.show_types_nv false
                |> Config.put_generic Printer.show_markup false
                |> Config.put_generic Printer.show_structs false
                |> Config.put_generic Printer.show_question_marks true
                |> Config.put_generic Printer.show_brackets false
       in Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt
       #> REPL.trim_makrup
      end)
  | string_of_term "typed_pretty" = string_of_term "type"
  | string_of_term "type_sort" = (fn ctxt =>
      let val ctxt = ctxt
                |> Config.put_generic Printer.show_types true
                |> Config.put_generic Printer.show_sorts false
                |> Config.put_generic Printer.show_types_nv false
                |> Config.put_generic Printer.show_markup false
                |> Config.put_generic Printer.show_structs false
                |> Config.put_generic Printer.show_question_marks true
                |> Config.put_generic Printer.show_brackets false
       in Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt
       #> REPL.trim_makrup
      end)
  | string_of_term "type_nv" = (fn ctxt =>
      let val ctxt = ctxt
                |> Config.put_generic Printer.show_types true
                |> Config.put_generic Printer.show_sorts false
                |> Config.put_generic Printer.show_types_nv true
                |> Config.put_generic Printer.show_markup false
                |> Config.put_generic Printer.show_structs false
                |> Config.put_generic Printer.show_question_marks true
                |> Config.put_generic Printer.show_brackets false
       in Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt
       #> REPL.trim_makrup
      end)
  | string_of_term "typed-nv_pretty" = string_of_term "type_nv"
  | string_of_term "T4S4" =
      let val rand = random ()
       in fn ctxt =>
      let val show_type = rand () <= 0.4
          val show_sort = show_type andalso rand () <= 0.4
          val ctxt = ctxt
                |> Config.put_generic Printer.show_types show_type
                |> Config.put_generic Printer.show_sorts show_sort
                |> Config.put_generic Printer.show_types_nv false
                |> Config.put_generic Printer.show_markup false
                |> Config.put_generic Printer.show_structs false
                |> Config.put_generic Printer.show_question_marks true
                |> Config.put_generic Printer.show_brackets false
       in Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt
       #> REPL.trim_makrup
      end
      end
  | string_of_term "T4S4nv" =
      let val rand = random ()
       in fn ctxt =>
      let val show_type = rand () <= 0.4
          val show_sort = show_type andalso rand () <= 0.4
          val ctxt = ctxt
                |> Config.put_generic Printer.show_types show_type
                |> Config.put_generic Printer.show_sorts show_sort
                |> Config.put_generic Printer.show_types_nv show_type
                |> Config.put_generic Printer.show_markup false
                |> Config.put_generic Printer.show_structs false
                |> Config.put_generic Printer.show_question_marks true
                |> Config.put_generic Printer.show_brackets false
       in Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt
       #> REPL.trim_makrup
      end
      end
  | string_of_term "T2S3" =
      let val rand = random ()
       in fn ctxt =>
      let val show_type = rand () <= 0.2
          val show_sort = show_type andalso rand () <= 0.3
          val ctxt = ctxt
                |> Config.put_generic Printer.show_types show_type
                |> Config.put_generic Printer.show_sorts show_sort
                |> Config.put_generic Printer.show_types_nv false
                |> Config.put_generic Printer.show_markup false
                |> Config.put_generic Printer.show_structs false
                |> Config.put_generic Printer.show_question_marks true
                |> Config.put_generic Printer.show_brackets false
       in Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt
       #> REPL.trim_makrup
      end
      end
  | string_of_term "T2S3nv" =
      let val rand = random ()
       in fn ctxt =>
      let val show_type = rand () <= 0.2
          val show_sort = show_type andalso rand () <= 0.3
          val ctxt = ctxt
                |> Config.put_generic Printer.show_types show_type
                |> Config.put_generic Printer.show_sorts show_sort
                |> Config.put_generic Printer.show_types_nv show_type
                |> Config.put_generic Printer.show_markup false
                |> Config.put_generic Printer.show_structs false
                |> Config.put_generic Printer.show_question_marks true
                |> Config.put_generic Printer.show_brackets false
       in Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt
       #> REPL.trim_makrup
      end
      end
  | string_of_term name = (fn _ =>
      raise REPL_fail ("Unknown term printer " ^ name
              ^ ". Unknown printers: ['sexpr', 'pretty', 'typed_pretty']"))
  

fun term_packer "sexpr" _ = s_expression_packer
  | term_packer "pretty" ctxt = term_string ctxt
  | term_packer "typed-nv_pretty" ctxt =
      let val ctxt = Config.put_generic Printer.show_types true ctxt
                  |> Config.put_generic Printer.show_types_nv true
       in term_string ctxt
      end
  | term_packer "typed_pretty" ctxt =
      let val ctxt = Config.put_generic Printer.show_types true ctxt
       in term_string ctxt
      end
  | term_packer name _ =
      raise REPL_fail ("Unknown term printer " ^ name
              ^ ". Unknown printers: ['sexpr', 'pretty', 'typed_pretty']")
  
fun pretty_typ ctxt =
      packString o REPL.trim_makrup o Context.cases Syntax.string_of_typ_global Syntax.string_of_typ ctxt

fun typ_packer "sexpr" _ = (fn typ => packString (String.concat (s_expr_typ typ [])))
  | typ_packer "pretty" ctxt = pretty_typ ctxt
  | typ_packer "typed_pretty" ctxt = pretty_typ ctxt
  | typ_packer "typed-nv_pretty" ctxt = pretty_typ ctxt
  | typ_packer name _ =
      raise REPL_fail ("Unknown term printer " ^ name ^ ". Unknown printers: ['sexpr', 'pretty']")

fun thm_packer s_expr ctxt = term_packer s_expr ctxt o Thm.prop_of



fun pack_context s_expr ctxt =
  let val thm = thm_packer s_expr ctxt
      val typ = typ_packer s_expr ctxt
      val term= term_packer s_expr ctxt
   in fn ({
        local_facts: (string * thm list) list,
        assumptions: thm list,
        bindings   : (typ * term) Vartab.table (*bindings introduced by `let ?x = <...>`*),
        fixed_terms: typ Vartab.table * sort Vartab.table,
        goals      : cterm list
      } : context) =>
    packTuple5 (
        packPairList (packString, packList thm),
        packList thm,
        packPairList (pack_var, packPair (typ, term)) o Vartab.dest,
        packPair (packPairList (pack_var, typ) o Vartab.dest, packPairList (pack_var, packList packString) o Vartab.dest),
        packList (term o Thm.term_of))
      ( local_facts: (string * thm list) list,
        assumptions: thm list,
        bindings   : (typ * term) Vartab.table (*bindings introduced by `let ?x = <...>`*),
        fixed_terms: typ Vartab.table * sort Vartab.table,
        goals      : cterm list)
  end

end


end
