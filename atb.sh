#!/usr/bin/env bash
# Copyright (c) 2024 shmilee
# Copyright (c) 2013-2024 Laurent Cozic (laurent22)
# License: MIT

APPNAME=$(basename "$0" | sed "s/\.sh$//")

# ---------------------------------------------------------------------------
# Log functions
# ---------------------------------------------------------------------------
fn_no_color() {
    COFF=""
    BOLD=""
    BLUE=""
    GREEN=""
    YELLOW=""
    RED=""
}
fn_set_color() {
    # if in a tty, https://unix.stackexchange.com/questions/401934
    if [ -t 1 -a -t 2 ]; then
        COFF="\e[1;0m"
        BOLD="\e[1;1m"
        BLUE="${BOLD}\e[1;34m"
        GREEN="${BOLD}\e[1;32m"
        YELLOW="${BOLD}\e[1;33m"
        RED="${BOLD}\e[1;31m"
    else
        fn_no_color
    fi
}
fn_set_color  # default on
fn_log_info() { echo -e "${BLUE}[${APPNAME}]${COFF} $1"; }
fn_log_info_gb() { echo -e "${GREEN}[${APPNAME}]${COFF} ${BOLD}$1${COFF}"; }
fn_log_warn() {
    echo -e "${YELLOW}[${APPNAME^^}]${COFF} ${BOLD}WARNING: $1${COFF}" 1>&2
}
fn_log_error() {
    echo -e "${RED}[${APPNAME^^}]${COFF} ${BOLD}ERROR: $1${COFF}" 1>&2
}
fn_log_info_cmd() {
    if [ -n "$SSH_DEST_FOLDER_PREFIX" ]; then
        echo -e "${BLUE}[${APPNAME^}]${COFF} ${BOLD}$SSH_CMD '$1'${COFF}"
    else
        echo -e "${BLUE}[${APPNAME^}]${COFF} ${BOLD}$1${COFF}"
    fi
}

# ---------------------------------------------------------------------------
# Make sure everything really stops when CTRL+C is pressed
# ---------------------------------------------------------------------------
fn_terminate_script() { fn_log_info "SIGINT caught."; exit 1; }
trap 'fn_terminate_script' SIGINT

# ---------------------------------------------------------------------------
# Small utility functions for reducing code duplication
# ---------------------------------------------------------------------------
fn_display_usage() {
    echo "Usage: $(basename "$0") [OPTION]... <[USER@HOST:]SOURCE> <[USER@HOST:]DESTINATION>"
    echo ""
    echo "Options"
    echo " -p, --profile </local/path/to/profile>"
    echo "                       Specify a backup profile. The profile can be used to set"
    echo "                       SOURCE, DESTINATION, the binary of ssh and rsync,"
    echo "                       the flags of ssh and rsync, expiration strategy,"
    echo "                       auto-expire and filter rules for backup files."
    echo " --ssh-get-flags       Display the default SSH flags that are used for backup and exit."
    echo " --ssh-set-flags       Set the SSH flags that are used for backup."
    echo " --ssh-append-flags    Append the SSH flags that are going to be used for backup."
    echo " --rsync-get-flags     Display the default rsync flags that are used for backup and exit."
    echo "                       If using remote drive over SSH, --compress will be added."
    echo "                       If SOURCE or DESTINATION is on FAT, --modify-window=2 will be added."
    echo " --rsync-set-flags     Set the rsync flags that are used for backup."
    echo " --rsync-append-flags  Append the rsync flags that are going to be used for backup."
    echo " --strategy            Set the expiration strategy. Default: \"1:1 30:7 365:30\" means after one"
    echo "                       day, keep one backup per day. After 30 days, keep one backup every 7 days."
    echo "                       After 365 days keep one backup every 30 days."
    echo " --no-auto-expire      Disable automatically deleting backups when out of space. Instead an error"
    echo "                       is logged, and the backup is aborted."
    echo " --log-dir </path>     Set the log file directory. If this flag is set, generated files will"
    echo "                       not be managed by the script - in particular they will not be"
    echo "                       automatically deleted."
    echo "                       Default: $LOG_DIR"
    echo " --no-color            Disable colorizing the log info warn error output in a tty."
    echo " --init <DESTINATION>  Initialize <DESTINATION> by creating a backup marker file and exit."
    echo " -t, --time-travel </local/path/to/a/specific/file>"
    echo "                       List all versions of a specific file in a backup DESTINATION and exit."
    echo " -tig|--tig|--travel-in-git <GIT_REPO_DIR>"
    echo "                       Create a git repo and commit all versions of the specific file."
    echo "                       This is especially useful when the specific file is a text file."
    echo " -tib|--tib|--travel-in-browser <LINKS_DIR>"
    echo "                       Create links for all versions of the specific file in a directory."
    echo " -h, --help            Display this help message and exit."
    echo ""
    echo "For more detailed help, please see the README file:"
    echo "https://github.com/shmilee/arch-time-backup/blob/master/README.md"
    echo "https://github.com/laurent22/rsync-time-backup/blob/master/README.md"
}

