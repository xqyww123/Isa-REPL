signature REPL_SERIALIZE = sig

val message_type_packer   : REPL.message_type MessagePackBinIO.Pack.packer
val message_packer        : REPL.message MessagePackBinIO.Pack.packer
val flags_packer          : REPL.flags MessagePackBinIO.Pack.packer
val command_output_packer : REPL.command_output MessagePackBinIO.Pack.packer
val command_outputs_packer: REPL.command_outputs MessagePackBinIO.Pack.packer

(* Re-exported from RPC_Pretty for backward compatibility *)
type pp_name = RPC_Pretty.pp_name
type printing_config = RPC_Pretty.printing_config

val pack_raw_term : term MessagePackBinIO.Pack.packer
val unpack_raw_term : term MessagePackBinIO.Unpack.unpacker
val pack_raw_typ : typ MessagePackBinIO.Pack.packer
val unpack_raw_typ : typ MessagePackBinIO.Unpack.unpacker

val string_of_term : pp_name -> Context.generic -> term -> string
val term_string : Context.generic -> term MessagePackBinIO.Pack.packer
val s_expression : term -> string
val s_expression_packer : term MessagePackBinIO.Pack.packer
val pack_context : pp_name -> Context.generic -> REPL.context MessagePackBinIO.Pack.packer
val s_expr_typ : typ -> string list -> string list

val term_packer : pp_name -> Context.generic -> term MessagePackBinIO.Pack.packer
val typ_packer  : pp_name -> Context.generic -> typ  MessagePackBinIO.Pack.packer
val pos_packer  : Position.T MessagePackBinIO.Pack.packer

val print_term   : printing_config -> Proof.context -> term -> string
val print_typ    : printing_config -> Proof.context -> typ  -> string

end

structure REPL_Serialize : REPL_SERIALIZE = struct
open REPL

(* Re-export from RPC_Pretty *)
type pp_name = RPC_Pretty.pp_name
type printing_config = RPC_Pretty.printing_config

val pack_raw_term = RPC_Pretty.pack_raw_term
val unpack_raw_term = RPC_Pretty.unpack_raw_term
val pack_raw_typ = RPC_Pretty.pack_raw_typ
val unpack_raw_typ = RPC_Pretty.unpack_raw_typ
val string_of_term = RPC_Pretty.string_of_term
val term_string = RPC_Pretty.term_string
val s_expression = RPC_Pretty.s_expression
val s_expression_packer = RPC_Pretty.s_expression_packer
val s_expr_typ = RPC_Pretty.s_expr_typ
val term_packer = RPC_Pretty.term_packer
val typ_packer = RPC_Pretty.typ_packer
val pos_packer = RPC_Pretty.pos_packer
val print_term = RPC_Pretty.print_term
val print_typ = RPC_Pretty.print_typ

(* REPL-specific serializers *)

local open MessagePackBinIO.Pack in

fun flags_packer {is_toplevel, is_theory, is_proof, has_goal}
      = packTuple4 (packBool, packBool, packBool, packBool)
                   (is_toplevel, is_theory, is_proof, has_goal)

fun message_type_packer NORMAL  = packInt 0
  | message_type_packer TRACING = packInt 1
  | message_type_packer WARNING = packInt 2

val message_packer = packPair (message_type_packer, packString)

fun command_output_packer {
        command : string,
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
    (   command,
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

fun pack_context s_expr ctxt =
  let val thm = RPC_Pretty.thm_packer s_expr ctxt
      val typ = typ_packer s_expr ctxt
      val term= term_packer s_expr ctxt
      open MessagePackBinIO.Pack
      val pack_var = packString o RPC_Pretty.string_of_var
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
