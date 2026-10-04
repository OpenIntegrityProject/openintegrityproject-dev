#!/usr/bin/env zsh
########################################################################
## Script:        TEST-bootstrap_oi_repo.sh
## Version:       0.1.01 (2026-10-03)
## Origin:        https://github.com/OpenIntegrityProject/openintegrityproject-dev/blob/main/.repo/scripts/tests/TEST-bootstrap_oi_repo.sh
## Description:   Regression tests for bootstrap_oi_repo.sh and
##                merge_pr.sh. Uses throwaway software keys in an
##                ssh-agent in place of Secure Enclave keys, a local bare
##                repository in place of GitHub, and a stub "gh" that
##                records its calls and simulates PRs and CI runs.
## License:       BSD-2-Clause-Patent (https://spdx.org/licenses/BSD-2-Clause-Patent.html)
## Copyright:     (c) 2026 Blockchain Commons LLC (https://www.BlockchainCommons.com)
## Attribution:   Christopher Allen <ChristopherA@LifeWithAlacrity.com>
## Usage:         TEST-bootstrap_oi_repo.sh
########################################################################

# Reset the shell environment to a known state
emulate -LR zsh

# Safe shell scripting options
setopt errexit nounset pipefail localoptions warncreateglobal

typeset -r Exit_Status_Success=0
typeset -r Exit_Status_General=1

typeset -r Scripts="${0:A:h:h}"
typeset -g Test_Root="" Demo=""
typeset -gi Tests_Run=0 Tests_Failed=0

#----------------------------------------------------------------------#
# Function: check
#----------------------------------------------------------------------#
# Description:
#   Records one test result
# Parameters:
#   $1 - Test name
#   $2 - "true" if the test passed
#   $3 - Optional detail printed on failure
# Returns:
#   Exit_Status_Success always
#----------------------------------------------------------------------#
check() {
    (( Tests_Run += 1 ))
    if [[ "$2" == true ]]; then
        print -- "PASS  $1"
    else
        (( Tests_Failed += 1 ))
        print -- "FAIL  $1"
        [[ -z "${3-}" ]] || print -- "$3" | sed 's/^/      /'
    fi
    return $Exit_Status_Success
}

#----------------------------------------------------------------------#
# Function: is
#----------------------------------------------------------------------#
# Description:
#   Runs a command and prints "true" if it succeeds, else "false"
# Parameters:
#   $@ - Command and arguments
# Returns:
#   Exit_Status_Success always
#----------------------------------------------------------------------#
is() { if "$@" >/dev/null 2>&1; then print true; else print false; fi; }

#----------------------------------------------------------------------#
# Function: write_Gh_Stub
#----------------------------------------------------------------------#
# Description:
#   Installs a stub "gh" on PATH. "repo create --push" adds a local bare
#   repository as origin and pushes; "api" calls are logged; "pr view"
#   reports the PR described by FAKE_PR_* variables; "run list" returns
#   a run id; "run watch" fails when FAKE_RUN_FAIL=1.
# Parameters:
#   None
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
write_Gh_Stub() {
    mkdir -p "$Test_Root/bin"
    print -r -- '#!/bin/sh
echo "gh $*" >> "$TEST_ROOT/gh.log"
case "$1 $2" in
  "repo create")
    git init -q --bare -b main "$TEST_ROOT/origin.git"
    while [ $# -gt 0 ]; do [ "$1" = --source ] && src="$2"; shift; done
    git -C "$src" remote add origin "$TEST_ROOT/origin.git"
    git -C "$src" push -q -u origin main ;;
  "api "*) cat > /dev/null 2>&1 || true ;;
  "pr view")
    printf "%s\t%s\tmain\tOPEN\t%s\n" "$FAKE_PR_HEAD" "$FAKE_PR_BRANCH" "$FAKE_PR_TITLE" ;;
  "run list") echo 4242 ;;
  "run watch") [ "${FAKE_RUN_FAIL:-0}" = 1 ] && exit 1; exit 0 ;;
esac' > "$Test_Root/bin/gh"
    chmod +x "$Test_Root/bin/gh"
}

