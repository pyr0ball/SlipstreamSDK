function UserInstall($targetUser) {
    $s3dk_bashrc = "# SlipStream SDK environment v$VERSION 
    $env:s3dk_functions = \"${installdir}/functions\""

    # Copy functions first
    Install-Functions

    # Copy bashrc scripts to home folder
    Install-Dir -SourcePath "${rundir}/repositories" -DestinationPath $installdir

    # Check for dependent applications and warn user if any are missing
    if (-not (Check-Deps)) {
        Write-Warning "Some of the utilities needed by this script are missing"
        Write-Output "Missing utilities:"
        Write-Output $bins_missing
        Write-Output "Would you like to install them? (this will require root password)"
        $utilsmissing_menu = @(
            "$(Write-Output "${green_check} Yes")",
            "$(Write-Output "${red_x} No")"
        )
        $choice = Select-Option -Options $utilsmissing_menu
        switch ($choice) {
            0 {
                Write-Output "${grn}Installing dependencies...${dfl}"
                Install-Deps
            }
            1 {
                Write-Warning "Dependent Utilities missing: $bins_missing"
            }
        }
    }

    # Check for and parse the installed vim version
    Detect-Vim

    # Check for existing bashrc config, append if missing
    $bashrcPath = "/home/$targetUser/.bashrc"
    if ((Get-Content $bashrcPath | Select-String 'bashrc.d').Count -eq 0) {
        Take-Backup $bashrcPath
        Add-Content $bashrcPath $bashrc_append | Out-Null
        if ($?) {
            Write-Output "bashc.d installed..."
        } else {
            Write-Warning "Malformed append on $bashrcPath. Check this file for errors"
        }
    }
    $s3dk_bashrcPath = "/home/$targetUser/.bashrc.d/70-SlipStreamSDK.bashrc"
    if (-not (Test-Path $s3dk_bashrcPath)) {
        Add-Content $s3dk_bashrcPath $s3dk_bashrc | Out-Null
        if ($?) {
            Write-Output "bashc.d/70-SlipStreamSDK.bashrc installed..."
        } else {
            Write-Warning "Malformed append on $s3dk_bashrcPath. Check this file for errors"
        }
    }
}

function Install {
    # Create global install directory
    New-Item -ItemType Directory -Path $installdir | Out-Null

    Install-Functions
    $env:prbl_functions = "${installdir}/functions"

    # Check for dependent applications and offer to install
    if (-not (Check-Deps)) {
        Write-Warning "Some of the utilities needed by this script are missing"
        Write-Output "Missing utilities:"
        Write-Output $bins_missing
        Write-Output "Would you like to install them? (this will require root password)"
        $utilsmissing_menu = @(
            "$(Write-Output "${green_check} Yes")",
            "$(Write-Output "${red_x} No")"
        )
        $choice = Select-Option -Options $utilsmissing_menu
        switch ($choice) {
            0 {
                Write-Output "${grn}Installing dependencies...${dfl}"
                Install-Deps
            }
            1 {
                Write-Warning "Dependent Utilities missing: $bins_missing"
            }
        }
    }

    Write-Output "Install for other users?"
    $utilsmissing_menu = @(
        "$(Write-Output "${green_check} Yes")",
        "$(Write-Output "${red_x} No")"
    )
    $choice = Select-Option -Options $utilsmissing_menu
    switch ($choice) {
        0 {
            Choose-Users-Menu
        }
        1 {
            UserInstall $runuser
        }
    }

    # Download and install any other extras
    Extras-Menu
}