fn_parse_date() {
    # Converts YYYY-MM-DD-HHMMSS to YYYY-MM-DD HH:MM:SS and then to Unix Epoch.
    case "$OSTYPE" in
        linux*|cygwin*|netbsd*)
            date -d "${1:0:10} ${1:11:2}:${1:13:2}:${1:15:2}" +%s ;;
        FreeBSD*) date -j -f "%Y-%m-%d-%H%M%S" "$1" "+%s" ;;
        darwin*)
            # Under MacOS X Tiger
            # Or with GNU 'coreutils' installed (by homebrew)
            #   'date -j' doesn't work, so we do this:
            yy=$(expr ${1:0:4})
            mm=$(expr ${1:5:2} - 1)
            dd=$(expr ${1:8:2})
            hh=$(expr ${1:11:2})
            mi=$(expr ${1:13:2})
            ss=$(expr ${1:15:2})
            perl -e 'use Time::Local; print timelocal('$ss','$mi','$hh','$dd','$mm','$yy'),"\n";' ;;
    esac
}

fn_find_backups() {
    fn_run_cmd "find "$DEST_FOLDER/" -maxdepth 1 -type d -name \"????-??-??-??????\" -prune | sort -r"
}

fn_expire_backup() {
    # Double-check that we're on a backup destination to be completely
    # sure we're deleting the right folder
    if [ -z "$(fn_find_backup_marker "$(dirname -- "$1")")" ]; then
        fn_log_error "$1 is not on a backup destination - aborting."
        exit 1
    fi
    fn_log_info "Expiring $1"
    fn_rm_dir "$1"
}

fn_expire_backups() {
    local current_timestamp=$EPOCH
    local last_kept_timestamp=9999999999
    # we will keep requested backup
    backup_to_keep="$1"
    # we will also keep the oldest backup
    oldest_backup_to_keep="$(fn_find_backups | sort | sed -n '1p')"
    # Process each backup dir from the oldest to the most recent
    for backup_dir in $(fn_find_backups | sort); do
        local backup_date=$(basename "$backup_dir")
        local backup_timestamp=$(fn_parse_date "$backup_date")
        # Skip if failed to parse date...
        if [ -z "$backup_timestamp" ]; then
            fn_log_warn "Could not parse date: $backup_dir"
            continue
        fi
        if [ "$backup_dir" == "$backup_to_keep" ]; then
            # this is the latest backup requsted to be kept. We can finish pruning
            break
        fi
        if [ "$backup_dir" == "$oldest_backup_to_keep" ]; then
            # We dont't want to delete the oldest backup. It becomes first "last kept" backup
            last_kept_timestamp=$backup_timestamp
            # As we keep it we can skip processing it and go to the next oldest one in the loop
            continue
        fi
        # Find which strategy token applies to this particular backup
        for strategy_token in $(echo $EXPIRATION_STRATEGY | tr " " "\n" | sort -r -n); do
            IFS=':' read -r -a t <<< "$strategy_token"
            # After which date (relative to today) this token applies (X) - we use seconds to get exact cut off time
            local cut_off_timestamp=$((current_timestamp - ${t[0]} * 86400))
            # Every how many days should a backup be kept past the cut off date (Y) - we use days (not seconds)
            local cut_off_interval_days=$((${t[1]}))
            # If we've found the strategy token that applies to this backup
            if [ "$backup_timestamp" -le "$cut_off_timestamp" ]; then
                # Special case: if Y is "0" we delete every time
                if [ $cut_off_interval_days -eq "0" ]; then
                    fn_expire_backup "$backup_dir"
                    break
                fi
                # we calculate days number since last kept backup
                local last_kept_timestamp_days=$((last_kept_timestamp / 86400))
                local backup_timestamp_days=$((backup_timestamp / 86400))
                local interval_since_last_kept_days=$((backup_timestamp_days - last_kept_timestamp_days))
                # Check if the current backup is in the interval between
                # the last backup that was kept and Y
                # to determine what to keep/delete we use days difference
                if [ "$interval_since_last_kept_days" -lt "$cut_off_interval_days" ]; then
                    # Yes: Delete that one
                    fn_expire_backup "$backup_dir"
                    # backup deleted no point to check shorter timespan strategies - go to the next backup
                    break
                else
                    # No: Keep it.
                    # this is now the last kept backup
                    last_kept_timestamp=$backup_timestamp
                    # and go to the next backup
                    break
                fi
            fi
        done
    done
}

