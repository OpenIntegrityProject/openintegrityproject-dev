#!/usr/bin/env zsh
########################################################################
## Script:        TEST-verify_commit_signatures.sh
## Version:       0.1.00 (2026-10-02)
## Origin:        https://github.com/OpenIntegrityProject/openintegrityproject-dev/blob/main/.repo/scripts/tests/TEST-verify_commit_signatures.sh
## Description:   Regression tests for verify_commit_signatures.sh. Builds
##                throwaway repositories signed with throwaway keys and
##                checks that valid trust chains pass and each kind of
##                broken chain fails.
## License:       BSD-2-Clause-Patent (https://spdx.org/licenses/BSD-2-Clause-Patent.html)
## Copyright:     (c) 2026 Blockchain Commons LLC (https://www.BlockchainCommons.com)
## Attribution:   Christopher Allen <ChristopherA@LifeWithAlacrity.com>
## Usage:         TEST-verify_commit_signatures.sh
########################################################################

# Reset the shell environment to a known state
emulate -LR zsh

# Safe shell scripting options
setopt errexit nounset pipefail localoptions warncreateglobal

typeset -r Exit_Status_Success=0
typeset -r Exit_Status_General=1

typeset -r Verifier="${0:A:h:h}/verify_commit_signatures.sh"
typeset -r Signers_Path=".repo/config/verification/allowed_commit_signers"
typeset -g Test_Root=""
typeset -gi Tests_Run=0 Tests_Failed=0

#----------------------------------------------------------------------#
# Function: make_Key
#----------------------------------------------------------------------#
# Description:
#   Creates an unencrypted throwaway ed25519 key in the test root
# Parameters:
#   $1 - Key name
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
make_Key() {
    ssh-keygen -q -t ed25519 -N '' -C "$1" -f "$Test_Root/keys/$1"
}

#----------------------------------------------------------------------#
# Function: key_Fingerprint
#----------------------------------------------------------------------#
# Description:
#   Prints the SHA256 fingerprint of a throwaway key
# Parameters:
#   $1 - Key name
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
key_Fingerprint() {
    ssh-keygen -lf "$Test_Root/keys/$1.pub" | awk '{print $2}'
}

#----------------------------------------------------------------------#
# Function: signers_Line
#----------------------------------------------------------------------#
# Description:
#   Prints an allowed signers line for a throwaway key
# Parameters:
#   $1 - Key name (also used as the principal)
#   $2 - Optional extra options, comma-prefixed (e.g. ',valid-before="2020"')
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
signers_Line() {
    print -r -- "@$1 namespaces=\"git\"${2-} $(<"$Test_Root/keys/$1.pub")"
}

#----------------------------------------------------------------------#
# Function: signed_Commit
#----------------------------------------------------------------------#
# Description:
#   Commits staged changes in the current repository, SSH-signed by a
#   throwaway key (or unsigned when the key name is "none")
# Parameters:
#   $1 - Key name, or "none"
#   $2 - Commit message
#   $@ - Extra arguments for git commit
# Returns:
#   Exit status of git commit
#----------------------------------------------------------------------#
signed_Commit() {
    typeset Key="$1" Message="$2"
    shift 2
    if [[ "$Key" == none ]]; then
        git -c commit.gpgsign=false commit -q --allow-empty -m "$Message" "$@"
    else
        git -c gpg.format=ssh -c gpg.ssh.program=ssh-keygen \
            -c user.signingkey="$Test_Root/keys/$Key" \
            commit -q -S --allow-empty -m "$Message" "$@"
    fi
}

#----------------------------------------------------------------------#
# Function: new_Repo
#----------------------------------------------------------------------#
# Description:
#   Creates a repository with an Open Integrity inception commit (empty,
#   committer named by key fingerprint) and cds into it
# Parameters:
#   $1 - Repository name
#   $2 - Inception key name
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
new_Repo() {
    typeset Name="$1" Key="$2"
    git init -q "$Test_Root/$Name"
    cd "$Test_Root/$Name"
    git config user.name "Test User"
    git config user.email "test@example.com"
    GIT_COMMITTER_NAME="$(key_Fingerprint "$Key")" signed_Commit "$Key" "Inception"
}

#----------------------------------------------------------------------#
# Function: add_Signers
#----------------------------------------------------------------------#
# Description:
#   Writes the allowed signers file and commits it, signed by a key
# Parameters:
#   $1 - Signing key name
#   $2 - File contents
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
add_Signers() {
    typeset Key="$1" Contents="$2"
    mkdir -p "${Signers_Path:h}"
    print -r -- "$Contents" > "$Signers_Path"
    git add "$Signers_Path"
    signed_Commit "$Key" "Update signers"
}

