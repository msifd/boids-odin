$BuildDir = "build"

echo "Cleanup hot artifacts"

Remove-Item -Path "$BuildDir/pdb/*" -Force 2> $null
Remove-Item -Path "$BuildDir/tmp*" -Force 2> $null