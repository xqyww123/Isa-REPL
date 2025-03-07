theory Isa_REPL
  imports HOL.Sledgehammer
begin

ML_file \<open>contrib/mlmsgpack/mlmsgpack-aux.sml\<close>
ML_file \<open>contrib/mlmsgpack/realprinter-packreal.sml\<close>
ML_file \<open>contrib/mlmsgpack/mlmsgpack.sml\<close>

ML_file \<open>library/sledgehammer.ML\<close>

ML_file \<open>library/REPL.ML\<close>
ML_file \<open>library/REPL_serializer.ML\<close>
ML_file \<open>library/REPL_aux.ML\<close>
ML_file \<open>library/Server.ML\<close>


end