#----------------------------------------------------------------------#
# Function: bootstrap
#----------------------------------------------------------------------#
# Description:
#   Runs bootstrap_oi_repo.sh with the throwaway keys
# Parameters:
#   $@ - Extra arguments
# Returns:
#   The script's exit status
#----------------------------------------------------------------------#
bootstrap() {
    zsh "$Scripts/bootstrap_oi_repo.sh" --path "$Demo" --github test/oi-demo \
        --allow-software-human-key --allow-software-device-keys \
        --human-key "$Test_Root/keys/human.pub" --agent-key "$Test_Root/keys/agent.pub" \
        --device seshat="$Test_Root/keys/seshat.pub" \
        --device athena="$Test_Root/keys/athena.pub" "$@"
}

#----------------------------------------------------------------------#
# Function: as_Agent
#----------------------------------------------------------------------#
# Description:
#   Runs a command with the environment local Claude Code gets from the
#   generated .claude/settings.local.json
# Parameters:
#   $@ - Command and arguments
# Returns:
#   The command's exit status
#----------------------------------------------------------------------#
as_Agent() {
    typeset -a Env
    Env=(${(f)"$(sed -n 's/^ *"\(GIT_[A-Z_0-9]*\)": "\(.*\)",*$/\1=\2/p' "$Demo/.claude/settings.local.json")"})
    env "${Env[@]}" "$@"
}

#----------------------------------------------------------------------#
# Function: open_Pr
#----------------------------------------------------------------------#
# Description:
#   Pushes the current branch to origin and as refs/pull/<n>/head, and
#   points the gh stub at it
# Parameters:
#   $1 - PR number
#   $2 - Title
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
open_Pr() {
    typeset Branch
    Branch=$(git -C "$Demo" symbolic-ref --short HEAD)
    git -C "$Demo" push -q origin "HEAD:refs/heads/$Branch" "HEAD:refs/pull/$1/head"
    export FAKE_PR_HEAD="$(git -C "$Demo" rev-parse HEAD)" FAKE_PR_BRANCH="$Branch" FAKE_PR_TITLE="$2"
    git -C "$Demo" switch -q main
}

