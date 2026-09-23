(*  Title:      library/repl_boot.ML
    Author:     Qiyuan Xu

Loaded once, as a raw Poly/ML --use prelude by the `isabelle REPL` tool,
before Isabelle/ML antiquotations exist: Standard ML over Isabelle's
structures, no antiquotations (TAT_Boot.ML is the model).  Defines the
protocol command Isa_REPL.load.  Forked like build_session
(build.ML:101-118): the protocol loop must stay free to answer
Scala.function calls made while the theories load; interruptible_task
because Isabelle_Thread.params forks uninterruptible
(isabelle_thread.ML:100) and a wedged boot must be cancellable.
The failure render is guarded like build.ML:113-115 (TAT_Boot.ML at
0508b71:18-23 does the same): exn_message_list can itself raise, and
here that would escape a fork whose main has no handler
(isabelle_thread.ML:117-126) -- the tool would hear nothing and wait
out -T.
*)

fun isa_repl_load [] =
      ignore (Isabelle_Thread.fork (Isabelle_Thread.params "Isa_REPL.load") (fn () =>
        (case Exn.capture_body (Future.interruptible_task (fn () =>
                ((* the isabelle.Session's handshake sends Prover.options, whose
                    handler is init_options_interactive (protocol.ML:21-24):
                    parallel_proofs 3, show_markup_default, a persistent
                    Syntax cache.  Undo it as build.ML:55 does. *)
                 Isabelle_Process.init_options ();
                 Thy_Info.use_theories (Options.default ()) ""
                   [("Isa_REPL.Isa_REPL", Position.none)];
                 Thy_Info.finish ()))) of
          Exn.Res () => Output.protocol_message [Markup.function "Isa_REPL.loaded"] []
        | Exn.Exn exn =>
            Output.protocol_message [Markup.function "Isa_REPL.failed"]
              [[XML.Text (cat_lines
                  (case Exn.capture Runtime.exn_message_list exn of
                    Exn.Res msgs => msgs
                  | Exn.Exn _ (*sic!*) => ["CRASHED"]))]])))
  | isa_repl_load _ = raise Match;
val _ = Protocol_Command.define "Isa_REPL.load" isa_repl_load;