fn_parse_profile() {
    local PRF="$1"
    if [ ! -f "${PRF}" ]; then
        fn_log_error "Profile not found: '${PRF}'!"
        exit 2
    fi
    local fname="$(basename "${PRF}")"
    local N0=$(awk '/FILTER_RULES_BEGIN/{print NR;exit}' "${PRF}")
    local N1=$(awk '/^[ ]*FILTER_RULES_BEGIN[ ]*$/{print NR;exit}' "${PRF}")
    local N2=$(awk '/^[ ]*FILTER_RULES_END[ ]*$/{print NR;exit}' "${PRF}")
    if [ -z "$N0" ]; then
        # No file-rules
        source "${PRF}"
    else
        local profile_source="$(mktemp -u -t "${fname}.source.$$.XXXXX")"
        if [ -n "$N1" -a -n "$N2" ]; then
            awk -v n1=$N1 -v n2=$N2 '{if((NR<n1)||(NR>n2)){print $0}}' \
                "${PRF}" >"${profile_source}"
            # filter part
            local filter="$(mktemp -u -t "${fname}.filter.$$.XXXXX")"
            awk -v n1=$N1 -v n2=$N2 '{if((n1<NR)&&(NR<n2)){print $0}}' \
                "${PRF}" >"${filter}"
            FILTER_RULES="${filter}"
            trap "rm -f -- '${filter}'" EXIT
        else
            awk -v n=$N0 '{if(NR<n){print $0}}' "${PRF}" >"${profile_source}"
        fi
        source "${profile_source}"
        rm -f -- "${profile_source}"
    fi
    SRC_FOLDER="${SOURCE}"
    DEST_FOLDER="${DESTINATION}"
    unset SOURCE DESTINATION
    #SSH_BIN, RSYNC_BIN
    #SSH_FLAGS, RSYNC_FLAGS,
    #EXPIRATION_STRATEGY, AUTO_EXPIRE
}