#----------------------------------------------------------------------#
# Function: run_Tests
#----------------------------------------------------------------------#
# Description:
#   Runs every test case in order; later cases build on earlier ones
# Parameters:
#   None
# Returns:
#   Exit_Status_Success always
#----------------------------------------------------------------------#
run_Tests() {
    typeset Output Main_Before Merge_Id
    typeset -i Status

    Output=$(bootstrap --dry-run 2>&1) && Status=0 || Status=$?
    check "dry run succeeds and creates nothing" \
        "$( (( Status == 0 )) && [[ ! -e "$Demo" ]] && print true || print false)" "$Output"

    Output=$(zsh "$Scripts/bootstrap_oi_repo.sh" --path "$Demo" --no-github \
        --human-key "$Test_Root/keys/human.pub" --agent-key "$Test_Root/keys/agent.pub" 2>&1) && Status=0 || Status=$?
    check "a software human key is refused without --allow-software-human-key" \
        "$( (( Status == 2 )) && [[ "$Output" == *"not a Secure Enclave"* ]] && print true || print false)" "$Output"

    Output=$(zsh "$Scripts/bootstrap_oi_repo.sh" --path "$Demo" --no-github --dry-run \
        --allow-software-human-key --human-key "$Test_Root/keys/human.pub" \
        --agent-key "$Test_Root/keys/agent.pub" \
        --device athena="$Test_Root/keys/athena.pub" 2>&1) && Status=0 || Status=$?
    check "a software device key is refused (it would become a main signer)" \
        "$( (( Status == 2 )) && [[ "$Output" == *"device key for athena is ssh-ed25519"* ]] && print true || print false)" "$Output"

    Output=$(bootstrap 2>&1) && Status=0 || Status=$?
    check "bootstrap succeeds" "$( (( Status == 0 )) && print true || print false)" "$Output"
    check "seven commits: inception, human, devices, local agent, cloud agent, roles, tooling" \
        "$( [[ "$(git -C "$Demo" rev-list --count HEAD)" == 7 ]] && print true || print false)"
    check "inception committer is the human key fingerprint" \
        "$( [[ "$(git -C "$Demo" log --max-parents=0 --format=%cn HEAD)" == "$(ssh-keygen -lf "$Test_Root/keys/human.pub" | awk '{print $2}')" ]] && print true || print false)"
    check "every commit verifies with main protected" \
        "$(is zsh "$Demo/.repo/scripts/verify_commit_signatures.sh" -C "$Demo" --protected HEAD)"
    check "devices are commit, main, and tag signers" \
        "$( [[ $(grep -c '^@ChristopherA/\(seshat\|athena\)-se ' "$Demo"/.repo/config/verification/allowed_{commit,main,tag}_signers | awk -F: '{s+=$2} END {print s}') == 6 ]] && print true || print false)"
    check "agent keys are commit signers only" \
        "$( grep -q '^@claude-local/' "$Demo/.repo/config/verification/allowed_commit_signers" \
            && grep -q '^@claude-code-web ' "$Demo/.repo/config/verification/allowed_commit_signers" \
            && ! grep -q '^@claude' "$Demo"/.repo/config/verification/allowed_{main,tag}_signers \
            && print true || print false)"
    check "settings.local.json exists and is ignored by Git" \
        "$( [[ -r "$Demo/.claude/settings.local.json" ]] && git -C "$Demo" check-ignore -q .claude/settings.local.json && print true || print false)"
    check "GitHub: repo created, pushed, and two rulesets requested" \
        "$( grep -q 'gh repo create test/oi-demo --public' "$Test_Root/gh.log" \
            && [[ $(grep -c 'gh api -X POST repos/test/oi-demo/rulesets' "$Test_Root/gh.log") == 2 ]] \
            && [[ "$(git -C "$Test_Root/origin.git" rev-parse main)" == "$(git -C "$Demo" rev-parse HEAD)" ]] \
            && print true || print false)"

    Output=$(bootstrap 2>&1) && Status=0 || Status=$?
    check "re-running makes no new commits" \
        "$( (( Status == 0 )) && [[ "$(git -C "$Demo" rev-list --count HEAD)" == 7 ]] && print true || print false)" "$Output"

    # Local Claude signs with its own key on a working branch
    git -C "$Demo" switch -q -c claude/readme
    print "Agent edit" >> "$Demo/README.md"
    as_Agent git -C "$Demo" commit -q -am "Agent edit to README"
    check "local Claude signs with the agent key, as itself" \
        "$( [[ "$(zsh "$Demo/.repo/scripts/verify_commit_signatures.sh" -C "$Demo" --protected main | grep "$(git -C "$Demo" rev-parse --short HEAD)")" == *"OK @claude-local/"* ]] \
            && [[ "$(git -C "$Demo" log -1 --format=%an)" == "Claude (local)" ]] && print true || print false)"
    open_Pr 1 "Agent edit to README"

    Main_Before=$(git -C "$Test_Root/origin.git" rev-parse main)
    Output=$(cd "$Demo" && zsh .repo/scripts/merge_pr.sh --dry-run 1 2>&1) && Status=0 || Status=$?
    check "merge_pr --dry-run verifies and leaves main alone" \
        "$( (( Status == 0 )) && [[ "$(git -C "$Test_Root/origin.git" rev-parse main)" == "$Main_Before" ]] && print true || print false)" "$Output"

    export FAKE_RUN_FAIL=1
    Output=$(cd "$Demo" && zsh .repo/scripts/merge_pr.sh -y 1 2>&1) && Status=0 || Status=$?
    check "merge_pr stops before main when the CI check fails" \
        "$( (( Status == 4 )) && [[ "$(git -C "$Test_Root/origin.git" rev-parse main)" == "$Main_Before" ]] \
            && git -C "$Test_Root/origin.git" rev-parse -q --verify staging/main >/dev/null && print true || print false)" "$Output"
    git -C "$Demo" reset -q --hard origin/main
    export FAKE_RUN_FAIL=0

    Output=$(cd "$Demo" && zsh .repo/scripts/merge_pr.sh -y 1 2>&1) && Status=0 || Status=$?
    Merge_Id=$(git -C "$Test_Root/origin.git" rev-parse main)
    check "merge_pr merges the PR to main with a human-signed merge" \
        "$( (( Status == 0 )) && [[ "$(git -C "$Test_Root/origin.git" rev-parse "$Merge_Id^2")" == "$FAKE_PR_HEAD" ]] \
            && [[ "$(git -C "$Test_Root/origin.git" rev-parse "$Merge_Id^1")" == "$Main_Before" ]] && print true || print false)" "$Output"
    check "main verifies after the merge" \
        "$(is zsh "$Demo/.repo/scripts/verify_commit_signatures.sh" -C "$Demo" --protected HEAD)"

    # An agent PR that changes the trust files is refused
    git -C "$Demo" switch -q -c claude/sneaky
    print "@mallory namespaces=\"git\" $(cut -d' ' -f1,2 "$Test_Root/keys/mallory.pub")" \
        >> "$Demo/.repo/config/verification/allowed_commit_signers"
    as_Agent git -C "$Demo" commit -q -am "Add a signer"
    open_Pr 2 "Add a signer"
    Main_Before=$(git -C "$Test_Root/origin.git" rev-parse main)
    Output=$(cd "$Demo" && zsh .repo/scripts/merge_pr.sh -y 2 2>&1) && Status=0 || Status=$?
    check "merge_pr refuses an agent PR that changes trust files" \
        "$( (( Status == 4 )) && [[ "$Output" == *"does not verify"* ]] \
            && [[ "$(git -C "$Test_Root/origin.git" rev-parse main)" == "$Main_Before" ]] && print true || print false)" "$Output"

    return $Exit_Status_Success
}

