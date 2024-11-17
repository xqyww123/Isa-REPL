signature REPL_SERIALIZE = sig

val message_type_packer   : REPL.message_type MessagePackBinIO.Pack.packer
val message_packer        : REPL.message MessagePackBinIO.Pack.packer
val flags_packer          : REPL.flags MessagePackBinIO.Pack.packer
val command_output_packer : REPL.command_output MessagePackBinIO.Pack.packer
val command_outputs_packer: REPL.command_outputs MessagePackBinIO.Pack.packer

val term_string : Context.generic -> term MessagePackBinIO.Pack.packer
val s_expression : term -> string
val s_expression_packer : term MessagePackBinIO.Pack.packer

end

structure REPL_Serialize : REPL_SERIALIZE = struct
open REPL

local open MessagePackBinIO.Pack in

fun flags_packer {is_toplevel, is_theory, is_proof}
      = packTuple3 (packBool, packBool, packBool)
                   (is_toplevel, is_theory, is_proof)

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

fun term_string ctxt =
  packString o REPL.trim_makrup o Context.cases Syntax.string_of_term_global Syntax.string_of_term ctxt



fun s_expr ret bvs term =
  let val (head, args) = Term.strip_comb term
      val ret = if null args then ret else ")" :: ret
   in (
    case head
      of Const (name,_) => (name :: out_args ret bvs args)
       | Free (name, _) => (name :: out_args ret bvs args)
       | Var ((name,_), _) => (name :: out_args ret bvs args)
       | Abs (triple as (name,_,body)) =>
          if null args then ("(\<lambda> " :: name :: " " :: s_expr (")"::ret) (name::bvs) body)
                       else (s_expr ret bvs (Abs triple) @ out_args ret bvs args)
       | Bound i => (nth bvs i :: out_args ret bvs args)
       | _ $ _ => error "impossible")
   |> (fn L => if null args then L else "(" :: L)
  end
and out_args ret bvs args = fold_rev (fn x => fn ret => (" " :: s_expr ret bvs x)) args ret

fun s_expression term = String.concat (s_expr [] [] term)
val s_expression_packer = packString o s_expression


end

end