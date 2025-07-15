signature REPL_SERIALIZE = sig

val message_type_packer   : REPL.message_type MessagePackBinIO.Pack.packer
val message_packer        : REPL.message MessagePackBinIO.Pack.packer
val flags_packer          : REPL.flags MessagePackBinIO.Pack.packer
val command_output_packer : REPL.command_output MessagePackBinIO.Pack.packer
val command_outputs_packer: REPL.command_outputs MessagePackBinIO.Pack.packer

val term_string : Context.generic -> term MessagePackBinIO.Pack.packer
val s_expression : term -> string
val s_expression_packer : term MessagePackBinIO.Pack.packer
val pack_context : bool -> Context.generic -> REPL.context MessagePackBinIO.Pack.packer
val s_expr_typ : typ -> string list -> string list
val pp_of : Context.generic -> string -> term MessagePackBinIO.Pack.packer

end

structure REPL_Serialize : REPL_SERIALIZE = struct
open REPL

local open MessagePackBinIO.Pack in

fun flags_packer {is_toplevel, is_theory, is_proof, has_goal}
      = packTuple4 (packBool, packBool, packBool, packBool)
                   (is_toplevel, is_theory, is_proof, has_goal)

fun message_type_packer NORMAL  = packInt 0
  | message_type_packer TRACING = packInt 1
  | message_type_packer WARNING = packInt 2

val message_packer = packPair (message_type_packer, packString)


fun command_output_packer {
        command_name : string,
        output : message list, (*text printed in Isabelle's output panel*)
        latex  : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        plugin_output: (plugin_name * raw_packer) list,
        errors : string list
} = packTuple8 (packString,
                packList message_packer,
                packOption (packString o REPL.trim_makrup o YXML.string_of_body),
                flags_packer,
                packInt,
                packString,
                packPairList (packString, I),
                packList packString)
    (   command_name,
        output : message list, (*text printed in Isabelle's output panel*)
        latex  : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        plugin_output: (plugin_name * raw_packer) list,
        errors : string list    )


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

fun term_packer s_expr ctxt =
      if s_expr then s_expression_packer else term_string ctxt
fun pretty_typ ctxt =
      packString o REPL.trim_makrup o Context.cases Syntax.string_of_typ_global Syntax.string_of_typ ctxt
fun typ_packer s_expr ctxt typ =
      if s_expr
      then packString (String.concat (s_expr_typ typ []))
      else pretty_typ ctxt typ
fun thm_packer s_expr ctxt = term_packer s_expr ctxt o Thm.prop_of



fun pack_context s_expr ctxt ({
  local_facts: (string * thm list) list,
  assumptions: thm list,
  bindings   : (typ * term) Vartab.table (*bindings introduced by `let ?x = <...>`*),
  fixed_terms: typ Vartab.table * sort Vartab.table,
  goals      : cterm list
} : context) =
  let val thm = thm_packer s_expr ctxt
      val typ = typ_packer s_expr ctxt
      val term= term_packer s_expr ctxt
   in packTuple5 (
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

fun pp_of _ "sexpr" = s_expression_packer
  | pp_of ctxt "pretty" = term_string ctxt
  | pp_of _ name =
      raise REPL_fail ("Unknown term printer " ^ name ^ ". Unknown printers: ['sexpr', 'pretty']")
  

end