#----------------------------------------------------------------------#
# Function: main
#----------------------------------------------------------------------#
# Description:
#   Isolates Git, SSH, and gh in a test root, runs the tests, and
#   reports a summary
# Parameters:
#   None
# Returns:
#   Exit_Status_Success if all tests pass, Exit_Status_General otherwise
#----------------------------------------------------------------------#
main() {
    typeset Key
    Test_Root=$(mktemp -d)
    Demo="$Test_Root/oi-demo"
    mkdir -p "$Test_Root/keys"
    for Key in human agent seshat athena mallory; do
        ssh-keygen -q -t ed25519 -N '' -C "$Key" -f "$Test_Root/keys/$Key"
    done
    print -r -- "[user]
    name = Test Human
    email = human@example.com
[gpg \"ssh\"]
    program = ssh-keygen" > "$Test_Root/gitconfig"
    export GIT_CONFIG_GLOBAL="$Test_Root/gitconfig" GIT_CONFIG_NOSYSTEM=1 TEST_ROOT="$Test_Root"
    # The scripts under test run in child zsh processes. Point ZDOTDIR at
    # the empty test root so they skip the user's ~/.zshenv, which may
    # prepend directories (such as /opt/homebrew/bin) ahead of the stub.
    export ZDOTDIR="$Test_Root"
    export PATH="$Test_Root/bin:$PATH"
    write_Gh_Stub
    # Never reach real GitHub: stop unless a child zsh finds the stub
    [[ "$(zsh -c 'command -v gh')" == "$Test_Root/bin/gh" ]] || {
        print -u2 -- "Error: a child zsh does not resolve gh to the stub in $Test_Root/bin; not running tests"
        rm -rf -- "$Test_Root"
        return $Exit_Status_General
    }

    typeset -gx SSH_AUTH_SOCK SSH_AGENT_PID
    eval "$(ssh-agent -s)" >/dev/null
    trap 'ssh-agent -k >/dev/null 2>&1; rm -rf -- "$Test_Root"' EXIT
    ssh-add -q "$Test_Root/keys/human" "$Test_Root/keys/agent" 2>/dev/null

    # No test step reads input; detach stdin so a stray read cannot block
    run_Tests < /dev/null
    print -- "$(( Tests_Run - Tests_Failed )) of $Tests_Run tests passed"
    (( Tests_Failed == 0 )) || return $Exit_Status_General
    return $Exit_Status_Success
}

main "$@"
