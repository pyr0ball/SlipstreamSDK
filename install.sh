#!/bin/bash
###################################################################
#               Slipstream Foundation SDK Installer               #
###################################################################

# initial vars
VERSION=0.0.1
installdir="/opt/SlipstreamSDK"

# Escape characters (if your shell uses a different one, you can modify it here)
# By default this is using the usual bash escape code
ESC=$( printf '\033')

# Detect OS type
case $OSTYPE in 
  linux-gnu* ) ESC=$( printf '\033') ;;
  darwin* ) ESC=$( printf '\e') ;;
  cygwin ) ESC=$( printf '\033') ;;
  msys ) ESC=$( printf '\033') ;;
esac

# Bash expansions to get the name and location of this script when run
scriptname="${BASH_SOURCE[0]##*/}"
rundir="${BASH_SOURCE[0]%/*}"

# Store functions revision in a variable to compare with if already installed
installer_functionsrev=$functionsrev
required_functionsrev=1.6.0

# Source PRbL Functions locally or retrieve from online
if [ -n "$prbl_functions" ]; then
    source "$prbl_functions"
    vercompare=$(vercomp "$installer_functionsrev" "$required_functionsrev")
    if [[ $vercompare == 2 ]]; then
        prbl_functions_url='https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions'
        # Iterate through get commands and fall back on next if unavailable
        for cmd in "curl" "wget" "fetch"; do
            if command -v "$cmd" >/dev/null 2>&1; then
                source <("$cmd" -ks "$prbl_functions_url")
                break
            fi
        done
    fi
else
    if [ -f "${rundir}/functions" ]; then
        source "${rundir}/functions"
    else
        prbl_functions_url='https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions'
        for cmd in "curl" "wget" "fetch"; do
            if command -v "$cmd" >/dev/null 2>&1; then
                source <("$cmd" -ks "$prbl_functions_url")
                break
            fi
        done
    fi
fi

script_title="$(center "Slipstream Foundation SDK Installer - v$VERSION")"
rundir_absolute=$(pushd $rundir ; pwd ; popd)
escape_dir=$(printf %q "${rundir_absolute}")
logfile="${rundir}/${pretty_date}_${scriptname}.log"
# Set light blue borders
brdr=${gry}

# Pull in the versios file
source $rundir/VERSIONS

#-----------------------------------------------------------------#
# Script-specific Parameters
#-----------------------------------------------------------------#


# Get and store the user currently executing this script
runuser=$(whoami)

# set up an array containing the users listed under /home/
users=()
users=($(ls /home/))

# If run as non-root, default install to user's home directory
userinstalldir="$HOME/.local/share/SlipstreamSDK"

# If run as root, this will be the install directory
globalinstalldir="/opt/SlipstreamSDK"

# Initialize arrays for file and dependency management
bins_missing=()
backup_files=()
installed_files=()
installed_dirs=()

# Dependencies
sys_packages=()
sys_packages=(
    git
    curl
    python3
    python3-pip
    cmake
    libgmp3-dev
    libgtk-3-dev
)

pip_packages=()
pip_packages=(
    pyparsing==3.0.9
    gitpython
)

repo_packages=()
repo_packages=(
    BruceDLong/CodeDog
    BruceDLong/Proteus
    BruceDLong/Slipstream
)

prbl_packages=()
prbl_packages=(
    golang.install
)