fn_parse_ssh() {
    # To keep compatibility with bash version < 3, we use grep
    if echo "$DEST_FOLDER" | grep -Eq '^[A-Za-z0-9\._%\+\-]+@[A-Za-z0-9.\-]+:.+$'; then
        SSH_USER=$(echo "$DEST_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\1/')
        SSH_HOST=$(echo "$DEST_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\2/')
        SSH_DEST_FOLDER=$(echo "$DEST_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\3/')
        SSH_CMD="$SSH_BIN $SSH_FLAGS ${SSH_USER}@${SSH_HOST}"
        SSH_DEST_FOLDER_PREFIX="${SSH_USER}@${SSH_HOST}:"
    elif echo "$SRC_FOLDER" | grep -Eq '^[A-Za-z0-9\._%\+\-]+@[A-Za-z0-9.\-]+:.+$'; then
        SSH_USER=$(echo "$SRC_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\1/')
        SSH_HOST=$(echo "$SRC_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\2/')
        SSH_SRC_FOLDER=$(echo "$SRC_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\3/')
        SSH_CMD="$SSH_BIN $SSH_FLAGS ${SSH_USER}@${SSH_HOST}"
        SSH_SRC_FOLDER_PREFIX="${SSH_USER}@${SSH_HOST}:"
    fi
}

fn_check_BIN() {
    if ! hash "$1" &>/dev/null; then
        fn_log_error "Command not found: '$1'!"
        exit 3
    fi
}

fn_run_cmd() {
    if [ -n "$SSH_DEST_FOLDER_PREFIX" ]; then
        eval "$SSH_CMD '$1'"
    else
        eval $1
    fi
}

fn_run_cmd_src() {
    if [ -n "$SSH_SRC_FOLDER_PREFIX" ]; then
        eval "$SSH_CMD '$1'"
    else
        eval $1
    fi
}

fn_find() { fn_run_cmd "find '$1'"  2>/dev/null; }
fn_get_absolute_path() { fn_run_cmd "cd '$1'; pwd"; }
fn_mkdir() { fn_run_cmd "mkdir -p -- '$1'"; }
fn_rm_file() { fn_run_cmd "rm -f -- '$1'"; } # rm a file,symlink - not dir
fn_rm_dir() { fn_run_cmd "rm -rf -- '$1'"; }
fn_touch() { fn_run_cmd "touch -- '$1'"; }
fn_ln() { fn_run_cmd "ln -s -- '$1' '$2'"; }
fn_test_file_exists_src() { fn_run_cmd_src "test -e '$1'"; }
fn_df_t_src() { fn_run_cmd_src "df -T '${1}/'"; }
fn_df_t() { fn_run_cmd "df -T '${1}/'"; }
fn_backup_marker_path() { echo "$1/backup.marker"; }
fn_find_backup_marker() { fn_find "$(fn_backup_marker_path "$1")" 2>/dev/null; }

fn_initialize_dest() {
    DEST_FOLDER="${1%/}"
    fn_parse_ssh
    if [ -n "$SSH_DEST_FOLDER" ]; then  # remote DEST
        fn_check_BIN "$SSH_BIN"
        DEST_FOLDER="$SSH_DEST_FOLDER"
    fi
    local Marker="$(fn_find_backup_marker "$DEST_FOLDER")"
    if [ -z "$Marker" ]; then
        local marker_path="$(fn_backup_marker_path "$DEST_FOLDER")"
        fn_log_info "Running commands:"
        fn_log_info_cmd "mkdir -p -- '$DEST_FOLDER'"
        fn_mkdir "$DEST_FOLDER"
        fn_log_info_cmd "touch -- '$marker_path'"
        fn_touch "$marker_path"
        exit
    else
        fn_log_info "A backup marker is found in '$1'!"
        fn_log_warn "The backup DESTINATION folder has been initialized!"
        exit 1
    fi
}

fn_local_fileinode() {
    (
        ls -i "$1" 2>/dev/null ||
        find "$1" -printf "%i" 2>/dev/null ||
        stat -c%i -- "$1" 2>/dev/null ||
        stat -f%i -- "$1" 2>/dev/null
    ) | awk '{print $1}'
}

fn_local_filesize() {  # in bytes
    (
        find "$1" -printf "%s" 2>/dev/null ||
        stat --printf="%s" -- "$1" 2>/dev/null ||
        stat -c%s -- "$1" 2>/dev/null ||
        stat -f%z -- "$1" 2>/dev/null
    ) | awk '{print $1}'
}

fn_time_travel() {
    # ref: https://github.com/uglygus/rsync-time-browse
    local specific="$TRAVEL_SPEC_FILE"
    if [ ! -f "$specific" ]; then
        if [ -d "$specific" ]; then
            fn_log_error "Directory not supported: '$specific'"
        elif echo "$specific" | grep -Eq '^[A-Za-z0-9\._%\+\-]+@[A-Za-z0-9.\-]+:.+$'; then
            fn_log_error "Remote path not supported: '$specific'"
        else
            fn_log_error "File not found: '$specific'"
        fi
        exit 4
    fi
    # 1. find DESTINATION folder containing 'backup.marker'
    specific="$(realpath "$specific")"  # symlink or relative resolved
    local DEST_FOLDER="$(dirname "$specific")"
    while [ "$DEST_FOLDER" != '/' ]; do
        #fn_log_info "Checking DEST_FOLDER = $DEST_FOLDER"
        if [ -f "$(fn_backup_marker_path "$DEST_FOLDER")" ]; then
            break
        fi
        # walk back
        DEST_FOLDER="$(dirname "$DEST_FOLDER")"
    done
    if [ "$DEST_FOLDER" = '/' ]; then
        fn_log_error "Cannot find backup marker path for '$specific'"
        exit 4
    else
        fn_log_info "The Backup DESTINATION is $DEST_FOLDER"
    fi
    # 2. check date/time pattern, get relative file path
    local datepattern="[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}"  # -E
    if ! echo "${specific}" | grep -Eq "$DEST_FOLDER/$datepattern/"; then
        fn_log_error "Unable to determine the date version of: '${specific}'"
        exit 4
    fi
    local DATEVER="$(echo "${specific}" | sed -E "s|^$DEST_FOLDER/($datepattern)/.*$|\1|")"
    local REL_APTH="$(echo "${specific}" | sed -E "s|^$DEST_FOLDER/$datepattern/(.*)$|\1|")"
    #local REL_APTH=${specific#$DEST_FOLDER/????-??-??-??????/}
    fn_log_info "Specific Version:       $DATEVER"
    fn_log_info "Specific Relative Path: $REL_APTH"
    # 3. get the date/time folder names for backup folders
    local BACKUP_NAMES=($(fn_find_backups "$DEST_FOLDER" | sort))
    local DATE_VERSIONS=()
    for back in ${BACKUP_NAMES[@]}; do
        if [ -f "$back/$REL_APTH" ]; then
            DATE_VERSIONS+=("$(basename $back)")
        fi
    done
    fn_log_info_gb "Found ${GREEN}${#BACKUP_NAMES[@]}${COFF} whole backups and the specific file has ${GREEN}${#DATE_VERSIONS[@]}${COFF} backups."
    # 4. process date versions from oldest to latest, get and show unique files
    #    compared by file inode, faster than size or hash
    #local pre_size=""
    #local pre_hash=""  # md5
    local pre_inode=""
    local UNIQ_VERSIONS=()  # date of unique files
    local size_max=$((100*1024*1024))  # in bytes, show file md5 when its size<size_max(100M)
    for datever in ${DATE_VERSIONS[@]}; do
        local file="$DEST_FOLDER/$datever/$REL_APTH"
        #this_size="$(fn_local_filesize "$file")"
        #this_hash="$(md5sum "$file" | awk '{print $1}')"
        #if [ "$this_size" != "$pre_size" -o "$this_hash" != "$pre_hash" ];
        #    UNIQ_VERSIONS+=("$datever")
        #fi
        local this_inode=$(fn_local_fileinode "$file")
        if [ "$this_inode" != "$pre_inode" ]; then
            local this_size="$(fn_local_filesize "$file")"
            local this_hash=""
            if [ "$this_size" -lt $size_max ]; then
                this_hash=", md5=$(md5sum "$file" | awk '{print $1}')"
            fi
            fn_log_info_gb "\t$datever: inode=$this_inode$this_hash, size=$this_size"
            UNIQ_VERSIONS+=("$datever")
        else
            fn_log_info "\t$datever: inode=$this_inode"
        fi
        pre_inode=$this_inode
    done
    fn_log_info_gb "Found ${GREEN}${#UNIQ_VERSIONS[@]}${COFF} versions of the specific file."
    if [ "${#UNIQ_VERSIONS}" -lt 2 ]; then
        fn_log_info_gb "Less than 2 versions to compare!"
        exit
    fi
    # 5. prepare TRAVEL_GIT_REPO TRAVEL_LINKS_DIR
    local GIT_action   # ln, cp. depends on TRAVEL_GIT_REPO mountpoint (mp)
    local LDIR_action  # ln, ln-s. depends on TRAVEL_LINKS_DIR mountpoint
    local DEST_mp="$(df "$DEST_FOLDER" | awk '{if(NR==2){print $6}}')"
    if [ -n "$TRAVEL_GIT_REPO" ]; then
        if [ -d "$TRAVEL_GIT_REPO" ]; then
            fn_log_error "Git repository '$TRAVEL_GIT_REPO' exists! Skip to create the repository!"
        else
            git init -q -b master "$TRAVEL_GIT_REPO"
            local git_mp="$(df "$TRAVEL_GIT_REPO" | awk '{if(NR==2){print $6}}')"
            #fn_log_info "mountpoint: DEST($DEST_mp) vs git($git_mp)"
            if [ "$DEST_mp" = "$git_mp" ]; then
                GIT_action='ln'
            else
                GIT_action='cp'
            fi
        fi
    fi
    if [ -n "$TRAVEL_LINKS_DIR" ]; then
        if [ -d "$TRAVEL_LINKS_DIR" ]; then
            fn_log_error "Directory '$TRAVEL_LINKS_DIR' exists! Skip to create links for file versions!"
        else
            mkdir -p -- "$TRAVEL_LINKS_DIR"
            local ldir_mp="$(df "$TRAVEL_LINKS_DIR" | awk '{if(NR==2){print $6}}')"
            #fn_log_info "mountpoint: DEST($DEST_mp) vs link-dir($ldir_mp)"
            if [ "$DEST_mp" = "$ldir_mp" ]; then
                LDIR_action='ln'
            else
                LDIR_action='ln-s'
            fi
        fi
    fi
    #fn_log_info "GIT_action=$GIT_action, LDIR_action=$LDIR_action"
    # 6. ln or cp unique files
    if [ "$GIT_action" != "" -o "$LDIR_action" != "" ]; then
        local base="$(basename "$REL_APTH")"
        for datever in ${UNIQ_VERSIONS[@]}; do
            local file="$DEST_FOLDER/$datever/$REL_APTH"
            # git repo
            if [ "$GIT_action" != "" ]; then
                if [ "$GIT_action" = "ln" ]; then
                    ln -f "$file" "$TRAVEL_GIT_REPO/$base"
                elif [ "$GIT_action" = "cp" ]; then
                    cp -f "$file" "$TRAVEL_GIT_REPO/$base"
                fi
                (
                    cd "$TRAVEL_GIT_REPO" &&
                        git add "$base" &&
                        git commit -q -m "$datever" -m "$file"
                )
            fi
            # links-dir
            if [ "$LDIR_action" != "" ]; then
                if [ "$LDIR_action" = "ln" ]; then
                    ln "$file" "$TRAVEL_LINKS_DIR/${datever}-${base}"
                elif [ "$LDIR_action" = "ln-s" ]; then
                    ln -s "$file" "$TRAVEL_LINKS_DIR/${datever}-${base}"
                fi
            fi
        done
        if [ "$GIT_action" != "" ]; then
            fn_log_info "TRAVEL_GIT_REPO  ${YELLOW}$TRAVEL_GIT_REPO${COFF} is ready."
        fi
        if [ "$LDIR_action" != "" ]; then
            fn_log_info "TRAVEL_LINKS_DIR ${YELLOW}$TRAVEL_LINKS_DIR${COFF} is ready."
        fi
    else
        local i=1
        for datever in ${UNIQ_VERSIONS[@]}; do
            fn_log_info " $i) $DEST_FOLDER/$datever/$REL_APTH"
            ((i++))
        done
    fi
}

# ---------------------------------------------------------------------------
# Source and destination information
# ---------------------------------------------------------------------------
SSH_USER=""
SSH_HOST=""
SSH_DEST_FOLDER=""
SSH_SRC_FOLDER=""
SSH_DEST_FOLDER_PREFIX=""
SSH_SRC_FOLDER_PREFIX=""
SSH_BIN="ssh"
SSH_FLAGS="-o ServerAliveInterval=60"
SSH_CMD=""

SRC_FOLDER=""
DEST_FOLDER=""
FILTER_RULES=""
LOG_DIR="$HOME/.$APPNAME"
AUTO_DELETE_LOG="1"
EXPIRATION_STRATEGY="1:1 30:7 365:30"
AUTO_EXPIRE="1"

RSYNC_BIN="rsync"
RSYNC_FLAGS="-D --numeric-ids --links --hard-links --one-file-system --itemize-changes --times --recursive --perms --owner --group --stats --human-readable"

TRAVEL_SPEC_FILE=""
TRAVEL_GIT_REPO=""
TRAVEL_LINKS_DIR=""

while :; do
    case $1 in
        -h|--help)
            fn_display_usage
            exit
            ;;
        -p|--profile)
            shift
            fn_parse_profile "$1"
            ;;
        --ssh-get-flags)
            shift
            echo "$SSH_FLAGS"
            exit
            ;;
        --ssh-set-flags)
            shift
            SSH_FLAGS="$1"
            ;;
        --ssh-append-flags)
            shift
            SSH_FLAGS="$SSH_FLAGS $1"
            ;;
        --rsync-get-flags)
            shift
            echo "$RSYNC_FLAGS"
            exit
            ;;
        --rsync-set-flags)
            shift
            RSYNC_FLAGS="$1"
            ;;
        --rsync-append-flags)
            shift
            RSYNC_FLAGS="$RSYNC_FLAGS $1"
            ;;
        --strategy)
            shift
            EXPIRATION_STRATEGY="$1"
            ;;
        --no-auto-expire)
            AUTO_EXPIRE="0"
            ;;
        --log-dir)
            shift
            LOG_DIR="$1"
            AUTO_DELETE_LOG="0"
            ;;
        --no-color)
            shift
            fn_no_color
            ;;
        --init)
            shift
            fn_initialize_dest "$1"
            exit
            ;;
        -t|--time-travel)
            shift
            TRAVEL_SPEC_FILE="$1"
            ;;
        -tig|--tig|--travel-in-git)
            shift
            TRAVEL_GIT_REPO="$(realpath "$1")"
            ;;
        -tib|--tib|--travel-in-browser)
            shift
            TRAVEL_LINKS_DIR="$(realpath "$1")"
            ;;
        --)
            shift
            SRC_FOLDER="${1:-$SRC_FOLDER}"
            DEST_FOLDER="${2:-$DEST_FOLDER}"
            break
            ;;
        -*)
            fn_log_error "Unknown option: \"$1\""
            fn_display_usage
            exit 1
            ;;
        *)
            SRC_FOLDER="${1:-$SRC_FOLDER}"
            DEST_FOLDER="${2:-$DEST_FOLDER}"
            break
    esac

    shift
