theory Isa_REPL
  imports Auto_Sledgehammer.Auto_Sledgehammer Main
begin

ML_file \<open>contrib/mlmsgpack/mlmsgpack-aux.sml\<close>
ML_file \<open>contrib/mlmsgpack/realprinter-packreal.sml\<close>
ML_file \<open>contrib/mlmsgpack/mlmsgpack.sml\<close>

ML_file \<open>library/premise_selection.ML\<close>
ML_file \<open>library/REPL.ML\<close>
ML_file \<open>library/REPL_serializer.ML\<close>
ML_file \<open>library/REPL_aux.ML\<close>
ML_file \<open>library/Server.ML\<close>

(*
declare [[ML_debugger]]
declare [[ML_print_depth = 1000]]
 
lemma 
  assumes \<open>rev l = b\<close>
  shows \<open>rev (rev l) = rev b\<close> and B and \<open>rev l = b\<close>
proof -
ML_val \<open>Premise_Selection.SH_select_debug 10 @{Isar.state}\<close>
  have A: "[] @ [] = []" sorry
  show \<open>rev (rev l) = rev b\<close>  
  ML_val \<open>Assumption.all_assms_of \<^context>\<close>
  ML_val \<open>Premise_Selection.SH_select_debug 10 @{Isar.state}\<close>
  ML_val \<open>Thm.prems_of (#goal @{Isar.goal})\<close>
*)

end
