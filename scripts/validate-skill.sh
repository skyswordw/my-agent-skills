#!/bin/sh

set -eu

usage() {
  cat >&2 <<'EOF'
Usage: scripts/validate-skill.sh <skill-dir>

Validate one skill directory for:
  - required files
  - SKILL.md frontmatter
  - agents/openai.yaml presence
  - basic public-data guardrails
EOF
  exit 64
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  file_path=$1
  [ -f "$file_path" ] || die "required file is missing: $file_path"
  [ -s "$file_path" ] || die "required file is empty: $file_path"
}

[ $# -eq 1 ] || usage

skill_dir=$1
[ -d "$skill_dir" ] || die "skill directory does not exist: $skill_dir"

skill_name=${skill_dir##*/}
skill_md="$skill_dir/SKILL.md"
openai_agent_yaml="$skill_dir/agents/openai.yaml"

require_file "$skill_md"
require_file "$openai_agent_yaml"

if skill_frontmatter_name=$(
  awk '
    NR == 1 {
      if ($0 != "---") {
        exit 10
      }
      next
    }
    /^---$/ {
      closed = 1
      exit
    }
    {
      if ($0 ~ /^name:[[:space:]]*[^[:space:]].*$/) {
        sub(/^name:[[:space:]]*/, "", $0)
        name = $0
      }
      if ($0 ~ /^description:[[:space:]]*[^[:space:]].*$/) {
        has_description = 1
      }
    }
    END {
      if (!closed) {
        exit 11
      }
      if (name == "") {
        exit 12
      }
      if (!has_description) {
        exit 13
      }
      print name
    }
  ' "$skill_md"
); then
  :
else
  case $? in
    10) die "SKILL.md must start with YAML frontmatter: $skill_md" ;;
    11) die "SKILL.md frontmatter is not closed with ---: $skill_md" ;;
    12) die "SKILL.md frontmatter must include name: $skill_md" ;;
    13) die "SKILL.md frontmatter must include description: $skill_md" ;;
    *) die "failed to parse SKILL.md frontmatter: $skill_md" ;;
  esac
fi

[ "$skill_frontmatter_name" = "$skill_name" ] || die \
  "SKILL.md frontmatter name does not match directory name: expected $skill_name, got $skill_frontmatter_name"

grep -Eq '^interface:[[:space:]]*$' "$openai_agent_yaml" || \
  die "agents/openai.yaml must define an interface block: $openai_agent_yaml"
if awk '
  function indent_len(value,     copy) {
    copy = value
    sub(/[^ ].*$/, "", copy)
    return length(copy)
  }
  /^[[:space:]]*#/ || /^[[:space:]]*$/ {
    next
  }
  {
    current_indent = indent_len($0)
    trimmed = substr($0, current_indent + 1)

    if (in_interface && current_indent <= interface_indent) {
      in_interface = 0
    }

    if (current_indent == 0 && trimmed == "interface:") {
      saw_interface = 1
      in_interface = 1
      interface_indent = current_indent
      child_indent = 0
      next
    }

    if (in_interface && current_indent > interface_indent) {
      if (!child_indent) {
        child_indent = current_indent
      }
      if (current_indent == child_indent && trimmed ~ /^display_name:[[:space:]]*.+$/) {
        has_display_name = 1
      }
      if (current_indent == child_indent && trimmed ~ /^short_description:[[:space:]]*.+$/) {
        has_short_description = 1
      }
    }
  }
  END {
    if (!saw_interface) {
      exit 20
    }
    if (!has_display_name) {
      exit 21
    }
    if (!has_short_description) {
      exit 22
    }
  }
' "$openai_agent_yaml"; then
  :
else
  case $? in
    20) die "agents/openai.yaml must define a top-level interface block: $openai_agent_yaml" ;;
    21) die "agents/openai.yaml must define interface.display_name: $openai_agent_yaml" ;;
    22) die "agents/openai.yaml must define interface.short_description: $openai_agent_yaml" ;;
    *) die "failed to parse agents/openai.yaml interface block: $openai_agent_yaml" ;;
  esac
fi

symlink_hits=$(
  find "$skill_dir" \( -type d -name node_modules -prune \) -o -type l -print
)
if [ -n "$symlink_hits" ]; then
  die "skill contains symlinks, which are not allowed in published public data:\n$symlink_hits"
fi

env_hits=$(
  find "$skill_dir" \( -type d -name node_modules -prune \) -o -type f -name '.env*' -print
)
if [ -n "$env_hits" ]; then
  OLD_IFS=$IFS
  IFS='
'
  for env_file in $env_hits; do
    case "${env_file##*/}" in
      .env.example|.env.sample|.env.template|.env.dist)
        ;;
      *)
        die "skill contains a non-public environment file: $env_file"
        ;;
    esac
  done
  IFS=$OLD_IFS
fi

forbidden_name_hits=$(
  find "$skill_dir" \( -type d -name node_modules -prune \) -o -type f \( \
    -name '*.pem' -o \
    -name '*.key' -o \
    -name 'id_rsa' -o \
    -name 'id_rsa.pub' -o \
    -name 'id_ed25519' -o \
    -name 'id_ed25519.pub' \
  \) -print
)
if [ -n "$forbidden_name_hits" ]; then
  die "skill contains files that look like secret material:\n$forbidden_name_hits"
fi

private_key_hits=$(
  find "$skill_dir" \( -type d -name node_modules -prune \) -o -type f -exec grep -nE 'BEGIN (OPENSSH|RSA|DSA|EC|PGP|PRIVATE) PRIVATE KEY' {} /dev/null \; 2>/dev/null || true
)
if [ -n "$private_key_hits" ]; then
  die "skill contains private key content:\n$private_key_hits"
fi

printf 'Validated skill: %s\n' "$skill_dir"
