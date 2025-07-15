signature PREMISE_SELECTION = sig

val SH_select : Sledgehammer_Prover.params -> Sledgehammer_Fact.fact_override ->
        int -> Proof.context -> thm list -> thm -> (string * Sledgehammer_Fact.fact list) list

val SH_select_debug : int ->
      Toplevel.state ->
        (string * Sledgehammer_MaSh.fact list) list

end

structure Premise_Selection : PREMISE_SELECTION = struct

fun SH_select param override number context facts goal =
  let val hyps = Thm.hyps_of goal
      val concl = Thm.concl_of goal
      val all_facts = Sledgehammer_Fact.nearly_all_facts_of_context \<^context> true
                        override facts hyps concl
   in Sledgehammer_MaSh.relevant_facts context param "cvc4" number override hyps concl all_facts
  end

fun SH_select_debug num state =
  let val thy = Toplevel.theory_of state
      val state = Toplevel.proof_of state
      val {context, facts, goal} = Proof.raw_goal state
   in SH_select (Sledgehammer_Commands.default_params thy [])
                Sledgehammer_Fact.no_fact_override num
                context facts goal
  end

end
