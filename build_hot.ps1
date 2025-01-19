$BuildDir = "build"

# Create build dir
New-Item -ItemType Directory -Force -Path $BuildDir > $null


function Panic {
    process { Write-Host $_ -ForegroundColor Red }
    end { Exit -1 }
}


$ExeOutPath = Join-Path -Path $BuildDir -ChildPath "runner_hot.exe"
$GameRunning = $false
if (Test-Path $ExeOutPath) {
    $AbsExePath = Resolve-Path $ExeOutPath
    $GameRunning = [bool](Get-Process | ?{$_.path -eq $AbsExePath})
}


# PDB file is locked by debugger so we need to change its name
$PdbDir = Join-Path -Path $BuildDir -ChildPath "pdb"
$PdbCounterPath = Join-Path -Path $PdbDir -ChildPath "counter.txt"
if ($GameRunning) {
    $PdbCounter = [int](Get-Content $PdbCounterPath) + 1
} else {
    $PdbCounter = 0
    Remove-Item -Path "$PdbDir/*" -Force 2> $null
    New-Item -ItemType Directory -Force -Path $PdbDir > $null
}
Set-Content -Path $PdbCounterPath -Value $PdbCounter


$DllOutPath = Join-Path -Path $BuildDir -ChildPath "game.dll"
$PdbOutPath = Join-Path -Path $PdbDir -ChildPath "game_$PdbCounter.pdb"
echo "Build DLL: $DllOutPath ; PDB: $PdbOutPath"
odin build source -strict-style -vet -debug -build-mode:dll -out:$DllOutPath -pdb-name:$PdbOutPath -define:RAYLIB_SHARED=true

if (!$?) {
    "Game DLL build failed!" | Panic
}

if ($GameRunning) {
    echo "Skip runner build"
    return
}


$LocalRaylibPath = Join-Path -Path $BuildDir -ChildPath "raylib.dll"
if (-Not (Test-Path $LocalRaylibPath)) {
    echo "Missing raylib.dll ..."

    $OdinRoot = odin root
    $VendorRaylibPath = Join-Path -Path $OdinRoot -ChildPath "vendor\raylib\windows\raylib.dll"
    if (-Not (Test-Path $VendorRaylibPath)) {
        "   Place raylib.dll at $LocalRaylibPath" | Panic
    }

    echo "   Copying raylib.dll from $VendorRaylibPath"
    Copy-Item -Path $VendorRaylibPath -Destination $LocalRaylibPath
}


echo "Build runner $ExeOutPath"
odin build runner\hot.odin -file -strict-style -debug -out:$ExeOutPath
if (!$?) {
    "Runner build failed!" | Panic
}
