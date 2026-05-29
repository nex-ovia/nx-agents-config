# toml.sh — TOML parsing and config merging
# Requires: python3 3.11+ (tomllib), jq

parse_toml() {
  local toml_file="$1"
  python3 -c "
import tomllib, json, sys
try:
    with open('${toml_file}', 'rb') as f:
        print(json.dumps(tomllib.load(f)))
except Exception as e:
    print(json.dumps({}), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo "{}"
}

parse_toml_stdin() {
  python3 -c "
import tomllib, json, sys
try:
    print(json.dumps(tomllib.load(sys.stdin.buffer)))
except Exception as e:
    print(json.dumps({}), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo "{}"
}

load_user_config() {
  local user_toml="$STORE_DIR/config.toml"
  if [[ -f "$user_toml" ]]; then
    parse_toml "$user_toml"
  else
    echo "{}"
  fi
}

merge_configs() {
  local default_json="$1" user_json="$2"
  python3 -c "
import json, sys
default = json.loads(sys.argv[1])
user = json.loads(sys.argv[2])

for key in user:
    if key == 'tool' and key in default:
        default_tools = {t['name']: t for t in default['tool']}
        for t in user['tool']:
            default_tools[t['name']] = t
        default['tool'] = list(default_tools.values())
    elif isinstance(user[key], dict) and key in default and isinstance(default[key], dict):
        default[key].update(user[key])
    else:
        default[key] = user[key]

print(json.dumps(default))
" "$default_json" "$user_json" 2>/dev/null || echo "$default_json"
}

# Helpers using the merged config JSON ($TOML_JSON must be set)
tq()       { echo "$TOML_JSON" | jq -r "$@" 2>/dev/null || true; }

tool_names()        { tq '.tool[].name // empty'; }
tool_desc()         { tq ".tool[] | select(.name == \"$1\") | .desc // \"\""; }
tool_external()     { tq ".tool[] | select(.name == \"$1\") | .external // \"\""; }
tool_data()         { tq ".tool[] | select(.name == \"$1\") | .data // \"\""; }
tool_dependencies() { tq ".tool[] | select(.name == \"$1\") | .dependencies[] // empty" 2>/dev/null; }
tool_exists()       { tq ".tool[] | select(.name == \"$1\") | .name // \"\""; }

tool_int_count()    { tq ".tool[] | select(.name == \"$1\") | (.internal | length) // 0"; }
tool_int_from()     { tq ".tool[] | select(.name == \"$1\") | .internal[$2].from // \"\""; }
tool_int_to()       { tq ".tool[] | select(.name == \"$1\") | .internal[$2].to // \"\""; }
tool_int_desc()     { tq ".tool[] | select(.name == \"$1\") | .internal[$2].desc // \"\""; }

tool_file_count()   { tq ".tool[] | select(.name == \"$1\") | (.file | length) // 0"; }
tool_file_path()    { tq ".tool[] | select(.name == \"$1\") | .file[$2].path // \"\""; }
tool_file_desc()    { tq ".tool[] | select(.name == \"$1\") | .file[$2].desc // \"\""; }

tool_external_file_count() { tq ".tool[] | select(.name == \"$1\") | (.external_file | length) // 0"; }
tool_external_file_path()  { tq ".tool[] | select(.name == \"$1\") | .external_file[$2].path // \"\""; }
tool_external_file_desc()  { tq ".tool[] | select(.name == \"$1\") | .external_file[$2].desc // \"\""; }

tool_external_dir_count()      { tq ".tool[] | select(.name == \"$1\") | (.external_dir | length) // 0"; }
tool_external_dir_path()       { tq ".tool[] | select(.name == \"$1\") | .external_dir[$2].path // \"\""; }
tool_external_dir_store_path() { tq ".tool[] | select(.name == \"$1\") | .external_dir[$2].store_path // \"\""; }
tool_external_dir_desc()       { tq ".tool[] | select(.name == \"$1\") | .external_dir[$2].desc // \"\""; }
tool_external_dir_gitignore()  { tq ".tool[] | select(.name == \"$1\") | .external_dir[$2].gitignore // [] | .[]"; }

tool_internals_display() {
  tq ".tool[] | select(.name == \"$1\") | .internal[] | \"\(.from) → \(.to)  [\(.desc // \"\")]\"" 2>/dev/null
}
tool_files_display() {
  tq ".tool[] | select(.name == \"$1\") | .file[] | \"\(.path)  [\(.desc // \"\")]\"" 2>/dev/null
}
tool_external_files_display() {
  tq ".tool[] | select(.name == \"$1\") | .external_file[] | \"\(.path)  [\(.desc // \"\")]\"" 2>/dev/null
}
tool_deps_display() {
  local deps=$(tq ".tool[] | select(.name == \"$1\") | .dependencies | join(\", \") // empty" 2>/dev/null)
  [[ -n "$deps" ]] && echo "requires: $deps  [dependencies]" || true
}

shared_keys()  { tq '.shared | keys | .[] // empty'; }
shared_path()  { tq ".shared.\"$1\".path // \"\""; }
shared_desc()  { tq ".shared.\"$1\".desc // \"\""; }