done

# time travel of specific file, then exit
if [ -n "$TRAVEL_SPEC_FILE" ]; then
    fn_time_travel
    exit
fi

# Display usage information if required arguments are not passed
if [[ -z "$SRC_FOLDER" || -z "$DEST_FOLDER" ]]; then
    fn_display_usage
    exit 1
fi

# Show info
echo
fn_log_info "Backup Information"
cat <<EOF

  SOURCE       = ${SRC_FOLDER}
  DESTINATION  = ${DEST_FOLDER}
  FILTER_RULES = ${FILTER_RULES}
  SSH_FLAGS    = ${SSH_FLAGS}
  RSYNC_FLAGS  = ${RSYNC_FLAGS}
  AUTO_EXPIRE  = ${AUTO_EXPIRE}
  EXPIRATION_STRATEGY  = ${EXPIRATION_STRATEGY}

EOF

# Strips off last slash from dest. Note that it means the root folder "/"
# will be represented as an empty string "", which is fine
# with the current script (since a "/" is added when needed)
# but still something to keep in mind.
# However, due to this behavior we delay stripping the last slash for
# the source folder until after parsing for ssh usage.

DEST_FOLDER="${DEST_FOLDER%/}"

fn_parse_ssh
if [ -n "$SSH_CMD" ]; then
    fn_check_BIN "$SSH_BIN"
