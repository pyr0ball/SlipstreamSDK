#!/bin/bash
###################################################################
#               Slipstream Foundation SDK Installer               #
###################################################################

# initial vars
VERSION=0.0.1
_script-title="Slipstream Foundation SDK Installer - v$VERSION"

# Bash expansions to get the name and location of this script when run
scriptname="${BASH_SOURCE[0]##*/}"
rundir="${BASH_SOURCE[0]%/*}"

# Source PRbL Functions locally or retrieve from online
if [ ! -z $prbl_functions ] ; then
    source $prbl_functions
else
    if [ -f ${rundir}/functions ] ; then
        source ${rundir}/functions
    else
        prbl_functions_url='https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions'
        # Iterate through get commands and fall back on next if unavailable
        if command -v curl >/dev/null 2>&1; then
            source <(curl -ks $prbl_functions_url )
        elif command -v wget >/dev/null 2>&1; then
            source <(wget -qO- $prbl_functions_url )
        elif command -v fetch >/dev/null 2>&1; then
            source <(fetch -qo- $prbl_functions_url )
        else
            echo "Error: curl, wget, and fetch commands are not available. Please install one to retrieve PRbL functions."
            exit 1
        fi
    fi
fi

rundir_absolute=$(pushd $rundir ; pwd ; popd)
escape_dir=$(printf %q "${rundir_absolute}")
logfile="${rundir}/${pretty_date}_${scriptname}.log"

#-----------------------------------------------------------------#
# Script-specific Parameters
#-----------------------------------------------------------------#

# Store functions revision in a variable to compare with if already installed
installer_functionsrev=$functionsrev

# Get and store the user currently executing this script
runuser=$(whoami)

# set up an array containing the users listed under /home/
users=($(ls /home/))

# If run as non-root, default install to user's home directory
userinstalldir="$HOME/.local/share/SlipstreamSDK"

# If run as root, this will be the install directory
globalinstalldir="/usr/share/SlipstreamSDK"

# Initialize arrays for file and dependency management
bins_missing=()
backup_files=()
installed_files=()
installed_dirs=()

# List of dependency packaged to be istalled via apt (For Debian/Ubuntu)
packages=(
    git
    curl
    python3
    python3-pip
    cmake
    libgmp3-dev
    libgtk-3-dev
    venv
    wget
)

pip_packages=(
    pyparsing
    gitpython
)

repo_packages=(
    https://github.com/BruceDLong/CodeDog.git
    https://github.com/BruceDLong/Proteus.git
    https://github.com/BruceDLong/Slipstream.git
    https://github.com/pyr0ball/PRbL-bashrc.git
)

