theory Isa_REPL
  imports Auto_Sledgehammer.Auto_Sledgehammer Main
begin

(* declare [[ML_debugger]] *)

ML_file \<open>contrib/mlmsgpack/mlmsgpack-aux.sml\<close>
ML_file \<open>contrib/mlmsgpack/realprinter-packreal.sml\<close>
ML_file \<open>contrib/mlmsgpack/mlmsgpack.sml\<close>

ML_file \<open>library/premise_selection.ML\<close>
ML_file \<open>library/REPL.ML\<close>
ML_file \<open>library/REPL_serializer.ML\<close>
ML_file \<open>library/REPL_aux.ML\<close>
ML_file \<open>library/Server.ML\<close>

(*
ML \<open>
val master_dir = Path.explode "/home/user/current_theory_dir";
  val target_name = "Auto_Sledgehammer.Auto_Sledgehammer";  (* or "HOL.List" or "MyTheory" *)
  val qualifier = "Draft";

  (* Parse the absolute path: *)
  val {node_name, master_dir = target_master_dir, theory_name} =
      Resources.import_name qualifier master_dir target_name;

  (* node_name is the absolute path to the .thy file *)
  writeln ("Theory file path: " ^ Path.implode node_name);
  (* target_master_dir is the directory containing that file *)
  writeln ("Master directory: " ^ Path.implode target_master_dir);
  (* theory_name is the fully qualified theory name *)
  writeln ("Theory name: " ^ theory_name);

\<close>
*)

(*
ML \<open>Symbol_Pos.explode ("asdasd", Position.none)
  |> Vector.fromList
             |> Vector.map fst
  |> (fn src => Vector.sub (src, 1))
\<close>
ML \<open>
\<^here>\<close>
 
ML \<open>(REPL_Aux.column_of_pos "ML \<open>\nx\<close>" |> snd)
        (Position.make0 2 6 1 "" "" "")\<close>
*)

(*
ML \<open>REPL_Serialize.string_of_term "T4S4" (Context.Proof \<^context>) (Thm.prop_of @{thm allI})\<close>



ML \<open>REPL_Serialize.print_term {all_typ=true, bv_typ=true, constant_typ=true,
        free_typ=true, num_typ=true, sorting=true, show_type_P=SOME 0.4, show_sort_P=SOME 0.5}
    \<^context> (Thm.prop_of @{thm allI}) \<close>

ML \<open>Random.random ()\<close>
ML \<open>Time.now ()\<close>
ML \<open>fun rmod x y = x - y * Real.realFloor (x / y);\<close> 

ML \<open>Random.random ()\<close>
*)

end