fi
fn_check_BIN "$RSYNC_BIN"

if [ -n "$SSH_DEST_FOLDER" ]; then
    DEST_FOLDER="$SSH_DEST_FOLDER"
fi

if [ -n "$SSH_SRC_FOLDER" ]; then
    SRC_FOLDER="$SSH_SRC_FOLDER"
fi

# Exit if source folder does not exist.
if ! fn_test_file_exists_src "${SRC_FOLDER}"; then
    fn_log_error "Source folder \"${SRC_FOLDER}\" does not exist - aborting."
    exit 1
fi

# Now strip off last slash from source folder.
SRC_FOLDER="${SRC_FOLDER%/}"

for ARG in "$SRC_FOLDER" "$DEST_FOLDER"; do
    if [[ "$ARG" == *"'"* ]]; then
        fn_log_error 'Source and destination directories may not contain single quote characters.'
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Check that the destination drive is a backup drive
# ---------------------------------------------------------------------------
# TODO: check that the destination supports hard links
if [ -z "$(fn_find_backup_marker "$DEST_FOLDER")" ]; then
    fn_log_info "Safety check failed - the destination does not appear to be a backup folder or drive (marker file not found)."
    fn_log_info "If it is indeed a backup folder, you may add the marker file by running the following command:"
    fn_log_info ""
    fn_log_info_cmd "mkdir -p -- \"$DEST_FOLDER\" ; touch \"$(fn_backup_marker_path "$DEST_FOLDER")\""
    fn_log_info ""
    exit 1
