signature REPL_SERIALIZE = sig

val message_type_packer   : REPL.message_type MessagePackBinIO.Pack.packer
val message_packer        : REPL.message MessagePackBinIO.Pack.packer
val flags_packer          : REPL.flags MessagePackBinIO.Pack.packer
val command_output_packer : REPL.command_output MessagePackBinIO.Pack.packer
val command_outputs_packer: REPL.command_outputs MessagePackBinIO.Pack.packer

end

structure REPL_Serialize : REPL_SERIALIZE = struct
open REPL

local open MessagePackBinIO.Pack in

fun flags_packer {is_toplevel, is_theory, is_proof, is_skipped_proof}
      = packTuple4 (packBool, packBool, packBool, packBool)
                   (is_toplevel, is_theory, is_proof, is_skipped_proof)

fun message_type_packer NORMAL  = packInt 0
  | message_type_packer TRACING = packInt 1
  | message_type_packer WARNING = packInt 2

val message_packer = packPair (message_type_packer, packString)


fun command_output_packer {
        command_name : string,
        message: message list, (*text printed in Isabelle's output panel*)
        output : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        errors : string list
} = packTuple7 (packString,
                packList message_packer,
                packOption (packString o YXML.string_of_body),
                flags_packer,
                packInt,
                packString,
                packList packString)
    (   command_name,
        message: message list, (*text printed in Isabelle's output panel*)
        output : Latex.text option, (*text, section, and other latex commands*)
        flags  : flags,
        level  : int,
        state  : string,
        errors : string list    )

type command_outputs = {
        outputs: command_output list,
        error : string option
}

fun command_outputs_packer {
        outputs: command_output list,
        error : string option
} = packPair (packList command_output_packer,
              packOption packString)
    (   outputs: command_output list,
        error : string option     )


end

end