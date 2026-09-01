# Signs a single PE file with Azure Artifact Signing (Trusted Signing) via SignTool + dlib.
# Used for the Godot export and as Inno Setup's SignTool (setup.exe + embedded uninstaller).
#
# Expects after azure/login (OIDC) and the workflow install step:
#   ACS_DLIB     path to Azure.CodeSigning.Dlib.dll (x64)
#   ACS_METADATA path to metadata.json
#   SIGNTOOL     path to signtool.exe (optional; searched if unset)

param(
	[Parameter(Mandatory = $true, Position = 0)]
	[string] $FilePath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $FilePath)) {
	throw "File not found for signing: $FilePath"
}

$dlib = $env:ACS_DLIB
$metadata = $env:ACS_METADATA
if ([string]::IsNullOrWhiteSpace($dlib) -or -not (Test-Path -LiteralPath $dlib)) {
	throw "ACS_DLIB missing or not found: $dlib"
}
if ([string]::IsNullOrWhiteSpace($metadata) -or -not (Test-Path -LiteralPath $metadata)) {
	throw "ACS_METADATA missing or not found: $metadata"
}

$signtool = $env:SIGNTOOL
if ([string]::IsNullOrWhiteSpace($signtool) -or -not (Test-Path -LiteralPath $signtool)) {
	$kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
	$signtool = Get-ChildItem -Path $kits -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
		Where-Object { $_.Directory.Name -eq 'x64' } |
		Sort-Object FullName -Descending |
		Select-Object -First 1 -ExpandProperty FullName
}
if ([string]::IsNullOrWhiteSpace($signtool)) {
	throw 'signtool.exe not found (install Windows SDK Build Tools)'
}

Write-Host "Signing $FilePath"
Write-Host "  signtool=$signtool"
Write-Host "  dlib=$dlib"
Write-Host "  metadata=$metadata"

& $signtool sign `
	/v `
	/fd SHA256 `
	/tr 'http://timestamp.acs.microsoft.com' `
	/td SHA256 `
	/dlib $dlib `
	/dmdf $metadata `
	$FilePath

if ($LASTEXITCODE -ne 0) {
	throw "signtool failed for $FilePath (exit $LASTEXITCODE)"
}
