read_codex_patch() {
  PATCH_PATHS=(); PATCH_HAS_BOM=0
  local line t mode='' active=0 first_add=0 added_block=0 text bom=$'\357\273\277'
  while IFS= read -r line || [ -n "$line" ]; do
    # Git Bash jq emits each \n as \r\n, so a CRLF patch arrives as \r\r\n.
    while [ "${line%$'\r'}" != "$line" ]; do line="${line%$'\r'}"; done
    # Markers and headers match trimmed, as Codex's parser trims them; content lines stay raw.
    t="${line#"${line%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
    if [ "$active" = 0 ]; then
      [ "$t" = '*** Begin Patch' ] && active=1
      continue
    fi
    # Raw: a context line ` *** End Patch` must not end the scan early.
    [ "$line" = '*** End Patch' ] && break
    case "$t" in
      '*** Add File: '*) mode=Add; PATCH_PATHS+=("${t#'*** Add File: '}"); first_add=1; added_block=0; continue ;;
      '*** Update File: '*) mode=Update; PATCH_PATHS+=("${t#'*** Update File: '}"); first_add=1; added_block=0; continue ;;
      '*** Delete File: '*) mode=Delete; PATCH_PATHS+=("${t#'*** Delete File: '}"); first_add=1; added_block=0; continue ;;
      '*** Move to: '*)
        [ "$mode" = Update ] && PATCH_PATHS+=("${t#'*** Move to: '}")
        added_block=0; continue ;;
    esac
    case "$line" in
      +*)
        text="${line#+}"
        if { [ "$mode" = Add ] && [ "$first_add" = 1 ]; } || { [ "$mode" = Update ] && [ "$added_block" = 0 ]; }; then
          case "$text" in "$bom"*) PATCH_HAS_BOM=1 ;; esac
        fi
        first_add=0; added_block=1 ;;
      *) added_block=0 ;;
    esac
  done <<< "$1"
}

normalize_hook_path() {
  local path="${1//\\//}" base="$2" prefix='' part result='' i
  local parts=() stack=()
  case "$path" in /*|[A-Za-z]:/*) ;; *) path="$base/$path" ;; esac
  case "$path" in
    [A-Za-z]:/*) prefix="${path:0:3}"; path="${path:3}" ;;
    //*) prefix='//'; path="${path:2}" ;;
    /*) prefix='/'; path="${path:1}" ;;
  esac
  IFS='/' read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    case "$part" in
      ''|.) ;;
      ..) i=${#stack[@]}; [ "$i" -gt 0 ] && unset 'stack[i-1]' ;;
      *) stack+=("$part") ;;
    esac
  done
  for part in "${stack[@]}"; do result="${result:+$result/}$part"; done
  printf '%s' "$prefix$result"
}