# This variable is what is injected into the bashrc
bashrc_append="
# Pluggable bashrc config. Add environment modifications to ~/.bashrc.d/ and append with '.bashrc'
if [ -n \"\$BASH_VERSION\" ]; then
    # include .bashrc if it exists
    if [ -d \"\$HOME/.bashrc.d\" ]; then
        for file in \$HOME/.bashrc.d/*.bashrc ; do
            source \"\$file\"
        done
    fi
fi
"

#-----------------------------------------------------------------#
# Script-specific Funcitons
#-----------------------------------------------------------------#
# SlipStream Colors
ss1="${ESC}[38;5;87m"
ss2="${ESC}[38;5;51m"
ss3="${ESC}[38;5;45m"
ss4="${ESC}[38;5;39m"
ss5="${ESC}[38;5;33m"
ss6="${ESC}[38;5;254m"
ss7="${ESC}[38;5;252m"
ss8="${ESC}[38;5;248m"
ss9="${ESC}[38;5;244m"
ss10="${ESC}[38;5;240m"

script-title(){
    boxborder \
"${ss1}           ___          _    _                                        ${dfl}" \
"${ss2}          |       |         | |           |                           ${dfl}" \
"${ss3}           -+-    +     +   |-       -   -+-  |-     -     -    |- -  ${dfl}" \
"${ss4}              |   |     |   |        \    |   |     |/    | |   | | | ${dfl}" \
"${ss5}           ---    -                  -     -         --    --         ${dfl}" \
"${ss6}                                ___   ___                             ${dfl}" \
"${ss7}                               |       | | |  /                       ${dfl}" \
"${ss8}                                -+-    + | |-+                        ${dfl}" \
"${ss9}                                   |   | | |  \                       ${dfl}" \
"${ss10}                                ---   ---                            ${dfl}"
}

# Function for displaying the usage of this script
usage(){
    script-title
    boxborder \
        "${script_title}" \
        "${lbl}Usage:${dfl}" \
        "${lyl}./$scriptname ${bld}[args]${dfl}" \
        "$(boxseparator)" \
        "[args:]" \
        "   -i [--install]" \
        "   -d [--dependencies]" \
        "   -D [--dry-run]" \
        "   -r [--remove]" \
        "   -f [--force]" \
        "   -F [--force-remove]" \
        "   -u [--update]" \
        "   -h [--help]" 
}

detectvim(){
    # If the vim install directory exists, check for and store the highest numerical value version installed
    if [[ -d /usr/share/vim ]] ; then
        viminstall=$(ls -lah /usr/share/vim/ | grep vim | grep -v rc | awk '{print $NF}' | tail -n 1)
        logger boxline "Vim detected at $viminstall"
    else
        viminstall=null
        warn "vim is not currently installed, unable to set up colorscheme and formatting"
    fi
}

check-deps(){
    # Iterate through the list of required packages and check if installed
    for pkg in "${sys_packages[@]}" ; do
        pkg_installed=$(check-packages $pkg)
        if ! $pkg_installed ; then
            case $pkg_installed in
                1) logger boxline "Installed version of $pkg is out of date" ;;
                2) logger boxline "Package $pkg is not installed" ;;
                3) logger boxline "Installed version of $pkg is newer than available" ;;
            esac
            bins_missing+=($pkg)
        fi
    done
    if ! command -v python3 >/dev/null 2>&1 ; then
        brdr=${ong}
        logger boxline "Python3 is not currently installed or is not available on \$PATH"
        logger boxline "Adding python3 package to deps list"
        brdr=${dfl}
        bins_missing+=(python3)
    fi

    if ! command -v pip3 >/dev/null 2>&1 ; then
        brdr=${ong}
        logger boxline "Pip is not currently installed or is not available on \$PATH"
        logger boxline "Adding pip3 package to deps list"
        brdr=${dfl}
        bins_missing+=(pip3)
    else
        for pkg in "${pip_packages[@]}" ; do
            if ! pip show "$pkg" >/dev/null 2>&1 ; then
                brdr=${ong}
                logger boxline "Required pip package $pkg is not currently installed"
                logger boxline "Adding package $pkg to pip deps list"
                brdr=${dfl}
                bins_missing+=("pip: $pkg")
            fi
        done
    fi

    # This installer requires golang to work
    # TODO: better handling of prbl_packages as dependencies
    if ! command -v go >/dev/null 2>&1 ; then
        brdr=${ong}
        logger boxline "golang v19.x is required for Slipstream and is not currently installed"
        logger boxline "Adding golang to deps list"
        brdr=${dfl}
        bins_missing+=("prbl: golang.install")
    fi
    # Count the number of entries in bins_missing
    local _bins_missing=${#bins_missing[@]}
    # If higher than 0, return a fail (1)
    if [[ $_bins_missing != 0 ]] ; then
        logger boxline "Dependencies missing >: $_bins_missing"
        for pkg in ${bins_missing[@]} ; do
            logger boxline "        >: $pkg"
        done
    fi
    return ${_bins_missing}
}

install-deps(){
    logger echo "${grn}Installing packages:${lyl} $sys_packages${dfl}"
    for _package in "${sys_packages[@]}" ; do
        install_result=$(run install-packages "$_package")
        if [[ $install_result != 0 ]] ; then
            brdr=${ylw}
            logger boxline "Package install for $_package failed"
            brdr=${dfl}
        fi
    done
    if [ -f "${rundir}/requirements.txt" ] ; then
        logger echo "${grn}Installing pip requirements$...${dfl}"
        run pip install -U -r "${rundir}/requirements.txt"
    else
        if [ ! -z "$pip_packages" ] ; then
            logger echo "${grn}Installing pip packages:${lyl} $pip_packages${dfl}"
            run pip install -U "${pip_packages[*]}"
        fi
    fi
    logger boxline "${grn}Checking Repositories:${lyl} $repo_packages${dfl}"
    pushd "$installdir"
        for repo in "${repo_packages[@]}"; do
            if ! check-git-repository "repositories/${repo#*/}"; then
                if [ -d "repositories/${repo#*/}" ] ; then
                    warn "Existing repo ${repo#*/} is broken..."
                    return 1
                else
                    logger boxline "Cloning ${repo} into ${installdir}/repositories/${repo#*/}"
                    clone-repo "https://github.com/$repo" "${installdir}/repositories/${repo#*/}"
                fi
            else
                pushd "repositories/${repo#*/}"
                if [[ ${VERSIONS[${repo#*/}]} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    logger boxline "Version tag detected: ${VERSIONS[${repo#*/}]}"
                    git checkout "${VERSIONS[${repo#*/}]}"
                else
                    logger boxline "Commit hash detected: ${VERSIONS[${repo#*/}]}"
                    git checkout -q "${VERSIONS[${repo#*/}]}"
                fi
                popd
            fi
        done
    popd
    # Sets dependency installed flag to true
    depsinstalled=true
}

dry-run-report(){
    box-rounded
    boxborder "${grn}Dry-run Report:${dfl}"
    box-norm
    boxborder \
    "bins_missing= " \
    "${bins_missing[@]}" \
    "backup_files= " \
    "${backup_files[@]}" \
    "installed_files= " \
    "${installed_files[@]}" \
    "installed_dirs= " \
    "${installed_dirs[@]}"
}

install-functions(){
    # Copy functions
    if [ -f ${rundir}/PRbL/functions ] ; then
        install-file ${rundir}/PRbL/functions ${installdir}
        logger boxline "Installed PRbL functions from script source"
    else
        curl -ks 'https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions' > ${rundir}/functions
        install-file ${rundir}/functions ${installdir}
        logger boxline "Installed latest 'main' branch PRbL functions from GitHub"
    fi  
}


install-prbl(){
    _extras=($(ls ${escape_dir}/extras/ | grep -v 'log$'))
    # extra_installs=$(ls ${escape_dir}/extras/)
    # for file in $extra_installs ; do
    #     _extras+=("$file")
    # done

    boxborder "Which extras should be installed?"
    for each in {1..${#_extras[@]}} ; do
        preselect+=("true")
    done
    multiselect result _extras preselect

    # For each extra, compare input choice and apply installs
    idx=0
    for extra in "${_extras[@]}"; do
        # If the selected user is set to true
        if [[ "${result[idx]}" == "true" ]] ; then
            if [[ $dry_run != true ]] ; then
                boxline "running extra $extra"
                run "${rundir_absolute}/extras/$extra -i"
            else
                dry_run=false
                run "${rundir_absolute}/extras/$extra -D"
                dry_run=true
            fi
        # else
        #     echo "index for $extra is ${result[idx]}"
        fi
    done
}

extras-menu(){
    # Download and install any other extras
    if [ -d "${rundir_absolute}/extras/" ] ; then
        boxborder "Extra installs available. Select and install?"
        extras_menu=(
        "$(boxline "${green_check} Yes")"
        "$(boxline "${red_x} No")"
        )
        case `select_opt "${extras_menu[@]}"` in
            0)  boxborder "${grn}Installing extras...${dfl}"
                install-extras
                ;;
            1)  boxline "Skipping extras installs" ;;
        esac
    fi
}

choose-users-menu(){
    # Prompt the user to specify which users to install the quickinfo script for
    boxborder "Which users should PRbL be installed for?"
    multiselect result users "false"

    # For each user, compare input choice and apply installs
    idx=0
    for selecteduser in "${users[@]}"; do
        # If the selected user is set to true
        if [[ "${result[idx]}" == "true" ]] ; then
            #cp -r ${rundir}/lib/skel/* /etc/skel/
            userinstall ${selecteduser}
        fi
    done
}

userinstall(){
    target_user=$1
# TODO: modify this function to accept a user as an argument and call it from globalinstall
    s3dk_bashrc="# SlipStream SDK environment v$VERSION 
export s3dk_functions=\"${installdir}/functions\""

    # Copy functions first
    install-functions

    # Copy bashrc scripts to home folder
    install-dir ${rundir}/repositories ${installdir}

    # Check for dependent applications and warn user if any are missing
    if ! check-deps ; then
        warn "Some of the utilities needed by this script are missing"
        boxline "Missing utilities:"
        boxline "${bins_missing[@]}"
        boxline "Would you like to install them? (this will require root password)"
        utilsmissing_menu=(
        "$(boxline "${green_check} Yes")"
        "$(boxline "${red_x} No")"
        )
        case `select_opt "${utilsmissing_menu[@]}"` in
            0)  boxline "${grn}Installing dependencies...${dfl}"
                install-deps
                ;;
            1)  warn "Dependent Utilities missing: $bins_missing" ;;
        esac
    fi

    # Check for and parse the installed vim version
    detectvim

    # Check for existing bashrc config, append if missing

    if [[ $(cat /home/${target_user}/.bashrc | grep -c 'bashrc.d') == 0 ]] ; then
        take-backup /home/${target_user}/.bashrc
        bashrc_appended=$(run "echo -e "$bashrc_append" >> "/home/${target_user}/.bashrc"")
        if $bashrc_appended ; then
            boxborder "bashc.d installed..."
        else
            warn "Malformed append on ${lbl}/home/${target_user}/.bashrc${dfl}. Check this file for errors"
        fi
    fi
    if [[ ! -f "/home/${target_user}/.bashrc.d/70-SlipStreamSDK.bashrc" ]] ; then
        bashrc_created=$(run echo -e "$s3dk_bashrc" >> /home/${target_user}/.bashrc.d/70-SlipStreamSDK.bashrc)
        if $bashrc_created ; then
            boxborder "bashc.d/70-SlipStreamSDK.bashrc installed..." 
        else
            warn "Malformed append on ${lbl}/home/${target_user}/.bashrc.d/70-SlipStreamSDK.bashrc${dfl}. Check this file for errors"
        fi
    fi

    pushd $installdir/repositories/Proteus
        run sudo python3 ruleMgr.py
    popd
    pushd $installdir/repositories/Slipstream
        run $installdir/repositories/CodeDog/codeDog ./Slipstream.dog && logger echo "Slipstream app built at ${installdir}/repositories/Slipstream/LinuxBuild"
    popd
}

install(){
    # Create install directory
    run mkdir -p ${installdir}

    install-functions
    export prbl_functions="${installdir}/functions"

    # Check for dependent applications and offer to install
    if ! check-deps ; then
        warn "Some of the utilities needed by this script are missing"
        boxline "Missing utilities:"
        boxline "${bins_missing[@]}"
        boxline "Would you like to install them? (this will require root password)"
        utilsmissing_menu=(
        "$(boxline "${green_check} Yes")"
        "$(boxline "${red_x} No")"
        )
        case `select_opt "${utilsmissing_menu[@]}"` in
            0)  boxline "${grn}Installing dependencies...${dfl}"
                install-deps
                ;;
            1)  warn "Skipping install of Dependent Utilities: $bins_missing" ;;
        esac
    fi

    boxline "Install for other users?"
    userchoose_menu=(
    "$(boxline "${green_check} Yes")"
    "$(boxline "${red_x} No")"
    )
    case `select_opt "${userchoose_menu[@]}"` in
        0)  choose-users-menu ;;
        1)  userinstall $runuser ;;
    esac

    # Download and install any other extras
    extras-menu
    #clear
}