prbl_packages=(
    golang.19.x.install
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

script-title(){
    boxborder \
"           ___          _    _                                        " \
"          |       |         | |           |                           " \
"           -+-    +     +   |-       -   -+-  |-     -     -    |- -  " \
"              |   |     |   |        \    |   |     |/    | |   | | | " \
"           ---    -                  -     -         --    --         " \
"                                ___   ___                             " \
"                               |       | | |  /                       " \
"                                -+-    + | |-+                        " \
"                                   |   | | |  \                       " \
"                                ---   ---                             "
}

# Function for displaying the usage of this script
usage(){
    boxborder \
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
        "   -h [--help]" \
        "" \
        "Running this installer as 'root' will install globally to $globalinstalldir" \
        "You must run as 'root' for this script to automatically resolve dependencies"
}

detectvim(){
    # If the vim install directory exists, check for and store the highest numerical value version installed
    if [[ -d /usr/share/vim ]] ; then
        viminstall=$(ls -lah /usr/share/vim/ | grep vim | grep -v rc | awk '{print $NF}' | tail -n 1)
    else
        viminstall=null
        warn "vim is not currently installed, unable to set up colorscheme and formatting"
    fi
}

check-deps(){
    # Iterate through the list of required packages and check if installed
    for pkg in ${sys_packages[@]} ; do
        local _pkg=$(dpkg -l $pkg 2>&1 >/dev/null ; echo $?)
        # If not installed, add it to the list of missing bins
        if [[ $_pkg != 0 ]] ; then
            bins_missing+=($pkg)
        fi
    done
    pybin=$(which python3)
    if [ -z $pybin ] ; then
        run install-packages python3 python3-pip
        # TODO: make a universal package install function
    fi
    pipbin=$(which pip3)
    if [ -z $pipbin ] ; then
        run install-packages python3-pip
    fi
    for pkg in ${pip_packages[@]} ; do
        pippkg_installed=$(pip list | grep -F $pkg ; echo $?)
        if [[ $pippkg_installed != 0 ]] ; then
            bins_missing+=("pip: $pkg")
        fi
    done

    # This installer requires golang to work
    # TODO: better handling of prbl_packages as dependencies
    gobin=$(which go)
    if  [ -z $gobin ] ; then
        bins_missing+=("prbl: golang.install")
    fi
    # Count the number of entries in bins_missing
    local _bins_missing=${#bins_missing[@]}
    # If higher than 0, return a fail (1)
    if [[ $_bins_missing != 0 ]] ; then
        return 1
    else
        return 0
    fi
}

install-deps(){
    logger echo "Installing packages: $sys_packages"
    for _package in ${sys_packages[@]} ; do
        run install-packages $_package
    done
    if [ -f ${rundir}/requirements.txt ] ; then
        run pip install -y ${rundir}/requirements.txt
    else
        if [ ! -z $pip_packages ] ; then
            run pip install ${pip_packages[@]}
        fi
    fi
    for _package in $prbl_packages ; do
        if [ -f ${rundir}/$_package ] ; then
            if [[ $dry_run != true ]] ; then
                boxline "running extra $extra"
                run "${rundir}/$_package -i"
            else
                dry_run=false
                run "${rundir}/$_package -D"
                dry_run=true
            fi
        else
            if [[ $dry_run != true ]] ; then
                run-from-url https://raw.githubusercontent.com/pyr0ball/PRbL-bashrc/main/extras/$_package -i
            else
                run-from-url https://raw.githubusercontent.com/pyr0ball/PRbL-bashrc/main/extras/$_package -D
            fi
        fi
    done
    # Sets dependency installed flag to true
    depsinstalled=true
}

install(){
    # If script is run as root, run global install
    if [[ $runuser == root ]] ; then
        installdir="${globalinstalldir}"
        globalinstall
    else
    # If user is non-root, run user-level install
        installdir="${userinstalldir}"
        userinstall
    fi
}

install-functions(){
    # Copy functions
    if [ -f ${rundir}/PRbL/functions ] ; then
        install-file ${rundir}/PRbL/functions ${installdir}
    else
        curl -ks 'https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions' > ${rundir}/functions
        install-file ${rundir}/functions ${installdir}
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
        preselect+=("false")
    done
    multiselect result _extras preselect

    # For each extra, compare input choice and apply installs
    idx=0
    for extra in "${_extras[@]}"; do
        # If the selected user is set to true
        if [[ "${result[idx]}" == "true" ]] ; then
            if [[ $dry_run != true ]] ; then
                boxline "running extra $extra"
                run "${escape_dir}/extras/$extra -i"
            else
                dry_run=false
                run "${escape_dir}/extras/$extra -D"
                dry_run=true
            fi
        # else
        #     echo "index for $extra is ${result[idx]}"
        fi
    done
}

extras-menu(){
    # Download and install any other extras
    #if [ -d "${rundir_absolute}/extras/" ] ; then
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
    #fi
}

userinstall(){
# TODO: modify this function to accept a user as an argument and call it from globalinstall
    s3dk_bashrc="# SlipStream SDK environment v$VERSION 
export s3dk_functions=\"${installdir}/functions\""
    # Create install directory under user's home directory
    run mkdir -p ${installdir}

    # Copy functions first
    install-functions

    # Copy bashrc scripts to home folder
    install-dir ${rundir}/lib/skel/ $HOME

    # Check for dependent applications and warn user if any are missing
    if ! check-deps ; then
        warn "Some of the utilities needed by this script are missing"
        boxlinelog "Missing utilities:"
        boxlinelog "${bins_missing[@]}"
        boxlinelog "Would you like to install them? (this will require root password)"
        utilsmissing_menu=(
        "$(boxline "${green_check} Yes")"
        "$(boxline "${red_x} No")"
        )
        case `select_opt "${utilsmissing_menu[@]}"` in
            0)  boxlinelog "${grn}Installing dependencies...${dfl}"
                install-deps
                ;;
            1)  warn "Dependent Utilities missing: $bins_missing" ;;
        esac
    fi

    # Check for and parse the installed vim version
    detectvim

    # If vim is installed, add config files for colorization and expandtab
    # if [[ $viminstall != null ]] ; then
    #     run mkdir -p ${HOME}/.vim/colors
    #     install-file $rundir/lib/vimfiles/crystallite.vim ${HOME}/.vim/colors
    #     take-backup $HOME/.vimrc
    #     cp $rundir/lib/vimfiles/vimrc.local $rundir/lib/vimfiles/.vimrc
    #     install-file $rundir/lib/vimfiles/.vimrc $HOME
    #     rm $rundir/lib/vimfiles/.vimrc
    # fi

    # Check for existing bashrc config, append if missing
    if [[ $(cat ${HOME}/.bashrc | grep -c 'bashrc.d') == 0 ]] ; then
        take-backup $HOME/.bashrc
        run echo -e "$bashrc_append" >> $HOME/.bashrc && boxborder "bashc.d installed..." || warn "Malformed append on ${lbl}${HOME}/.bashrc${dfl}. Check this file for errors"
        run echo -e "$s3dk_bashrc" >> $HOME/.bashrc.d/70-SlipStreamSDK.bashrc && boxborder "bashc.d/70-SlipStreamSDK.bashrc installed..." || warn "Malformed append on ${lbl}${HOME}/.bashrc.d/70-SlipStreamSDK.bashrc${dfl}. Check this file for errors"
    fi


    # Create the quickinfo cache directory
    #mkdir -p $HOME/.quickinfo
    # export prbl_functions="${installdir}/functions"

    # If all required dependencies are installed, launch initial cache creation
    #if [[ "$bins_missing" == "false" ]] ; then
    #    bash $HOME/.bashrc.d/11-quickinfo.bashrc
    #fi
    #clear

    # launch extra installs
    extras-menu

    if [[ $dry_run != true ]] ; then
        boxborder "${grn}Please be sure to run ${lyl}sensors-detect --auto${grn} after installation completes${dfl}"
    fi
}

