$ProjectName = "arcadia"
$BuildDir = "build"

$ExeOutPath = Join-Path -Path $BuildDir -ChildPath "$($ProjectName).exe"

echo "Build release $ExeOutPath"
odin build "runner/static" -out:$ExeOutPath -strict-style -vet -no-bounds-check -o:speed -subsystem:windows
