#!/usr/bin/env zsh
########################################################################
## Script:        bootstrap_oi_repo.sh
## Version:       0.1.00 (2026-10-02)
## Origin:        https://github.com/OpenIntegrityProject/openintegrityproject-dev/blob/main/.repo/scripts/bootstrap_oi_repo.sh
## Description:   Creates a new Open Integrity repository from scratch:
##                an inception commit signed with the human's Secure
##                Enclave key, then one signed commit per trust step
##                (human signer, other devices, local agent key, cloud
##                agent key, main and tag roles, verification tooling),
##                local Git and Claude Code signing configuration, and
##                optionally the GitHub repository with its rulesets.
##                Every step is skipped if already done, so the script
##                can be re-run after an interruption.
## License:       BSD-2-Clause-Patent (https://spdx.org/licenses/BSD-2-Clause-Patent.html)
## Copyright:     (c) 2026 Blockchain Commons LLC (https://www.BlockchainCommons.com)
## Attribution:   Christopher Allen <ChristopherA@LifeWithAlacrity.com>
## Usage:         bootstrap_oi_repo.sh [options]   (see --help)
## Examples:      bootstrap_oi_repo.sh --dry-run
##                bootstrap_oi_repo.sh --create-agent-key \
##                    --device seshat=~/keys/sign_se_seshat.pub \
##                    --device athena=~/keys/sign_se_athena.pub
##                bootstrap_oi_repo.sh --no-github
########################################################################

# Reset the shell environment to a known state
emulate -LR zsh

# Safe shell scripting options
setopt errexit nounset pipefail localoptions warncreateglobal

# Script-scoped exit status codes
typeset -r Exit_Status_Success=0            # Successful execution
typeset -r Exit_Status_General=1            # General error (unspecified)
typeset -r Exit_Status_Usage=2              # Invalid usage or arguments
typeset -r Exit_Status_IO=3                 # Input/output error
typeset -r Exit_Status_Verification=4       # Result failed verification

typeset -r Script_Name="${0:t}"
typeset -r Source_Root="${0:A:h:h:h}"

typeset -r Verification_Dir=".repo/config/verification"
typeset -r Step_Trailer="OI-Bootstrap-Step"

# Anthropic's Claude Code on the web signing key, as observed 2026-10-02.
# Its scope (per session, account, organization, or global) is unconfirmed.
typeset -r Default_Cloud_Key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKy87HxSEheG8vEPhSs9u2KZCtVErAQfpmprtUJCZ2w7"

typeset -r Inception_Message="Initialize repository and establish a SHA-1 root of trust

This key also certifies future commits' integrity and origin. Other keys can be authorized to add additional commits via the creation of a ./.repo/config/verification/allowed_commit_signers file. This file must initially be signed by this repo's inception key, granting these keys the authority to add future commits to this repo, including the potential to remove the authority of this inception key for future commits. Once established, any changes to ./.repo/config/verification/allowed_commit_signers must be authorized by one of the previously approved signers."

# Options, set by parse_Parameters
typeset -g Repo_Path="" GitHub_Repo="OpenIntegrityProject/oi-demo"
typeset -g Human_Key="" Human_Principal="" Agent_Key="" Agent_Principal=""
typeset -g Cloud_Key="$Default_Cloud_Key" Cloud_Principal="@claude-code-web"
typeset -g Dry_Run=false Use_GitHub=true Allow_Software_Human_Key=false Allow_Software_Device_Keys=false
typeset -g Create_Agent_Key=false
typeset -ga Device_Specs