globalinstall(){
    # Create global install directory
    run mkdir -p ${installdir}

    install-functions
    export prbl_functions="${globalinstalldir}/functions"

    # Check for dependent applications and offer to install
    if ! check-deps ; then
        warn "Some of the utilities needed by this script are missing"
        boxlinelog "Missing utilities:"
        boxlinelog "${bins_missing[@]}"
        boxlinelog "Would you like to install them? (this will require root password)"
        utilsmissing_menu=(
        "$(boxline "${green_check} Yes")"
        "$(boxline "${red_x} No")"
        )
        case `select_opt "${utilsmissing_menu[@]}"` in
            0)  boxlinelog "${grn}Installing dependencies...${dfl}"
                install-deps
                ;;
            1)  warn "Dependent Utilities missing: $bins_missing" ;;
        esac
    fi

    # Prompt the user to specify which users to install the quickinfo script for
    boxborder "Which users should PRbL be installed for?"
    multiselect result users "false"

    # For each user, compare input choice and apply installs
    idx=0
    for selecteduser in "${users[@]}"; do
        # If the selected user is set to true
        if [[ "${result[idx]}" == "true" ]] ; then
            #cp -r ${rundir}/lib/skel/* /etc/skel/
            install-dir ${rundir}/lib/skel/ /home/${selecteduser}/
            # for file in $(ls -a -I . -I .. ${rundir}/lib/skel/) ; do
            #     install-dir ${rundir}/lib/skel/$file $HOME
            # done
            if [[ $(cat /home/${selecteduser}/.bashrc | grep -c prbl) == 0 ]] ; then
                take-backup /home/${selecteduser}/.bashrc
                run echo -e "$bashrc_append" >> /home/${selecteduser}/.bashrc && boxborder "bashc.d installed..." || warn "Malformed append on ${lbl}/home/${selecteduser}/.bashrc${dfl}. Check this file for errors"
            fi
            run sudo chown -R ${selecteduser}:${selecteduser} ${installdir}
            if [[ "$bins_missing" == "false" ]] ; then
                boxborder "Checking ${selecteduser}'s bashrc..."
                run su ${selecteduser} -c /home/${selecteduser}.bashrc.d/11-quickinfo.bashrc
            fi
        fi
    done

    detectvim
    if [[ $viminstall != null ]] ; then
        install-file $rundir/lib/vimfiles/crystallite.vim /usr/share/vim/${viminstall}/colors
        take-backup /etc/vim/vimrc.local
        install-file $rundir/lib/vimfiles/vimrc.local /etc/vim/vimrc.local
    fi
    if [ ! -z $(which sensors-detect) ] ; then
        run sensors-detect --auto
    fi

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
    userinstall
    globalinstall
    update_run=
    #backup_files=()
    remove
}