fi

# Check source and destination file-system (df -T /dest).
# If one of them is FAT, use the --modify-window rsync parameter
# (see man rsync) with a value of 1 or 2.
# The check is performed by taking the second row
# of the output of the first command.
if [[ "$(fn_df_t_src "${SRC_FOLDER}" | awk '{print $2}' | grep -c -i -e "fat")" -gt 0 ]]; then
    fn_log_info "Source file-system is a version of FAT."
    fn_log_info "Using the --modify-window rsync parameter with value 2."
    RSYNC_FLAGS="${RSYNC_FLAGS} --modify-window=2"
elif [[ "$(fn_df_t "${DEST_FOLDER}" | awk '{print $2}' | grep -c -i -e "fat")" -gt 0 ]]; then
    fn_log_info "Destination file-system is a version of FAT."
    fn_log_info "Using the --modify-window rsync parameter with value 2."
    RSYNC_FLAGS="${RSYNC_FLAGS} --modify-window=2"
fi

# ---------------------------------------------------------------------------
# Setup additional variables
# ---------------------------------------------------------------------------
# Date logic
NOW=$(date +"%Y-%m-%d-%H%M%S")
EPOCH=$(date "+%s")
KEEP_ALL_DATE=$((EPOCH - 86400))       # 1 day ago
KEEP_DAILIES_DATE=$((EPOCH - 2678400)) # 31 days ago

export IFS=$'\n' # Better for handling spaces in filenames.
DEST="$DEST_FOLDER/$NOW"
PREVIOUS_DEST="$(fn_find_backups | head -n 1)"
INPROGRESS_FILE="$DEST_FOLDER/backup.inprogress"
MYPID="$$"

# ---------------------------------------------------------------------------
# Create log folder if it doesn't exist
# ---------------------------------------------------------------------------
if [ ! -d "$LOG_DIR" ]; then
    fn_log_info "Creating log folder in '$LOG_DIR'..."
    mkdir -- "$LOG_DIR"
fi

# ---------------------------------------------------------------------------
# Handle case where a previous backup failed or was interrupted.
# ---------------------------------------------------------------------------
if [ -n "$(fn_find "$INPROGRESS_FILE")" ]; then
    if [ "$OSTYPE" == "cygwin" ]; then
        # 1. Grab the PID of previous run from the PID file
        RUNNINGPID="$(fn_run_cmd "cat $INPROGRESS_FILE")"
        # 2. Get the command for the process currently running under that PID and look for our script name
        RUNNINGCMD="$(procps -wwfo cmd -p $RUNNINGPID --no-headers | grep "$APPNAME")"
        # 3. Grab the exit code from grep (0=found, 1=not found)
        GREPCODE=$?
        # 4. if found, assume backup is still running
        if [ "$GREPCODE" = 0 ]; then
            fn_log_error "Previous backup task is still active - aborting (command: $RUNNINGCMD)."
            exit 1
        fi
    elif [[ "$OSTYPE" == "netbsd"* ]]; then
        RUNNINGPID="$(fn_run_cmd "cat $INPROGRESS_FILE")"
        if ps -axp "$RUNNINGPID" -o "command" | grep "$APPNAME" > /dev/null; then
            fn_log_error "Previous backup task is still active - aborting."
            exit 1
        fi
    else
        RUNNINGPID="$(fn_run_cmd "cat $INPROGRESS_FILE")"
        if ps -p "$RUNNINGPID" -o command | grep "$APPNAME"; then
            fn_log_error "Previous backup task is still active - aborting."
            exit 1
        fi
    fi

    if [ -n "$PREVIOUS_DEST" ]; then
        # - Last backup is moved to current backup folder so that it can be resumed.
        # - 2nd to last backup becomes last backup.
        fn_log_info "$SSH_DEST_FOLDER_PREFIX$INPROGRESS_FILE already exists - the previous backup failed or was interrupted. Backup will resume from there."
        fn_run_cmd "mv -- $PREVIOUS_DEST $DEST"
        if [ "$(fn_find_backups | wc -l)" -gt 1 ]; then
            PREVIOUS_DEST="$(fn_find_backups | sed -n '2p')"
        else
            PREVIOUS_DEST=""
        fi
        # update PID to current process to avoid multiple concurrent resumes
        fn_run_cmd "echo $MYPID > $INPROGRESS_FILE"
    fi
fi

