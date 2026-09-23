#!/usr/bin/env bash
#
# Rebuild the committed Scala jar of an Isabelle component whose etc/build.props
# has `no_build = true` (plan 二 §6.1).  Works for any such component; the
# component directory is the only argument.
#
#   tools/build_jar.sh <ABS_PATH_TO_COMPONENT_DIR>
#
# It builds in a throwaway copy so the shared working tree is never left with a
# flipped `no_build` line, and registers that copy as a component through a
# throwaway USER_HOME so the machine-wide ~/.isabelle/<id>/etc/components is
# untouched (getsettings only consults $HOME/.isabelle when USER_HOME is unset,
# and `isabelle scala_build` builds exactly the components on $ISABELLE_COMPONENTS,
# which getsettings resets from the components files it reads).
#
set -eu

if [ $# -ne 1 ]; then
  echo "usage: $0 <abs-path-to-component-dir>" >&2
  exit 2
fi

COMP="$1"
[ -d "$COMP" ] || { echo "not a directory: $COMP" >&2; exit 2; }
[ -f "$COMP/etc/build.props" ] || { echo "no etc/build.props under: $COMP" >&2; exit 2; }
[ -d "$COMP/src" ] || { echo "no src/ under: $COMP" >&2; exit 2; }

# the jar's path inside the component, read from build.props (never hard-coded)
MODULE="$(sed -n 's/^[[:space:]]*module[[:space:]]*=[[:space:]]*//p' "$COMP/etc/build.props" | head -1)"
[ -n "$MODULE" ] || { echo "no 'module =' line in $COMP/etc/build.props" >&2; exit 2; }

ID="$(isabelle getenv -b ISABELLE_IDENTIFIER)"
[ -n "$ID" ] || { echo "ISABELLE_IDENTIFIER is empty" >&2; exit 2; }

T="$(mktemp -d)"
H="$(mktemp -d)"
trap 'rm -rf "$T" "$H"' EXIT

# throwaway component copy: src/ verbatim, build.props without the no_build line,
# no etc/settings (its classpath line points at a jar that does not exist yet)
cp -r "$COMP/src" "$T/src"
mkdir -p "$T/etc"
grep -v '^[[:space:]]*no_build' "$COMP/etc/build.props" > "$T/etc/build.props"

# register T as the only extra component, via a throwaway USER_HOME
mkdir -p "$H/.isabelle/$ID/etc"
printf '%s\n' "$T" > "$H/.isabelle/$ID/etc/components"

echo "building $MODULE for component $COMP" >&2
USER_HOME="$H" isabelle scala_build

# the build wrote the jar into T/<module>; a compile failure exits non-zero
# above (set -e) and never reaches here, so this assertion cannot be vacuous
[ -f "$T/$MODULE" ] || { echo "build produced no $T/$MODULE" >&2; exit 2; }

mkdir -p "$COMP/$(dirname "$MODULE")"
cp "$T/$MODULE" "$COMP/$MODULE"

echo "== shasum of $COMP/$MODULE ==" >&2
SHA="$(unzip -p "$COMP/$MODULE" META-INF/isabelle/shasum)"
[ -n "$SHA" ] || { echo "META-INF/isabelle/shasum is empty in the built jar" >&2; exit 2; }
printf '%s\n' "$SHA"