remove(){
    if [ -f $rundir/installed_files.list ] ; then
        _installed_list=($(cat $rundir/installed_files.list))
    fi
    for file in "${installed_files[@]}" ; do
        if [ -f $file ] ; then
            run rm "$file"
            boxline "Removed $file"
        fi
    done
    for file in "${_installed_list[@]}" ; do
        if [ -f $file ] ; then
            run rm "$file"
            boxline "Removed $file"
        fi
    done
    if [ -f $rundir/installed_files.list ] ; then
        run rm $rundir/installed_files.list
    fi
    installed_files=()
    # if [ -f $rundir/backup_files.list ] ; then
    #     for file in $(cat $rundir/backup_files.list) ; do
    #         restore-backup $file
    #     done
    # fi
    restore-backup
}

remove-arbitrary(){
    update_run=true
    install
    update_run=
    #backup_files=()
    remove
}

update(){
    #remove-arbitrary
    pushd $installdir
        run git stash -m "$pretty_date stashing changes before update to latest"
        run git fetch && run git pull --recurse-submodules
    popd
    #install
}

dry-run-report(){
    box-rounded
    boxborder "${grn}Dry-run Report:${dfl}"
    box-norm
    boxborder \
    "bins_missing= " \
    "${bins_missing[@]}" \
    "backup_files= " \
    "${backup_files[@]}" \
    "installed_files= " \
    "${installed_files[@]}" \
    "installed_dirs= " \
    "${installed_dirs[@]}"
}

#------------------------------------------------------#
# Options and Arguments Parser
#------------------------------------------------------#

#$ Options Parser

while [[ $# -gt 0 ]] ; do
    arg2="$1"
    case $key in
        -D | --dry-run)
            export dry_run=true
            install
            box-double
            dry-run-report
            usage
            unset dry_run
            box-norm
            success "$script_title Dry-Run Complete!"
            ;;
        -u | --update)
            export update_run=true
            update && unset update_run && success " $script_title ${lyl}Updated${dfl}]"
            ;;
        -i | --install)
            install && success " $script_title ${lyl}Installed${dfl}]"
            ;;
        -F | --force-remove)
            remove-arbitrary && success " $script_title ${lyl}Force-Removed${dfl}]"
            ;;
        -h | --help)
            usage
            ;;
        -*)
            warn "Invalid option: $arg2"
            usage
            exit 1
            ;;
        *)
            if [[ -f $arg2 ]]; then
                # handle filename passed with flag
                # process_file $arg2
                break
            else
                warn "Invalid argument: $arg2"
                usage
                exit 1
            fi
            ;;
    esac
    shift
done

#------------------------------------------------------#
# Script begins here
#------------------------------------------------------#

usage