# Run in a loop to handle the "No space left on device" logic.
while : ; do
    # -----------------------------------------------------------------------
    # Check if we are doing an incremental backup (if previous backup exists).
    # -----------------------------------------------------------------------
    LINK_DEST_OPTION=""
    if [ -z "$PREVIOUS_DEST" ]; then
        fn_log_info "No previous backup - creating new one."
    else
        # If the path is relative, it needs to be relative to the destination. To keep
        # it simple, just use an absolute path. See http://serverfault.com/a/210058/118679
        PREVIOUS_DEST="$(fn_get_absolute_path "$PREVIOUS_DEST")"
        fn_log_info "Previous backup found - doing incremental backup from $SSH_DEST_FOLDER_PREFIX$PREVIOUS_DEST"
        LINK_DEST_OPTION="--link-dest='$PREVIOUS_DEST'"
    fi

    # -----------------------------------------------------------------------
    # Purge certain old backups before beginning new backup.
    # -----------------------------------------------------------------------
    if [ -n "$PREVIOUS_DEST" ]; then
        # regardless of expiry strategy keep backup used for --link-dest
        fn_expire_backups "$PREVIOUS_DEST"
    else
        # keep latest backup
        fn_expire_backups "$DEST"
    fi

    # -----------------------------------------------------------------------
    # Start backup
    # -----------------------------------------------------------------------
    # Create destination folder if it doesn't already exists
    if [ -z "$(fn_find "$DEST -type d" 2>/dev/null)" ]; then
        fn_log_info "Creating destination $SSH_DEST_FOLDER_PREFIX$DEST"
        if ! fn_mkdir "$DEST"; then
            fn_log_error "Failed to create destination!"
            exit 4
        fi
    fi

    LOG_FILE="$LOG_DIR/$(date +"%Y-%m-%d-%H%M%S").log"
    CMD="$RSYNC_BIN $RSYNC_FLAGS --log-file '$LOG_FILE'"
    if [ -n "$SSH_CMD" ]; then
        RSYNC_FLAGS="$RSYNC_FLAGS --compress"
        CMD="$CMD -e '$SSH_BIN $SSH_FLAGS'"
    fi
    if [ -f "$FILTER_RULES" ]; then
        CMD="$CMD --filter='merge $FILTER_RULES'"
    fi
    CMD="$CMD $LINK_DEST_OPTION"
    CMD="$CMD -- '$SSH_SRC_FOLDER_PREFIX$SRC_FOLDER/' '$SSH_DEST_FOLDER_PREFIX$DEST/'"
    fn_log_info "Starting backup ..."
    fn_log_info "From: $SSH_SRC_FOLDER_PREFIX$SRC_FOLDER/"
    fn_log_info "To:   $SSH_DEST_FOLDER_PREFIX$DEST/"
    fn_log_info "Running command:"
    fn_log_info "  $CMD"
    echo

    fn_run_cmd "echo $MYPID > $INPROGRESS_FILE"
    eval $CMD
    CMD_RETURNCODE=$?
    if [ -f "$FILTER_RULES" ]; then
        rm -f -- "$FILTER_RULES"
    fi

    # -----------------------------------------------------------------------
    # Check if we ran out of space
    # -----------------------------------------------------------------------
    NO_SPACE_LEFT="$(grep "No space left on device (28)\|Result too large (34)" "$LOG_FILE")"
    if [ -n "$NO_SPACE_LEFT" ]; then
        if [[ $AUTO_EXPIRE == "0" ]]; then
            fn_log_error "No space left on device, and automatic purging of old backups is disabled."
            exit 1
        fi
        fn_log_warn "No space left on device - removing oldest backup and resuming."
        if [[ "$(fn_find_backups | wc -l)" -lt "2" ]]; then
            fn_log_error "No space left on device, and no old backup to delete."
            exit 1
        fi
        fn_expire_backup "$(fn_find_backups | tail -n 1)"
        # Resume backup
        continue
    fi

    # -----------------------------------------------------------------------
    # Check whether rsync reported any errors
    # -----------------------------------------------------------------------
    EXIT_CODE="1"
    if [ -n "$(grep "rsync error:" "$LOG_FILE")" ]; then
        fn_log_error "Rsync reported an error, backup failed."
    elif [ $CMD_RETURNCODE -ne 0 ]; then
        fn_log_error "Rsync returned non-zero return code, backup failed."
    elif [ -n "$(grep "rsync:" "$LOG_FILE")" ]; then
        fn_log_warn "Rsync reported a warning, backup failed."
    else
        fn_log_info_gb "Backup completed without errors."
        EXIT_CODE="0"
    fi
    if [ "$EXIT_CODE" = 0 ]; then
        if [[ $AUTO_DELETE_LOG == "1" ]]; then
            rm -f -- "$LOG_FILE"
        fi
    else
        fn_log_error "Run this command for more details: grep -E 'rsync:|rsync error:' '$LOG_FILE'"
    fi

    # -----------------------------------------------------------------------
    # Add symlink to last backup
    # -----------------------------------------------------------------------
    if [ "$EXIT_CODE" = 0 ]; then
        # Create the latest symlink only when rsync succeeded
        fn_rm_file "$DEST_FOLDER/latest"
        fn_ln "$(basename -- "$DEST")" "$DEST_FOLDER/latest"
        # Remove .inprogress file only when rsync succeeded
        fn_rm_file "$INPROGRESS_FILE"
    fi

    exit $EXIT_CODE
done
