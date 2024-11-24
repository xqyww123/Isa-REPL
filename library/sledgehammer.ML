signature REPL_SLEDGEHAMMER_SOLVER = sig

val search_proof : Proof.context -> thm -> (string * thm)

val sledgehammer_params : string Config.T
val classical_prover_timeout : int Config.T

datatype fail_reason = Too_Many_Subgoals | Timeout | Application_Fails | Subgoal_unsolved | Unknown
                     | Prompt_Timeout
exception Auto_Fail of fail_reason

end

structure REPL_Sledgehammer_Solver : REPL_SLEDGEHAMMER_SOLVER = struct

val classical_prover_timeout =
        Attrib.setup_config_int \<^binding>\<open>REPL_classical_prover_timeout\<close> (K 3)

val sledgehammer_params_fixed = [("isar_proofs", "false")]

val sledgehammer_params = Attrib.setup_config_string \<^binding>\<open>REPL_sledgehammer_params\<close> (K "")
val preplay_timeout = Attrib.setup_config_int \<^binding>\<open>REPL_sledgehammer_preplay_timeout\<close> (K 20)

fun get_sledgehammer_params ctxt =
  Config.get ctxt sledgehammer_params
    |> String.tokens (fn #"," => true | _ => false)
    |> map_filter (fn s =>
          case String.tokens (fn #"=" => true | _ => false) s
            of [k,v] => SOME (Symbol.trim_blanks k, Symbol.trim_blanks v)
             | _ => if forall (fn c => c = #" ") (String.explode s)
                    then NONE
                    else error ("Invalid auto_sledgehammer_params : " ^ s))

fun error_message ctxt sequent =
  Pretty.string_of (Pretty.chunks (
    Pretty.para "Fail to prove the goal" ::
    (case Thm.prems_of sequent
       of (x::_)
            => [Syntax.pretty_term ctxt x]
        | _ => [])))

(*** Adapter of Sledgehammer ***)

(*copied and modified from Isabelle-2022/src/HOL/Tools/Sledgehammer/sledgehammer_proof_methods.ML
  Original Author: Jasmin Blanchette, TU Muenchen
                   Steffen Juilf Smolka, TU Muenchen

  May need to be synced once updated.
*)

val silence_state =
      Proof.map_contexts (Try0.silence_methods false #> Config.put SMT_Config.verbose false)

val debug_state =
      Proof.map_contexts (Try0.silence_methods false #> Config.put SMT_Config.verbose true
          #> Config.put SMT_Config.trace true #> Config.put SMT_Config.statistics true )

datatype fail_reason = Too_Many_Subgoals | Timeout | Application_Fails | Subgoal_unsolved | Unknown
                     | Prompt_Timeout
exception Auto_Fail of fail_reason

fun head_only tac th =
  if Thm.nprems_of th = 0
  then all_tac th
  else Goal.protect 1 th |> tac |> Seq.map Goal.conclude

fun auto_obligation_solver (ctxt, th) = th
       |> head_only (SOLVED' (fn _ => Clasimp.auto_tac ctxt) 1)

fun auto_obligation_solver1 (ctxt, th) = th
       |> head_only (SOLVED' (fn _ => Clasimp.auto_tac ctxt) 1)
       |> Seq.pull
       |> (fn NONE => raise Auto_Fail Application_Fails
            | SOME (th', _) => (ctxt, th'))

fun eval_prf_str timeout "" (ctxt,sequent) =
     \<^try>\<open>Timeout.apply timeout (Timing.timing (
            Position.setmp_thread_data Position.none auto_obligation_solver1)
         ) (ctxt,sequent) |> apfst (fn {elapsed=time,...} => (time,""))
              catch Timeout.TIMEOUT _ => raise Auto_Fail Timeout
                  | err => (tracing ("Unexpected error, maybe a bug: " ^ Runtime.exn_message err);
                            raise Auto_Fail Unknown)  \<close>
  | eval_prf_str timeout prf (ctxt,sequent) =
      \<^try>\<open>
       let val seq =
            Method.evaluate (
              Parse.read_embedded ctxt (Thy_Header.get_keywords (Proof_Context.theory_of ctxt))
                                       Method.parse (Input.string prf)
                |> fst
                |> Method.check_text ctxt
              ) ctxt [] (ctxt, sequent)
        in case Timeout.apply timeout (Timing.timing (
                    Position.setmp_thread_data Position.none Seq.pull)) seq
             of ({elapsed=time,...}, SOME (Seq.Result ret, _)) => ((time,prf), ret)
              | _ => raise Auto_Fail Application_Fails
       end catch Timeout.TIMEOUT _ => raise Auto_Fail Timeout
               | Auto_Fail err => Exn.reraise (Auto_Fail err)
               | err => (tracing ("Unexpected error, maybe a bug: " ^ Runtime.exn_message err);
                          raise Auto_Fail Unknown) \<close>


fun eval_prf_str_stat timeout F_None prf stat =
    let val ctxt = Proof.context_of stat
        val keywords = Thy_Header.get_keywords (Proof_Context.theory_of ctxt)
    in \<^try>\<open>(case Timeout.apply (Time.fromSeconds timeout)
                (Position.setmp_thread_data Position.none Seq.pull)
                (Proof.apply (Parse.read_embedded ctxt keywords Method.parse
                                                  (Input.string ("(" ^ prf ^ ")"))) stat)
          of (SOME (Seq.Result stat', _)) => (prf, stat')
           | _ => case F_None of SOME f => f()
                               | NONE => raise Auto_Fail Application_Fails)
        catch Timeout.TIMEOUT _ => (
                tracing "The proof fails due to timeout. Re-searching proofs...";
                raise Auto_Fail Timeout)
            | err => (
                tracing ("Unexpected error, maybe a bug: " ^ Runtime.exn_message err);
                raise Auto_Fail Unknown)\<close>
    end

exception SH_Short_Cut of string

fun dirty_hack ret stat s =
  let fun find c s = CharVector.foldri (fn (i, c', ret) => if c' = c then i :: ret else ret) [] s
      val inds = find #"\^E" s
   in if length inds < 4
      then tracing s
      else let
        val i2 = List.nth (inds, 1)
        val i3 = List.nth (inds, 2)
        val i4 = List.nth (inds, 3)
        val s_prf = String.substring (s, i2+1, i3 - 1 -i2)
        val preplay_succeeded = is_some (CharVector.findi (fn (i,c) => i > i4 andalso c = #"(") s)
        fun trans toks =
          let val toks1 = case toks of [] => raise Fail "internal bug #e12asfwgy43"
                                     | (tok::L) =>
                                 if Token.is_command tok andalso Token.content_of tok = "using"
                                 then L else tok::L
              val sep = find_index (fn tok => Token.is_command tok andalso
                                              (Token.content_of tok = "apply" orelse
                                               Token.content_of tok = "by")) toks1
              val (using, tac) = if sep = ~1 then raise Fail "internal bug #e12asfwgy44"
                                 else (take sep toks1, drop (sep+1) toks1)
              fun unparse toks = String.concatWith " " (map Token.unparse toks)
              fun unparse_tac (tok1::tok2::R) =
                    if Token.keyword_with (fn s => s = "[") tok2
                       andalso not (Token.keyword_with (K true) tok1)
                    then "(" ^ unparse [tok1] ^ ")" ^ unparse (tok2::R)
                    else unparse (tok1::tok2::R)
                | unparse_tac toks = unparse toks
            in (if null using then "" else "(insert " ^ unparse using ^ ")[1], ") ^ unparse_tac tac
           end
        val ctxt = Proof.context_of stat
        val keywords = Thy_Header.get_keywords (Proof_Context.theory_of ctxt)
        val prf = trans (Input.string s_prf
                      |> Input.source_explode
                      |> Token.tokenize keywords {strict = true}
                      |> filter Token.is_proper)
        val _ = Synchronized.change ret (fn prfs => prf :: prfs)
        val _ = tracing s
        val timeout = Config.get ctxt preplay_timeout
        in if preplay_succeeded andalso can (eval_prf_str_stat timeout NONE prf) stat
           then raise SH_Short_Cut prf
           else ()
       end
  end

fun raw_sledgehammer stat =
  let val N = #goal (Proof.goal stat) |> Thm.nprems_of
      val _ = if N = 0 then error "No subgoal!" else ()
      val ret : string list Synchronized.var = Synchronized.var "\<phi>System.raw_sledgehammer" []
      val sledgehammer_params = sledgehammer_params_fixed @ get_sledgehammer_params (Proof.context_of stat)
   in \<^try>\<open>(Sledgehammer.run_sledgehammer
              (Sledgehammer_Commands.default_params (Proof.theory_of stat) sledgehammer_params)
              Sledgehammer_Prover.Normal (SOME (dirty_hack ret stat)) 1 Sledgehammer_Fact.no_fact_override
              (silence_state stat);
       (Synchronized.value ret))

(* For some unknown reason, the return of Sledgehammer.run_sledgehammer doesn't give me everything
   it finds (not match to its output to users), so I have to dirty hijack its output stream and
   recovery the result in a hacking way.*)
    catch SH_Short_Cut ret => [ret]
         | err as Exn.Interrupt_Break => (warning "Interrupted\n\
              \If this interruption is unexpected for you, it can be caused by the \<open>try0\<close> based\n\
              \proof reconstruction of Sledgehammer.\n\
              \You may \<open>declare [[auto_sledgehammer_params = \"try0 = false\"]]\<close> to disable \<open>try0\<close>,\n\
              \and hopefully the problem can be addressed.";
              Exn.reraise err) \<close>
  end

(*** Proof search using Sledgehammer ***)


fun funpow' (0: int) _ x = x
  | funpow' n f x = funpow' (n - 1) f (f n x)

fun sledgehammer (ctxt,sequent) =
  let val (goal_term,_) = Logic.dest_implies (Thm.prop_of sequent)
      val stat = Proof.theorem NONE (K I) [[(goal_term, [])]] ctxt

      fun eval_prf_strs_stat [] _ = raise Auto_Fail Application_Fails
        | eval_prf_strs_stat (prf::L) stat =
            eval_prf_str_stat 30 NONE prf stat
            handle Auto_Fail _ => eval_prf_strs_stat L stat

      fun search_prf prompt =
        let
          val (prf0,stat0) =
                if prompt = ""
                then ("", stat)
                else eval_prf_str_stat 8 (SOME (fn () => ("",stat))) prompt stat
                     handle Auto_Fail Timeout => raise Auto_Fail Prompt_Timeout
          val N = Thm.nprems_of (@{print} (#goal (Proof.raw_goal stat0)))
          val Ns = string_of_int N

          val _ = if N > 30 then (tracing ("The prompt generates too many subgoals (" ^
                                    string_of_int N ^ "). give up...");
                                  raise Auto_Fail Too_Many_Subgoals)
                            else ()

          val (prfs,_) =
            funpow' N (fn j => fn (ps,s) =>
                        let val _ = tracing ("Sledgehammering on the " ^ string_of_int (N+1-j) ^
                                             "th goal (total " ^ Ns ^ ")")
                            val prfx = raw_sledgehammer s
                            val (p',s') = eval_prf_strs_stat prfx s
                         in (p'::ps, s') end)
                     ((if prf0 = "" then [] else [prf0]),stat0)
    
          val prf = "(" ^ String.concatWith ", " (rev prfs) ^ ")"
        in prf end

      fun rep_tries [] = raise Auto_Fail Application_Fails
        | rep_tries (f::L) = f () handle Auto_Fail _ => rep_tries L
      val prf = rep_tries [
          (fn () => search_prf "auto"),
          (fn () => (tracing "Fails... Try instead a stronger or maybe weaker prompt..." ;
                     search_prf "clarsimp, ((rule conjI)+)?")),
          (fn () => (tracing "Fails... Try instead the weakest prompt..." ;
                     search_prf ""))
        ]

   in eval_prf_str Time.zeroTime prf (ctxt,sequent)
  end


fun search_proof'i (ctxt,sequent) =
  let val ((_, prf), prf_result) = sledgehammer (ctxt, sequent)
   in (prf, snd prf_result)
                    (*
if no_cache
          then (tracing ("Proof cache miss, " ^ id))
          else (warning "The cached proof fails. Re-searching proofs...";
                Phi_Cache_DB.invalidate_proof_cache (not no_cache) id thy) ;
          find_proof ())) *)
   end
(* val proof = raw_sledgehammer stat *)


fun wrapper f (ctxt,sequent) =
  if Thm.no_prems sequent then sequent
  else case Thm.major_prem_of sequent
    of Const (\<^const_name>\<open>Trueprop\<close>, _) $ \<^const>\<open>True\<close> => @{thm TrueI} RS sequent
     | _ => f (ctxt,sequent)

fun search_proof ctxt sequent =
  if Thm.no_prems sequent then ("this", sequent)
  else case Thm.major_prem_of sequent
    of Const (\<^const_name>\<open>Trueprop\<close>, _) $ \<^const>\<open>True\<close> => ("standard", @{thm TrueI} RS sequent)
     | _ => search_proof'i (ctxt,sequent)
  handle Auto_Fail _ => error (error_message ctxt sequent)

end