#----------------------------------------------------------------------#
# Function: show_Usage
#----------------------------------------------------------------------#
# Description:
#   Prints usage instructions to stderr
# Parameters:
#   None
# Returns:
#   Does not return - exits with Exit_Status_Usage
#----------------------------------------------------------------------#
show_Usage() {
    print -u2 "Usage: $Script_Name [options]
Options:
  --path <dir>               New repository location (default: ../oi-demo)
  --github <owner/name>      GitHub repository (default: $GitHub_Repo)
  --human-key <file.pub>     This device's Secure Enclave signing key
                             (default: user.signingkey of this repository)
  --human-principal <name>   (default: @<github user>/<host>-se)
  --device <host>=<file.pub> Another device's Secure Enclave signing key;
                             repeatable
  --agent-key <file.pub>     Local Claude Code signing key
  --create-agent-key         Create the local Claude Code key in the Secure
                             Enclave (no Touch ID) if --agent-key is absent
  --agent-principal <name>   (default: @claude-local/<host>)
  --cloud-key '<key>'        Claude Code on the web key (default: observed key)
  --no-github                Skip creating the GitHub repository
  --allow-software-human-key Accept a non-Secure-Enclave human key (testing)
  --allow-software-device-keys Accept non-Secure-Enclave device keys (testing)
  --dry-run                  Print what would happen; change nothing
Examples:
  $Script_Name --dry-run
  $Script_Name --device athena=~/keys/sign_se_athena.pub"
    exit $Exit_Status_Usage
}

#----------------------------------------------------------------------#
# Function: say / run
#----------------------------------------------------------------------#
# Description:
#   say prints a progress line. run prints a command and, unless in dry
#   run mode, executes it.
# Parameters:
#   $@ - Message (say) or command and arguments (run)
# Returns:
#   The command's exit status (run); Exit_Status_Success (say)
#----------------------------------------------------------------------#
say() { print -- "==> $*"; }
run() {
    print -- "    \$ ${(j: :)${(q-)@}}"
    [[ "$Dry_Run" == true ]] && return $Exit_Status_Success
    "$@"
}

#----------------------------------------------------------------------#
# Function: die
#----------------------------------------------------------------------#
# Description:
#   Prints an error and exits
# Parameters:
#   $1 - Message
#   $2 - Exit status (default Exit_Status_General)
# Returns:
#   Does not return
#----------------------------------------------------------------------#
die() {
    print -u2 -- "Error: $1"
    exit ${2:-$Exit_Status_General}
}

