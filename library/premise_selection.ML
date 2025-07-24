signature PREMISE_SELECTION = sig

val SH_select : Sledgehammer_Prover.params -> Sledgehammer_Fact.fact_override ->
        int -> Proof.context -> thm list -> thm -> (string * Sledgehammer_Fact.fact list) list list
val SH_select_ultimate_goal : Sledgehammer_Prover.params -> Sledgehammer_Fact.fact_override ->
        int -> Proof.context -> thm list -> thm -> (string * Sledgehammer_Fact.fact list) list
val SH_select_leading_goal : Sledgehammer_Prover.params -> Sledgehammer_Fact.fact_override ->
        int -> Proof.context -> thm list -> thm -> (string * Sledgehammer_Fact.fact list) list

val SH_select_debug : int ->
      Toplevel.state ->
        (string * Sledgehammer_MaSh.fact list) list list

end

structure Premise_Selection : PREMISE_SELECTION = struct

fun SH_select param override number context facts goal =
  let val local_facts = Facts.dest_static false
                          [Global_Theory.facts_of (Proof_Context.theory_of context)]
                          (Proof_Context.facts_of context)
                     |> maps (map Thm.prop_of o snd)
                     |> distinct (op aconv) (*
                     |> map (fn x => case try HOLogic.dest_Trueprop x
                                       of SOME y => y | NONE => x) *)
      (* val assms = Assumption.all_assms_of context |> map Thm.term_of *)
      fun selection goal =
        let val hyps = Logic.strip_imp_prems goal @ local_facts
            val concl = Logic.strip_imp_concl goal
            val all_facts = Sledgehammer_Fact.nearly_all_facts_of_context \<^context> true
                              override facts hyps concl
         in Sledgehammer_MaSh.relevant_facts context param "cvc4" number override hyps concl all_facts
        end
   in map selection (Thm.prems_of goal)
  end

fun SH_select_ultimate_goal param override number context facts goal =
  let val local_facts = Facts.dest_static false
                          [Global_Theory.facts_of (Proof_Context.theory_of context)]
                          (Proof_Context.facts_of context)
                     |> maps (map Thm.prop_of o snd)
                     |> distinct (op aconv)
      (* val assms = Assumption.all_assms_of context |> map Thm.term_of *)
      val goal = Thm.concl_of goal
               |> Logic.unprotect
      val hyps = Logic.strip_imp_prems goal @ local_facts
      val concl = Logic.strip_imp_concl goal
      val all_facts = Sledgehammer_Fact.nearly_all_facts_of_context \<^context> true
                        override facts hyps concl
   in Sledgehammer_MaSh.relevant_facts context param "cvc4" number override hyps concl all_facts
  end

fun SH_select_leading_goal param override number context facts goal =
  let val local_facts = Facts.dest_static false
                          [Global_Theory.facts_of (Proof_Context.theory_of context)]
                          (Proof_Context.facts_of context)
                     |> maps (map Thm.prop_of o snd)
                     |> distinct (op aconv)
      (* val assms = Assumption.all_assms_of context |> map Thm.term_of *)
      fun selection goal =
        let val hyps = Logic.strip_imp_prems goal @ local_facts
            val concl = Logic.strip_imp_concl goal
            val all_facts = Sledgehammer_Fact.nearly_all_facts_of_context \<^context> true
                              override facts hyps concl
         in Sledgehammer_MaSh.relevant_facts context param "cvc4" number override hyps concl all_facts
        end
   in Logic.dest_implies (Thm.prop_of goal)
   |> fst
   |> selection
  end

fun SH_select_debug num state =
  let val thy = Toplevel.theory_of state
      val state = Toplevel.proof_of state
      val {context, facts, goal} = Proof.goal state
   in SH_select (Sledgehammer_Commands.default_params thy [])
                Sledgehammer_Fact.no_fact_override num
                context facts goal
  end

end
