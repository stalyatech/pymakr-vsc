#!/usr/bin/env pwsh
#Requires -Version 6
<# 
download multiple versions of the native bindings of the serialport library
    to a folder named "abi<ABI_ver>-<platform>-<arch>" 
to allow for dynamic binding of the serialport module on multiple platforms

by downloading additional (future) versions fo the bindings andincluding them in the distribution,
this reduceces the likelyhood of bugs when vscode updates the version of electron.

there is nourantee as this does depend on 
- the prebuilds to be avaiable at the time of packaging 
- some prior knowledge of the future electron ( or ABI) version

# dependencies 
    npm install @serialport 
    npm install node-abi
# dev only (unless runtime download needed )
    npm install prebuild-install -d
#> 
npm upgrade node-abi 

$ElectronVersions = "3.1.8","4.2.5","6.0.0-beta.0" | Sort 
$platforms = "win32","darwin","linux","aix"
$architectures = "x64","ia32"

# todo: read default from github, and sliit on newline
try {
    $master_url = "https://raw.githubusercontent.com/microsoft/vscode/master/.yarnrc"
    $yaml = Invoke-WebRequest $master_url | select -Expand Content 
    $yaml = $yaml.Split("`n")
    $currentversion = $yaml | Select-String -Pattern '^target +"(?<targetversion>[0-9.]*)"' -AllMatches | 
            Foreach-Object {$_.Matches} | 
            Foreach-Object {$_.Groups} |
            where Name -ieq 'targetversion' |
            Select-Object -ExpandProperty Value

    if ($currentversion -in $ElectronVersions ) {
        Write-Host -F Green "VSCode master branch uses a known version of Electron: $currentversion"
    }else {
        Write-Host -F Yellow "The VSCode master branch uses a new/unknown version of  Electron: $currentversion, that will be used in the current build"
        $ElectronVersions  = $ElectronVersions + ($currentversion) | Sort 
    } 
} catch {
    Write-warning "Unable to determine the Electron version used by VSCode from GitHub"
}

#assumes script is started in project root folder
$folder_root = $PWD
$folder_serial = Join-Path $folder_root -ChildPath 'node_modules\@serialport\bindings'
$folder_bindings = Join-Path $folder_root -ChildPath 'precompiles'
$docs = (Join-Path $folder_bindings "electron versions.md") 
# empty the previous prebuilds
remove-item (join-path $folder_bindings "abi*" ) -Recurse -ErrorAction SilentlyContinue 

mkdir $folder_bindings -ErrorAction SilentlyContinue | Out-Null
# Document electron-abi versions

"includes support for electron versions:" | Out-File -filepath $docs
$all = foreach ($version  in $ElectronVersions) {
    $ABI_ver = &node.exe --print "var getAbi = require('node-abi').getAbi;getAbi('$version','electron')"
    Write-Host -F Blue "Electron $version uses ABI $ABI_ver"
}

Set-Location $folder_serial
foreach ($version  in $ElectronVersions) {
    # Get the ABI version for electron version x.y.z 
    # getAbi('5.0.0', 'electron')
    $ABI_ver = &node.exe --print "var getAbi = require('node-abi').getAbi;getAbi('$version','electron')"
    # Write-Host -F Blue "Electron $version uses ABI $ABI_ver"
    # add to documentation
    "* Electron $version uses ABI $ABI_ver" | Out-File -FilePath $docs -Append 
    foreach ($platform in $platforms){
        foreach ($arch in $architectures){
            Write-Host -f green "Download prebuild native binding for electron: $version, abi: $abi_ver, $platform, $arch"
            if ($IsWindows) {
                .\node_modules\.bin\prebuild-install.cmd --runtime electron --target $version --arch $arch --platform $platform --tag-prefix @serialport/bindings@ 
            } else {
                # linux / mac : same command , slightly different path
                node_modules/.bin/prebuild-install --runtime electron --target $version --arch $arch --platform $platform --tag-prefix @serialport/bindings@
            }

            if ($LASTEXITCODE -eq 0){
                try {
                    #OK , now copy the platform folder 
                    # from : \@serialport\bindings\build\Release\bindings.node
                    # to a folder per "abi<ABI_ver>-<platform>-<arch>"
                    $dest_folder = Join-Path $folder_bindings -ChildPath "abi$ABI_ver-$platform-$arch"

                    # Write-Host 'Copy binding files'

                    mkdir $dest_folder -ErrorAction SilentlyContinue | Out-Null
                    Copy-Item '.\build\Release\bindings.node' $dest_folder -Force | Out-Null
                    # add to documentation
                    "   - $platform, $arch" | Out-File -FilePath $docs -Append
                } catch {
                    Write-Warning "Error while copying prebuild bindings for electron: $version, abi: $abi_ver, $platform, $arch"
                } 

            } else {
                # Write-Warning "no prebuild bindings for electron: $version, abi: $abi_ver, $platform, $arch"
            }
        }
    }
} 
Set-Location $folder_root