#----------------------------------------------------------------------#
# Function: key_Text / key_Type / key_Fingerprint
#----------------------------------------------------------------------#
# Description:
#   Reads the "<type> <base64>" part of a public key file, its type, and
#   its SHA256 fingerprint
# Parameters:
#   $1 - Public key file
# Returns:
#   Prints the value; non-zero if the file is not a public key
#----------------------------------------------------------------------#
key_Text() {
    typeset -a Fields
    Fields=(${=$(head -n 1 "$1")})
    (( ${#Fields} >= 2 )) || return $Exit_Status_General
    print -- "$Fields[1] $Fields[2]"
}
key_Type() { typeset Text; Text=$(key_Text "$1") || return $?; print -- "${Text%% *}"; }
key_Fingerprint() { ssh-keygen -lf "$1" | awk '{print $2}'; }

#----------------------------------------------------------------------#
# Function: signers_Line
#----------------------------------------------------------------------#
# Description:
#   Prints a commented allowed_signers entry
# Parameters:
#   $1 - Principal
#   $2 - Key text ("<type> <base64>")
#   $3 - Description for the comment line
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
signers_Line() {
    typeset Principal="$1" Key="$2" Description="$3" Fingerprint
    Fingerprint=$(print -r -- "$Key" | ssh-keygen -lf - | awk '{print $2}')
    print -r -- "# $Description"
    print -r -- "# $Fingerprint"
    print -r -- "$Principal namespaces=\"git\" $Key"
}

#----------------------------------------------------------------------#
# Function: step_Done
#----------------------------------------------------------------------#
# Description:
#   Reports whether a bootstrap step's commit already exists, by its
#   OI-Bootstrap-Step trailer
# Parameters:
#   $1 - Step name
# Returns:
#   Exit_Status_Success if done
#----------------------------------------------------------------------#
step_Done() {
    [[ -d "$Repo_Path/.git" ]] || return $Exit_Status_General
    git -C "$Repo_Path" rev-parse -q --verify HEAD >/dev/null 2>&1 || return $Exit_Status_General
    [[ -n "$(git -C "$Repo_Path" log --format=%H --grep="^$Step_Trailer: $1\$" HEAD)" ]]
}

#----------------------------------------------------------------------#
# Function: commit_Step
#----------------------------------------------------------------------#
# Description:
#   Stages the given paths and makes a commit signed by the human key,
#   tagged with a step trailer. Skips the step if already done.
# Parameters:
#   $1 - Step name
#   $2 - Commit subject and body
#   $@ - Paths to stage (none for an empty commit)
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
commit_Step() {
    typeset Step="$1" Message="$2"
    shift 2
    (( $# == 0 )) || run git -C "$Repo_Path" add -- "$@"
    run git -C "$Repo_Path" commit -S --signoff --allow-empty -q \
        -m "$Message" --trailer "$Step_Trailer: $Step"
}

#----------------------------------------------------------------------#
# Function: append_Signers
#----------------------------------------------------------------------#
# Description:
#   Appends entries to a file in the verification directory
# Parameters:
#   $1 - File name within the verification directory
#   $2 - Text to append
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
append_Signers() {
    typeset File="$Repo_Path/$Verification_Dir/$1" Text="$2"
    print -- "    (append to $Verification_Dir/$1)"
    print -r -- "$Text" | sed 's/^/      /'
    [[ "$Dry_Run" == true ]] && return $Exit_Status_Success
    mkdir -p "${File:h}"
    [[ -s "$File" ]] && print >> "$File"
    print -r -- "$Text" >> "$File"
}

#----------------------------------------------------------------------#
# Function: create_Agent_Key
#----------------------------------------------------------------------#
# Description:
#   Creates a non-exportable Secure Enclave key with no Touch ID for the
#   local Claude Code agent, and saves its public key from the SSH agent.
#   macOS only.
# Parameters:
#   $1 - Path to write the public key
# Returns:
#   Exit_Status_Success, or exits on failure
#----------------------------------------------------------------------#
create_Agent_Key() {
    typeset Pub_File="$1" Label="${1:t:r}"
    [[ "$OSTYPE" == darwin* ]] || die "--create-agent-key needs macOS"
    command -v sc_auth >/dev/null || die "sc_auth not found"
    say "Creating local agent key '$Label' in the Secure Enclave (no Touch ID)"
    run sc_auth create-ctk-identity -l "$Label" -k p-256-ne -t none
    [[ "$Dry_Run" == true ]] && return $Exit_Status_Success
    ssh-add -L | grep -- " $Label\$" > "$Pub_File" \
        || die "new key '$Label' not visible in ssh-add -L; save its public key to $Pub_File and re-run with --agent-key"
    say "Saved $Pub_File ($(key_Fingerprint "$Pub_File"))"
}

#----------------------------------------------------------------------#
# Function: check_Inputs
#----------------------------------------------------------------------#
# Description:
#   Fills defaults and validates keys and tools before any change
# Parameters:
#   None
# Returns:
#   Exit_Status_Success, or exits on invalid input
#----------------------------------------------------------------------#
check_Inputs() {
    typeset Host Spec Device_File GitHub_User
    Host=$(hostname -s)
    for Spec in git ssh-keygen; do
        command -v $Spec >/dev/null || die "$Spec not found" $Exit_Status_IO
    done
    [[ "$Use_GitHub" == false ]] || command -v gh >/dev/null || die "gh not found; use --no-github" $Exit_Status_IO

    [[ -n "$Repo_Path" ]] || Repo_Path="${Source_Root:h}/${GitHub_Repo:t}"
    Repo_Path="${Repo_Path:a}"
    GitHub_User=$(git -C "$Source_Root" config --get github.user 2>/dev/null) || GitHub_User="ChristopherA"

    if [[ -z "$Human_Key" ]]; then
        Human_Key=$(git -C "$Source_Root" config --get user.signingkey 2>/dev/null) \
            || die "no --human-key and no user.signingkey in $Source_Root" $Exit_Status_Usage
    fi
    Human_Key="${Human_Key/#\~/$HOME}"
    [[ -r "$Human_Key" ]] || die "human key '$Human_Key' not readable" $Exit_Status_IO
    key_Text "$Human_Key" >/dev/null || die "'$Human_Key' is not a public key" $Exit_Status_IO
    if [[ "$(key_Type "$Human_Key")" != sk-ecdsa-sha2-nistp256@openssh.com && "$Allow_Software_Human_Key" == false ]]; then
        die "human key is $(key_Type "$Human_Key"), not a Secure Enclave (sk-ecdsa) key; pass --allow-software-human-key to override" $Exit_Status_Usage
    fi
    [[ -n "$Human_Principal" ]] || Human_Principal="@$GitHub_User/$Host-se"

    for Spec in "${Device_Specs[@]}"; do
        [[ "$Spec" == *=* ]] || die "--device expects <host>=<file.pub>, got '$Spec'" $Exit_Status_Usage
        Device_File="${${Spec#*=}/#\~/$HOME}"
        key_Text "$Device_File" >/dev/null || die "device key '$Device_File' is not a public key" $Exit_Status_IO
        if [[ "$(key_Type "$Device_File")" != sk-ecdsa-sha2-nistp256@openssh.com && "$Allow_Software_Device_Keys" == false ]]; then
            die "device key for ${Spec%%=*} is $(key_Type "$Device_File"), not a Secure Enclave (sk-ecdsa) key; it would become a main and tag signer (override with --allow-software-device-keys)" $Exit_Status_Usage
        fi
    done

    [[ -n "$Agent_Principal" ]] || Agent_Principal="@claude-local/$Host"
    if [[ -z "$Agent_Key" ]]; then
        # Reuse an existing local agent key (newest first) before creating one
        typeset -a Existing
        Existing=("$HOME"/.ssh/sign_se_ecdsa-claude-$Host.local-*.pub(N.om))
        Agent_Key="${Existing[1]-$HOME/.ssh/sign_se_ecdsa-claude-$Host.local-${GitHub_User:l}_$(date +%Y-%m-%d).pub}"
        if [[ ! -r "$Agent_Key" ]]; then
            [[ "$Create_Agent_Key" == true ]] || die "no --agent-key; pass one, or --create-agent-key" $Exit_Status_Usage
            create_Agent_Key "$Agent_Key"
        fi
    fi
    Agent_Key="${Agent_Key/#\~/$HOME}"
    [[ "$Dry_Run" == true && ! -r "$Agent_Key" ]] \
        || key_Text "$Agent_Key" >/dev/null || die "agent key '$Agent_Key' is not a public key" $Exit_Status_IO

    [[ "$Cloud_Key" == ssh-* || "$Cloud_Key" == ecdsa-* || "$Cloud_Key" == sk-* ]] \
        || die "--cloud-key must be '<type> <base64>'" $Exit_Status_Usage

    say "Repository:   $Repo_Path$( [[ "$Use_GitHub" == true ]] && print " (GitHub $GitHub_Repo)")"
    say "Human key:    $Human_Principal $(key_Fingerprint "$Human_Key") ($(key_Type "$Human_Key"))"
    for Spec in "${Device_Specs[@]}"; do
        say "Device key:   @$GitHub_User/${Spec%%=*}-se $(key_Fingerprint "${${Spec#*=}/#\~/$HOME}")"
    done
    [[ -r "$Agent_Key" ]] && say "Agent key:    $Agent_Principal $(key_Fingerprint "$Agent_Key") ($(key_Type "$Agent_Key"))"
    say "Cloud key:    $Cloud_Principal $(print -r -- "$Cloud_Key" | ssh-keygen -lf - | awk '{print $2}')"
    [[ "$Dry_Run" == false ]] || say "DRY RUN: nothing will be changed"
}

#----------------------------------------------------------------------#
# Function: step_Init / step_Inception / step_Signers / ...
#----------------------------------------------------------------------#
# Description:
#   The bootstrap steps, in order. Each commit is signed by the human
#   key; the trust files are written so each commit verifies under the
#   rules of verify_commit_signatures.sh.
# Parameters:
#   None
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
step_Init() {
    if [[ -d "$Repo_Path/.git" ]]; then
        say "Repository exists at $Repo_Path"
    else
        [[ ! -e "$Repo_Path" || -z "$(ls -A "$Repo_Path" 2>/dev/null)" ]] \
            || die "$Repo_Path exists and is not an empty directory" $Exit_Status_IO
        say "Creating repository"
        run git init -q -b main "$Repo_Path"
    fi
    say "Configuring local Git signing"
    run git -C "$Repo_Path" config gpg.format ssh
    run git -C "$Repo_Path" config user.signingkey "$Human_Key"
    run git -C "$Repo_Path" config commit.gpgsign true
    run git -C "$Repo_Path" config tag.gpgsign true
    run git -C "$Repo_Path" config gpg.ssh.allowedSignersFile "$Verification_Dir/allowed_commit_signers"
}

step_Inception() {
    if [[ -d "$Repo_Path/.git" ]] && git -C "$Repo_Path" rev-parse -q --verify HEAD >/dev/null 2>&1; then
        say "Inception commit exists"
        return $Exit_Status_Success
    fi
    say "Inception commit (Touch ID)"
    print -- "    \$ GIT_COMMITTER_NAME=$(key_Fingerprint "$Human_Key") git commit --allow-empty -S ..."
    [[ "$Dry_Run" == true ]] && return $Exit_Status_Success
    GIT_COMMITTER_NAME="$(key_Fingerprint "$Human_Key")" \
        git -C "$Repo_Path" commit -S --allow-empty -q -m "$Inception_Message" \
        --trailer "Signed-off-by: $(key_Fingerprint "$Human_Key") <$(git -C "$Repo_Path" config user.email)>"
}

step_Human_Signer() {
    step_Done human-signer && { say "Human signer already approved"; return $Exit_Status_Success; }
    say "Approve this device's Secure Enclave key (Touch ID)"
    append_Signers allowed_commit_signers "$(signers_Line "$Human_Principal" "$(key_Text "$Human_Key")" \
        "Human, $(hostname -s) Secure Enclave key (Touch ID); inception key")"
    commit_Step human-signer "Authorize $Human_Principal as commit signer" "$Verification_Dir/allowed_commit_signers"
}

step_Devices() {
    typeset Spec Host Text=""
    (( ${#Device_Specs} > 0 )) || { say "No other devices given"; return $Exit_Status_Success; }
    step_Done devices && { say "Device keys already approved"; return $Exit_Status_Success; }
    say "Approve other devices' Secure Enclave keys (Touch ID)"
    for Spec in "${Device_Specs[@]}"; do
        Host="${Spec%%=*}"
        [[ -z "$Text" ]] || Text+=$'\n\n'
        Text+="$(signers_Line "${Human_Principal%/*}/$Host-se" "$(key_Text "${${Spec#*=}/#\~/$HOME}")" \
            "Human, $Host Secure Enclave key (Touch ID)")"
    done
    append_Signers allowed_commit_signers "$Text"
    commit_Step devices "Authorize other devices' Secure Enclave keys" "$Verification_Dir/allowed_commit_signers"
}

step_Agent_Signer() {
    step_Done agent-signer && { say "Local agent key already approved"; return $Exit_Status_Success; }
    say "Approve the local Claude Code key (Touch ID)"
    append_Signers allowed_commit_signers "$(signers_Line "$Agent_Principal" \
        "$( [[ -r "$Agent_Key" ]] && key_Text "$Agent_Key" || print '<agent key>')" \
        "Agent, Claude Code on $(hostname -s); Secure Enclave key without Touch ID; working branches only")"
    commit_Step agent-signer "Authorize $Agent_Principal (local Claude Code) as commit signer" \
        "$Verification_Dir/allowed_commit_signers"
}

step_Cloud_Signer() {
    step_Done cloud-signer && { say "Cloud agent key already approved"; return $Exit_Status_Success; }
    say "Approve the Claude Code on the web key (Touch ID)"
    append_Signers allowed_commit_signers "$(signers_Line "$Cloud_Principal" "$Cloud_Key" \
        "Agent, Claude Code on the web; Anthropic-held key, scope and rotation unconfirmed; working branches only")"
    commit_Step cloud-signer "Authorize $Cloud_Principal (Claude Code on the web) as commit signer

The private key is held by Anthropic. Whether it is unique to this
account or shared by all Claude Code on the web sessions is unconfirmed,
so a signature by it proves only that some Claude session made the
commit. It is limited to working branches by the main signer rules." \
        "$Verification_Dir/allowed_commit_signers"
}

step_Roles() {
    typeset Spec Text
    step_Done roles && { say "Main and tag roles already set"; return $Exit_Status_Success; }
    say "Restrict main, tags, and trust files to Secure Enclave keys (Touch ID)"
    Text="$(signers_Line "$Human_Principal" "$(key_Text "$Human_Key")" "Human, $(hostname -s) Secure Enclave key (Touch ID)")"
    for Spec in "${Device_Specs[@]}"; do
        Text+=$'\n\n'"$(signers_Line "${Human_Principal%/*}/${Spec%%=*}-se" "$(key_Text "${${Spec#*=}/#\~/$HOME}")" \
            "Human, ${Spec%%=*} Secure Enclave key (Touch ID)")"
    done
    append_Signers allowed_main_signers "# Signers for main's first-parent chain and for changes to these files
# Secure Enclave keys only

$Text"
    append_Signers allowed_tag_signers "# Signers for release tags
# Secure Enclave keys only

$Text"
    commit_Step roles "Require Secure Enclave keys for main, tags, and trust files" \
        "$Verification_Dir/allowed_main_signers" "$Verification_Dir/allowed_tag_signers"
}

step_Tooling() {
    typeset File
    typeset -a Files
    step_Done tooling && { say "Tooling already added"; return $Exit_Status_Success; }
    say "Add verification tooling, CI, and project files (Touch ID)"
    Files=(.repo/scripts/verify_commit_signatures.sh
           .repo/scripts/tests/TEST-verify_commit_signatures.sh
           .repo/scripts/merge_pr.sh
           .repo/scripts/collect_signing_environment.sh
           .repo/docs/REQUIREMENTS-verify_commit_signatures.md
           .github/workflows/verify-signatures.yml)
    for File in "${Files[@]}"; do
        [[ -r "$Source_Root/$File" ]] || die "missing source file $Source_Root/$File" $Exit_Status_IO
        run mkdir -p "$Repo_Path/${File:h}"
        run cp -p "$Source_Root/$File" "$Repo_Path/$File"
    done
    if [[ "$Dry_Run" == false ]]; then
        print -r -- "# Machine-specific Claude Code settings (agent signing key)
.claude/settings.local.json
# Signing environment reports, reviewed before committing
.repo/reports/" > "$Repo_Path/.gitignore"
        print -r -- "# ${GitHub_Repo:t}

A demonstration of an [Open Integrity](https://github.com/OpenIntegrityProject/core) repository: every commit since the inception commit is SSH-signed, and who may sign what is recorded in the repository itself.

- **Humans** sign with Secure Enclave keys (Touch ID). Only they may sign commits on \`main\`, tags, and changes to \`.repo/config/verification/\`.
- **Claude Code**, running locally or on the web, signs with its own keys and works on \`claude/*\` branches.
- **CI** checks every commit and tag against these rules: \`.repo/scripts/verify_commit_signatures.sh\`.

Verify it yourself:

\`\`\`sh
git clone https://github.com/$GitHub_Repo && cd ${GitHub_Repo:t}
zsh .repo/scripts/verify_commit_signatures.sh
\`\`\`" > "$Repo_Path/README.md"
        print -r -- "# CLAUDE.md

This is an Open Integrity repository. Every commit must be SSH-signed by a key listed in \`.repo/config/verification/\`.

- Work only on \`claude/*\` branches. Never push to \`main\` or \`staging/*\`.
- Never edit files in \`.repo/config/verification/\`; the verifier rejects agent changes to them.
- Before pushing, run \`zsh .repo/scripts/verify_commit_signatures.sh --protected origin/main\` and \`zsh .repo/scripts/tests/TEST-verify_commit_signatures.sh\`.
- A human merges with \`.repo/scripts/merge_pr.sh <number>\`, signing the merge with a Secure Enclave key." > "$Repo_Path/CLAUDE.md"
    fi
    commit_Step tooling "Add commit signature verification, CI, and project files" \
        "${Files[@]}" .gitignore README.md CLAUDE.md
}

step_Local_Claude() {
    typeset Settings="$Repo_Path/.claude/settings.local.json"
    if [[ -e "$Settings" ]]; then
        say "Local Claude Code settings exist; left unchanged ($Settings)"
        return $Exit_Status_Success
    fi
    say "Configure local Claude Code to sign with its own key"
    print -- "    (write .claude/settings.local.json; ignored by Git)"
    [[ "$Dry_Run" == true ]] && return $Exit_Status_Success
    mkdir -p "${Settings:h}"
    print -r -- '{
  "env": {
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_KEY_0": "user.signingkey",
    "GIT_CONFIG_VALUE_0": "'"$Agent_Key"'",
    "GIT_AUTHOR_NAME": "Claude (local)",
    "GIT_AUTHOR_EMAIL": "noreply@anthropic.com",
    "GIT_COMMITTER_NAME": "Claude (local)",
    "GIT_COMMITTER_EMAIL": "noreply@anthropic.com"
  }
}' > "$Settings"
}

step_Verify() {
    say "Verify the new repository"
    [[ "$Dry_Run" == true ]] && { print -- "    (skipped in dry run)"; return $Exit_Status_Success; }
    zsh "$Repo_Path/.repo/scripts/verify_commit_signatures.sh" -C "$Repo_Path" --protected HEAD \
        || die "the new repository does not verify" $Exit_Status_Verification
}

step_GitHub() {
    [[ "$Use_GitHub" == true ]] || { say "Skipping GitHub (--no-github)"; return $Exit_Status_Success; }
    if git -C "$Repo_Path" remote get-url origin >/dev/null 2>&1; then
        say "GitHub remote exists; pushing main"
        run git -C "$Repo_Path" push -u origin main
    else
        say "Create $GitHub_Repo on GitHub and push"
        run gh repo create "$GitHub_Repo" --public --source "$Repo_Path" --remote origin --push \
            --description "Open Integrity demonstration: signed history with human and agent roles"
    fi
    say "Protect main with rulesets"
    run_Ruleset '{
  "name": "main: verified history",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "verify", "integration_id": 15368 } ]
      } }
  ]
}'
    run_Ruleset '{
  "name": "main: only admins update",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [ { "type": "update", "parameters": { "update_allows_fetch_and_merge": false } } ],
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ]
}'
}

#----------------------------------------------------------------------#
# Function: run_Ruleset
#----------------------------------------------------------------------#
# Description:
#   Creates a ruleset on the GitHub repository unless one with the same
#   name exists
# Parameters:
#   $1 - Ruleset JSON
# Returns:
#   Exit_Status_Success
#----------------------------------------------------------------------#
run_Ruleset() {
    typeset Json="$1" Name Existing=""
    Name=$(print -r -- "$Json" | sed -n 's/^  "name": "\(.*\)",$/\1/p')
    if [[ "$Dry_Run" == false ]]; then
        Existing=$(gh api "repos/$GitHub_Repo/rulesets" --jq ".[] | select(.name == \"$Name\") | .id" 2>/dev/null) || Existing=""
    fi
    if [[ -n "$Existing" ]]; then
        say "Ruleset '$Name' exists ($Existing)"
        return $Exit_Status_Success
    fi
    print -- "    \$ gh api -X POST repos/$GitHub_Repo/rulesets  # $Name"
    [[ "$Dry_Run" == true ]] && return $Exit_Status_Success
    print -r -- "$Json" | gh api -X POST "repos/$GitHub_Repo/rulesets" --input - >/dev/null
}

#----------------------------------------------------------------------#
# Function: parse_Parameters
#----------------------------------------------------------------------#
# Description:
#   Parses command line options into the script-scoped option variables
# Parameters:
#   $@ - Command line arguments
# Returns:
#   Exit_Status_Success, or exits via show_Usage
#----------------------------------------------------------------------#
parse_Parameters() {
    while (( $# > 0 )); do
        case "$1" in
            --path) (( $# > 1 )) || show_Usage; Repo_Path="$2"; shift 2 ;;
            --github) (( $# > 1 )) || show_Usage; GitHub_Repo="$2"; shift 2 ;;
            --human-key) (( $# > 1 )) || show_Usage; Human_Key="$2"; shift 2 ;;
            --human-principal) (( $# > 1 )) || show_Usage; Human_Principal="$2"; shift 2 ;;
            --device) (( $# > 1 )) || show_Usage; Device_Specs+=("$2"); shift 2 ;;
            --agent-key) (( $# > 1 )) || show_Usage; Agent_Key="$2"; shift 2 ;;
            --agent-principal) (( $# > 1 )) || show_Usage; Agent_Principal="$2"; shift 2 ;;
            --create-agent-key) Create_Agent_Key=true; shift ;;
            --cloud-key) (( $# > 1 )) || show_Usage; Cloud_Key="$2"; shift 2 ;;
            --no-github) Use_GitHub=false; shift ;;
            --allow-software-human-key) Allow_Software_Human_Key=true; shift ;;
            --allow-software-device-keys) Allow_Software_Device_Keys=true; shift ;;
            --dry-run) Dry_Run=true; shift ;;
            -h|--help) show_Usage ;;
            *) print -u2 "Error: Unknown argument '$1'"; show_Usage ;;
        esac
    done
}

#----------------------------------------------------------------------#
# Function: main
#----------------------------------------------------------------------#
# Description:
#   Runs every bootstrap step in order
# Parameters:
#   $@ - Command line arguments
# Returns:
#   Exit_Status_Success, or exits on the first failure
#----------------------------------------------------------------------#
main() {
    parse_Parameters "$@"
    check_Inputs
    step_Init
    step_Inception
    step_Human_Signer
    step_Devices
    step_Agent_Signer
    step_Cloud_Signer
    step_Roles
    step_Tooling
    step_Local_Claude
    step_Verify
    step_GitHub
    say "Done."
    if [[ "$Use_GitHub" == true ]]; then
        say "Next: install the Claude GitHub App on $GitHub_Repo:"
        print -- "    https://github.com/apps/claude/installations/select_target"
    fi
    return $Exit_Status_Success
}

main "$@"
