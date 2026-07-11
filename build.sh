#!/usr/bin/env bash
set -uo pipefail

SCHEME="Textual (Standard Release)"
PROJECT="Sources/App/Textual App.xcodeproj"
BUILD_DIR="$(pwd)/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
ROOT="$(pwd)"

# To sign with a real cert instead of ad-hoc, pass CODE_SIGN_IDENTITY:
#   CODE_SIGN_IDENTITY="Apple Development: you@example.com" ./build.sh
# Default ad-hoc identity is set in Configurations/Build/Code Signing Identity.xcconfig.

if [[ -t 1 ]]; then USE_COLOR=1; else USE_COLOR=0; fi
if [[ $USE_COLOR -eq 1 ]]; then
    B=$'\033[1m' D=$'\033[2m' R=$'\033[31m' Y=$'\033[33m' G=$'\033[32m' Z=$'\033[0m'
else
    B='' D='' R='' Y='' G='' Z=''
fi

printf '%s\n' "${B}Building Textwerk...${Z}"
printf '%s\n' "${D}  Scheme:  $SCHEME${Z}"
printf '%s\n' "${D}  Output:  $BUILD_DIR/Textwerk.app${Z}"
printf '\n'

EXTRA_ARGS=()
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    EXTRA_ARGS+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY")
fi

printf '%s\n' "${D}  Cleaning build caches...${Z}"
rm -rf "$BUILD_DIR" .tmp 2>/dev/null || true
find Frameworks "XPC Services" "Sources/Plugins" \
    -maxdepth 2 \( -name build -o -name .tmp \) -type d \
    -print0 2>/dev/null | xargs -0 rm -rf
printf '\n'

START=$(date +%s)

AWK_PROG=$(cat << 'AWKEOF'
function init_colors() {
    if (use_color) {
        BOLD = "\033[1m"; DIM = "\033[2m"; RED = "\033[31m"
        YLW  = "\033[33m"; RST = "\033[0m"
    }
}

function extract_target(line,    i, t) {
    i = index(line, "(in target '")
    if (i == 0) return ""
    t = substr(line, i + 12)
    i = index(t, "'")
    if (i == 0) return t
    return substr(t, 1, i - 1)
}

function src_filename(line,    i, n, parts, fp) {
    sub(/ \(in target.*$/, "", line)
    sub(/ normal (arm64|x86_64).*$/, "", line)
    n = split(line, parts, " ")
    for (i = n; i >= 1; i--) {
        if (parts[i] ~ /\.(m|mm|c|cpp|cc|swift)$/) {
            n = split(parts[i], fp, "/")
            return fp[n]
        }
    }
    return ""
}

# Returns the display label for a phase, or "" to skip this phase
function phase_label(phase) {
    if (phase == "CompileSwift")                      return "Swift"
    if (phase == "CompileC")                          return "compilec"  # handled specially
    if (phase == "CompileXIB")                        return "XIB"
    if (phase == "Ld")                                return "Link"
    if (phase == "CopyFiles" || phase == "CpHeader")  return "Copy"
    if (phase == "CodeSign")                          return "Sign"
    if (phase == "PhaseScriptExecution")              return "Script"
    if (phase == "GenerateDSYMFile")                  return "dSYM"
    if (phase == "ProcessProductPackaging")           return "Package"
    if (phase == "RegisterWithLaunchServices")        return "Register"
    if (phase == "Validate")                          return "Validate"
    if (phase == "Strip")                             return "Strip"
    if (phase == "MkDir")                             return "Mkdir"
    return ""  # unknown/noise — skip
}

function show_target(target) {
    if (target == cur_target) return
    cur_target = target
    last_phase = ""
    printf "\n  " BOLD "◼  %s" RST "\n", target
}

function show_phase(label) {
    if (label == last_phase) return
    last_phase = label
    printf "    " DIM "· %s" RST "\n", label
}

function print_error(line,    idx, loc, msg, n, p) {
    gsub(root "/", "", line)
    idx = index(line, ": error: ")
    if (idx > 0) {
        loc = substr(line, 1, idx - 1)
        msg = substr(line, idx + 9)
        sub(/:[0-9]+$/, "", loc)
        n = split(loc, p, "/")
        printf "\n    " RED "✗  %s  %s" RST "\n\n", p[n], msg
    } else {
        # Bare "error: message" form
        printf "\n    " RED "✗  %s" RST "\n\n", substr(line, 8)
    }
}

function print_warning(line,    idx, loc, msg, n, p) {
    gsub(root "/", "", line)
    idx = index(line, ": warning: ")
    if (idx > 0) {
        loc = substr(line, 1, idx - 1)
        msg = substr(line, idx + 11)
        sub(/:[0-9]+$/, "", loc)
        n = split(loc, p, "/")
        printf "    " YLW "⚠  %s  %s" RST "\n", p[n], msg
    } else {
        printf "    " YLW "⚠  %s" RST "\n", substr(line, 10)
    }
}

BEGIN {
    init_colors()
    cur_target = ""
    last_phase = ""
}

# Error/warning rules fire before (in target) to avoid misclassifying them as phases
/: error: / { print_error($0); next }
/: warning: / { print_warning($0); next }
/^error: /   { print_error($0); next }
/^warning: / { print_warning($0); next }

/\(in target / {
    target = extract_target($0)
    if (target == "") { next }
    # skip note: lines entirely
    if ($1 == "note:") { next }

    label = phase_label($1)
    if (label == "") { next }  # unknown/noise phase

    show_target(target)

    if (label == "compilec") {
        fname = src_filename($0)
        if (fname != "") printf "    " DIM "· %s" RST "\n", fname
        next
    }

    show_phase(label)
    next
}

{ next }
AWKEOF
)

set +e
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" \
    build 2>&1 | awk -v root="$ROOT" -v use_color="$USE_COLOR" "$AWK_PROG"
PIPE_STATUS=("${PIPESTATUS[@]}")
set -e

ELAPSED=$(( $(date +%s) - START ))

printf '\n'
if [[ ${PIPE_STATUS[0]} -eq 0 ]]; then
    printf '%s\n' "${G}${B}✓  Build succeeded${Z}${D} — ${ELAPSED}s${Z}"
    printf '%s\n' "${D}   $BUILD_DIR/Textwerk.app${Z}"
else
    printf '%s\n' "${R}${B}✗  Build failed${Z}${D} — ${ELAPSED}s${Z}"
    exit 1
fi