update(){
    remove-arbitrary
    run git stash -m "$pretty_date stashing changes before update to latest"
    run git fetch && run git pull --recurse-submodules
    pushd PRbL
        run git checkout main
        run git pull
    popd
    install
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
script-title

#$ Options Parser
diags(){
  boxborder \
    "Diagnostics:" \
    "Local IP: $local_ip" \
    "Cert File: $cert_file" \
    "Key File: $key_file" \
    "Target(s): $target"
}

while [[ $# -gt 0 ]] ; do
  key="$1"
  case $key in
    -c | --cert-file)
        if [[ -n $2 && ! $2 == -* ]]; then
            cert_file=$2
            shift
        else
            warn "Invalid argument for $key: $2"
            usage
            exit 1
        fi
        ;;
    -k | --key-file)
        if [[ -n $2 && ! $2 == -* ]]; then
            key_file=$2
            shift
        else
            warn "Invalid argument for $key: $2"
            usage
            exit 1
        fi
        ;;
    -t | --target)
        if [[ -n $2 && ! $2 == -* ]]; then
            target=$2
            shift
        else
            warn "Invalid argument for $key: $2"
            usage
            exit 1
        fi
        ;;
    -D | --dry-run)
        export dry_run=true
        box-double
        boxtop
        diags
        install-keys
        boxbottom
        dry-run-report
        usage
        unset dry_run
        success "$script_title Dry-Run Complete!"
        ;;
    -u | --update)
        export update_run=true
        diags
        update && unset update_run && success " Certificate $cert_file and Key $key_file ${lyl}Updated${dfl}]"
        ;;
    -i | --install)
        diags
        install-keys && success " Certificate $cert_file and Key $key_file ${lyl}Installed${dfl}]"
        ;;
    -F | --force-remove)
        remove-arbitrary && success " $script_title ${lyl}Force-Removed${dfl}]"
        ;;
    -h | --help)
        usage
        ;;
    -*)
        warn "Invalid option: $key"
        usage
        exit 1
        ;;
    *)
        if [[ -f $key ]]; then
          # handle filename passed with flag
          process_file $key
        else
          warn "Invalid argument: $key"
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

