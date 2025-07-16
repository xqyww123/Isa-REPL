#!/bin/env python
USAGE = """
USAGE: example_lex.py <ADDRESS OF SERVER>

Argument <ADDRESS OF SERVER> is necessary.
"""

from IsaREPL import Client
import json
import sys

if len(sys.argv) != 2:
    print(USAGE)
    exit(1)

addr = sys.argv[1]
c = Client(addr, 'Transport')

print("""
This example demonstrates how to split a script into a
sequence of code pieces each of which is led by and contains
exactly one command.
""")

SRC = """\<^marker>\<open>creator "Kevin Kappelmann"\<close>
subsection \<open>Preorders\<close>
theory Preorders
  imports
    Binary_Relations_Reflexive
    Binary_Relations_Transitive
begin

definition "preorder_on \<equiv> reflexive_on \<sqinter> transitive_on"

lemma preorder_onI [intro]:
  assumes "reflexive_on P R"
  and "transitive_on P R"
  shows "preorder_on P R"
  unfolding preorder_on_def using assms by auto

lemma preorder_onE [elim]:
  assumes "preorder_on P R"
  obtains "reflexive_on P R" "transitive_on P R"
  using assms unfolding preorder_on_def by auto

lemma reflexive_on_if_preorder_on:
  assumes "preorder_on P R"
  shows "reflexive_on P R"
  using assms by (elim preorder_onE)

lemma transitive_on_if_preorder_on:
  assumes "preorder_on P R"
  shows "transitive_on P R"
  using assms by (elim preorder_onE)

lemma transitive_if_preorder_on_in_field:
  assumes "preorder_on (in_field R) R"
  shows "transitive R"
  using assms by (elim preorder_onE) (rule transitive_if_transitive_on_in_field)

corollary preorder_on_in_fieldE [elim]:
  assumes "preorder_on (in_field R) R"
  obtains "reflexive_on (in_field R) R" "transitive R"
  using assms
  by (blast dest: reflexive_on_if_preorder_on transitive_if_preorder_on_in_field)

lemma preorder_on_rel_inv_if_preorder_on [iff]:
  "preorder_on P R\<inverse> \<longleftrightarrow> preorder_on (P :: 'a \<Rightarrow> bool) (R :: 'a \<Rightarrow> 'a \<Rightarrow> bool)"
  by auto

lemma rel_if_all_rel_if_rel_if_reflexive_on:
  assumes "reflexive_on P R"
  and "\<And>z. P z \<Longrightarrow> R x z \<Longrightarrow> R y z"
  and "P x"
  shows "R y x"
  using assms by blast

lemma rel_if_all_rel_if_rel_if_reflexive_on':
  assumes "reflexive_on P R"
  and "\<And>z. P z \<Longrightarrow> R z x \<Longrightarrow> R z y"
  and "P x"
  shows "R x y"
  using assms by blast

consts preorder :: "'a \<Rightarrow> bool"

overloading
  preorder \<equiv> "preorder :: ('a \<Rightarrow> 'a \<Rightarrow> bool) \<Rightarrow> bool"
begin
  definition "(preorder :: ('a \<Rightarrow> 'a \<Rightarrow> bool) \<Rightarrow> bool) \<equiv> preorder_on (\<top> :: 'a \<Rightarrow> bool)"
end

lemma preorder_eq_preorder_on:
  "(preorder :: ('a \<Rightarrow> 'a \<Rightarrow> bool) \<Rightarrow> bool) = preorder_on (\<top> :: 'a \<Rightarrow> bool)"
  unfolding preorder_def ..

lemma preorder_eq_preorder_on_uhint [uhint]:
  assumes "P \<equiv> \<top> :: 'a \<Rightarrow> bool"
  shows "(preorder :: ('a \<Rightarrow> 'a \<Rightarrow> bool) \<Rightarrow> bool) \<equiv> preorder_on P"
  using assms by (simp add: preorder_eq_preorder_on)

context
  fixes R :: "'a \<Rightarrow> 'a \<Rightarrow> bool"
begin

lemma preorderI [intro]:
  assumes "reflexive R"
  and "transitive R"
  shows "preorder R"
  using assms by (urule preorder_onI)

lemma preorderE [elim]:
  assumes "preorder R"
  obtains "reflexive R" "transitive R"
  using assms by (urule (e) preorder_onE)

lemma preorder_on_if_preorder:
  fixes P :: "'a \<Rightarrow> bool"
  assumes "preorder R"
  shows "preorder_on P R"
  using assms by (elim preorderE)
  (intro preorder_onI reflexive_on_if_reflexive transitive_on_if_transitive)

end

paragraph \<open>Instantiations\<close>

lemma preorder_eq: "preorder (=)"
  using reflexive_eq transitive_eq by (rule preorderI)


end
"""
print("Source:")
print(SRC)
print("LEX result:")
print(c.lex(SRC))

c.close()

