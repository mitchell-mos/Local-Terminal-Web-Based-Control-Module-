#!/bin/zsh

# Shared release-version helpers for the native macOS lifecycle tools.
# Version labels use vMAJOR.UPDATE.FIX, with UPDATE padded to two digits.

control_module_version_label() {
  local project_dir="$1"
  local major="" update="" fix="" package_version="" package_major="" package_update="" package_fix=""
  local has_version_file=0
  if [[ -r "$project_dir/version.json" ]]; then
    has_version_file=1
    major="$(/usr/bin/plutil -extract major raw "$project_dir/version.json" 2>/dev/null || true)"
    update="$(/usr/bin/plutil -extract update raw "$project_dir/version.json" 2>/dev/null || true)"
    fix="$(/usr/bin/plutil -extract fix raw "$project_dir/version.json" 2>/dev/null || true)"
  fi
  if (( has_version_file == 0 )); then
    package_version="$(/usr/bin/plutil -extract version raw "$project_dir/package.json" 2>/dev/null || true)"
    if print -r -- "$package_version" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      major="${package_version%%.*}"
      package_version="${package_version#*.}"
      update="${package_version%%.*}"
      fix="${package_version##*.}"
    else
      return 1
    fi
  fi

  if ! print -r -- "$major.$update.$fix" | /usr/bin/grep -Eq '^[0-9]{1,9}\.[0-9]{1,2}\.[0-9]{1,9}$' \
    || (( 10#$update > 99 )); then
    return 1
  fi

  # When both public metadata files are present, refuse to report a version
  # unless they describe the same release. This keeps downgrade checks from
  # trusting one edited file while the application package reports another.
  if (( has_version_file )) && [[ -r "$project_dir/package.json" ]]; then
    package_version="$(/usr/bin/plutil -extract version raw "$project_dir/package.json" 2>/dev/null || true)"
    if ! print -r -- "$package_version" | /usr/bin/grep -Eq '^[0-9]{1,9}\.[0-9]{1,2}\.[0-9]{1,9}$'; then
      return 1
    fi
    package_major="${package_version%%.*}"
    package_version="${package_version#*.}"
    package_update="${package_version%%.*}"
    package_fix="${package_version##*.}"
    if (( 10#$major != 10#$package_major \
      || 10#$update != 10#$package_update \
      || 10#$fix != 10#$package_fix )); then
      return 1
    fi
  fi
  /usr/bin/printf 'v%s.%02d.%s' "$major" "$update" "$fix"
}

control_module_version_relation() {
  local candidate="$1"
  local installed="$2"
  local index candidate_value installed_value
  typeset -a candidate_parts installed_parts

  if ! print -r -- "$candidate" | /usr/bin/grep -Eq '^v[0-9]{1,9}\.[0-9]{2}\.[0-9]{1,9}$' \
    || ! print -r -- "$installed" | /usr/bin/grep -Eq '^v[0-9]{1,9}\.[0-9]{2}\.[0-9]{1,9}$'; then
    print -r -- "unknown"
    return 0
  fi

  candidate_parts=("${(@s:.:)${candidate#v}}")
  installed_parts=("${(@s:.:)${installed#v}}")
  for index in 1 2 3; do
    candidate_value="$(( 10#${candidate_parts[$index]} ))"
    installed_value="$(( 10#${installed_parts[$index]} ))"
    if (( candidate_value > installed_value )); then
      print -r -- "newer"
      return 0
    elif (( candidate_value < installed_value )); then
      print -r -- "older"
      return 0
    fi
  done
  print -r -- "same"
}