#----------------------------------------------------------------------#
# Function: expect
#----------------------------------------------------------------------#
# Description:
#   Runs the verifier in the current repository and checks its exit
#   status and, optionally, that its output contains a string
# Parameters:
#   $1 - Test name
#   $2 - Expected exit status
#   $3 - Optional expected output substring
# Returns:
#   Exit_Status_Success always (failures are counted)
#----------------------------------------------------------------------#
expect() {
    typeset Name="$1" Expected_Status="$2" Expected_Text="${3-}" Output
    typeset -i Status=0
    Output=$(zsh "$Verifier" 2>&1) || Status=$?
    (( Tests_Run += 1 ))
    if (( Status == Expected_Status )) && [[ -z "$Expected_Text" || "$Output" == *"$Expected_Text"* ]]; then
        print -- "PASS  $Name"
    else
        (( Tests_Failed += 1 ))
        print -- "FAIL  $Name (exit $Status, expected $Expected_Status${Expected_Text:+, text \"$Expected_Text\"})"
        print -- "$Output" | sed 's/^/      /'
    fi
    return $Exit_Status_Success
}

#----------------------------------------------------------------------#
# Function: run_Tests
#----------------------------------------------------------------------#
# Description:
#   Runs every test case
# Parameters:
#   None
# Returns:
#   Exit_Status_Success always
#----------------------------------------------------------------------#
run_Tests() {
    typeset Name
    for Name in root alice mallory; do make_Key $Name; done

    new_Repo valid root
    add_Signers root "$(signers_Line root)
$(signers_Line alice)"
    signed_Commit alice "Alice's work"
    expect "valid chain: inception, signers file, approved signer" 0 "Verified 3 of 3"

    new_Repo unsigned root
    add_Signers root "$(signers_Line root)"
    signed_Commit none "Unsigned work"
    expect "unsigned commit fails" 4 "unsigned or not SSH-signed"

    new_Repo unknown root
    add_Signers root "$(signers_Line root)"
    signed_Commit mallory "Mallory's work"
    expect "unlisted signer fails" 4 "not authorized"

    new_Repo self_approval root
    add_Signers root "$(signers_Line root)"
    add_Signers mallory "$(signers_Line root)
$(signers_Line mallory)"
    expect "signer cannot approve itself in the same commit" 4 "not authorized"

    new_Repo before_signers root
    signed_Commit alice "Before any signers file"
    expect "only the inception key signs before the signers file exists" 4 "is not the inception key"

    git init -q "$Test_Root/nonempty_inception"
    cd "$Test_Root/nonempty_inception"
    git config user.name "Test User"; git config user.email "test@example.com"
    print data > file.txt; git add file.txt
    GIT_COMMITTER_NAME="$(key_Fingerprint root)" signed_Commit root "Inception with content"
    expect "non-empty inception fails" 4 "inception commit is not empty"

    git init -q "$Test_Root/wrong_committer"
    cd "$Test_Root/wrong_committer"
    git config user.name "Test User"; git config user.email "test@example.com"
    GIT_COMMITTER_NAME="$(key_Fingerprint alice)" signed_Commit root "Inception"
    expect "inception key must match committer fingerprint" 4 "committer names"

    new_Repo expiry root
    add_Signers root "$(signers_Line root)
$(signers_Line alice ',valid-before="20200101"')"
    GIT_COMMITTER_DATE="2019-06-01T00:00:00Z" signed_Commit alice "Before expiry"
    expect "valid-before honors the commit date, not today" 0
    GIT_COMMITTER_DATE="2021-06-01T00:00:00Z" signed_Commit alice "After expiry"
    expect "commit after valid-before fails" 4 "not authorized"

    new_Repo two_roots root
    Name=$(git symbolic-ref --short HEAD)
    git checkout -q --orphan other
    GIT_COMMITTER_NAME="$(key_Fingerprint alice)" signed_Commit alice "Second inception"
    git checkout -q "$Name"
    git -c gpg.format=ssh -c gpg.ssh.program=ssh-keygen \
        -c user.signingkey="$Test_Root/keys/root" \
        merge -q -S --allow-unrelated-histories -m "Merge" other
    expect "a second root commit fails" 4 "found 2"

    new_Repo source_for_shallow root
    add_Signers root "$(signers_Line root)"
    signed_Commit root "More"
    git clone -q --depth 1 "file://$Test_Root/source_for_shallow" "$Test_Root/shallow" 2>/dev/null
    cd "$Test_Root/shallow"
    expect "shallow clone is refused" 3 "shallow clone"

    return $Exit_Status_Success
}

#----------------------------------------------------------------------#
# Function: main
#----------------------------------------------------------------------#
# Description:
#   Sets up an isolated test root and Git environment, runs the tests,
#   and reports a summary
# Parameters:
#   None
# Returns:
#   Exit_Status_Success if all tests pass, Exit_Status_General otherwise
#----------------------------------------------------------------------#
main() {
    Test_Root=$(mktemp -d)
    mkdir -p "$Test_Root/keys"
    trap 'rm -rf -- "$Test_Root"' EXIT

    # Isolate from the user's Git configuration and signing setup
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    unset SSH_AUTH_SOCK

    run_Tests
    print -- "$(( Tests_Run - Tests_Failed )) of $Tests_Run tests passed"
    (( Tests_Failed == 0 )) || return $Exit_Status_General
    return $Exit_Status_Success
}

main "$@"
