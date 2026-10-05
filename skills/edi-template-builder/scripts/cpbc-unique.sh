#! /bin/sh

# set -x

usage() {
  printf "usage:\n  %s [-fb] <input-file>\n\n  -f    financial feed\n  -b    benefit feed\n" "$(basename "$0")"
}

# jq prelude: normalize the input down to the records array, then expose it as
# `recs`. Accepts either a bare top-level array or a wrapped { "data": [...] }
# envelope -- the same two shapes wrap-data.sh accepts.
RECS='def recs: if type=="object" and (.data|type=="array") then .data else . end;'

benefitplans() {
  jq "$RECS"'[ recs[]."Benefit Plans".[] | { name: ."Benefit Plan Name", id: ."Benefit Plan ID" } ] | unique' "$1"
}

genders() {
  jq "$RECS"'[ recs[]."Members Gender" ] | unique' "$1"
}

maritals() {
  jq "$RECS"'[ recs[]."Members Marital Status" ] | unique' "$1"
}

coverages() {
  jq "$RECS"'[ recs[]."Benefit Plans".[]."Coverage Name" ] | unique' "$1"
}

relationships() {
  jq "$RECS"'[ recs[]."Relationship Code" ] | unique' "$1"
}

deductions() {
  jq "$RECS"'[ recs[]."Deductions" | keys ] | flatten | unique' "$1"
}

financial() {
  deductions=$(deductions "$1")
  genders=$(genders "$1")
  maritals=$(maritals "$1")

  printf "Deductions:\n%s\nGenders:\n%s\nMarital Status:\n%s\n" "$deductions" "$genders" "$maritals"
}

benefit() {
  benefitplans=$(benefitplans "$1")
  genders=$(genders "$1")
  maritals=$(maritals "$1")
  coverages=$(coverages "$1")
  relationships=$(relationships "$1")


  printf "Benefit Plans:\n%s\nGenders:\n%s\nMarital Status:\n%s\nCoverage Names:\n%s\nRelationship Codes:\n%s\n" "$benefitplans" "$genders" "$maritals" "$coverages" "$relationships"
}

main() {
  financial=0
  benefit=0
  # Parse args directly. getopt + `set -- $args` word-splits on spaces, which
  # breaks input paths like "Client & Co.json". Quoting "$2" handles them.
  if [ $# -ne 2 ]; then
    usage
    exit 1
  fi

  case "$1" in
    -f) financial=1; input="$2" ;;
    -b) benefit=1; input="$2" ;;
    *)  usage; exit 1 ;;
  esac

  if [ ! -f "$input" ]; then
    printf "'%s' does not exist.\n" "$input"
    exit 1
  fi

  if [ $benefit -eq 1 ]; then
    benefit "$input"
    exit 0
  elif [ $financial -eq 1 ]; then
    financial "$input"
    exit 0
  else
    usage
    exit 1
  fi

}

main "$@"
