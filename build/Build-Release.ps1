param (
	[Parameter(Mandatory=$true)]
	[ValidatePattern("^\d\.\d\.(?:\d\.\d$|\d$)")]
	[string]
	$ReleaseVersionNumber,
	[Parameter(Mandatory=$true)]
	[string]
	[AllowEmptyString()]
	$PreReleaseName
)

$PSScriptFilePath = (Get-Item $MyInvocation.MyCommand.Path);
$RepoRoot = (get-item $PSScriptFilePath).Directory.Parent.FullName;
$SolutionRoot = Join-Path -Path $RepoRoot "src";
$NuGetPackagesPath = Join-Path -Path $SolutionRoot "packages"

#trace
"Solution Root: $SolutionRoot"

# Make sure we don't have a release folder for this version already
$BuildFolder = Join-Path -Path $RepoRoot -ChildPath "build";
$ReleaseFolder = Join-Path -Path $BuildFolder -ChildPath "Release";
if ((Get-Item $ReleaseFolder -ErrorAction SilentlyContinue) -ne $null)
{
	Write-Warning "$ReleaseFolder already exists on your local machine. It will now be deleted."
	Remove-Item $ReleaseFolder -Recurse
}
New-Item $ReleaseFolder -Type directory

# Go get nuget.exe if we don't hae it
$NuGet = "$BuildFolder\nuget.exe"
$FileExists = Test-Path $NuGet 
If ($FileExists -eq $False) {
	Write-Host "Retrieving nuget.exe..."
	$SourceNugetExe = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
	Invoke-WebRequest $SourceNugetExe -OutFile $NuGet
}

# ensure we have vswhere
New-Item "$BuildFolder\vswhere" -type directory -force
$vswhere = "$BuildFolder\vswhere.exe"
if (-not (test-path $vswhere))
{
	Write-Host "Download VsWhere..."
	$path = "$BuildFolder\tmp"
	&$nuget install vswhere -OutputDirectory $path -Verbosity quiet
	$dir = ls "$path\vswhere.*" | sort -property Name -descending | select -first 1
	$file = ls -path "$dir" -name vswhere.exe -recurse
	mv "$dir\$file" $vswhere   
	}

$MSBuild = &$vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
if ($MSBuild) {
	$MSBuild = join-path $MSBuild 'MSBuild\15.0\Bin\MSBuild.exe'
	if (-not (test-path $msbuild)) {
	throw "MSBuild not found!"
	}
}

#trace
"Release path: $ReleaseFolder"

# Set the version number in SolutionInfo.cs
$AssemblyInfoPath = Join-Path -Path $SolutionRoot -ChildPath "Umbraco.RestApi\Properties\AssemblyInfo.cs"
(gc -Path $AssemblyInfoPath) `
	-replace "(?<=AssemblyFileVersion\(`")[.\d]*(?=`"\))", $ReleaseVersionNumber |
	sc -Path $AssemblyInfoPath -Encoding UTF8;
(gc -Path $AssemblyInfoPath) `
	-replace "(?<=AssemblyInformationalVersion\(`")[.\w-]*(?=`"\))", "$ReleaseVersionNumber-$PreReleaseName" |
	sc -Path $AssemblyInfoPath -Encoding UTF8;
# Set the copyright
$Copyright = "Copyright � Umbraco " + (Get-Date).year;
(gc -Path $AssemblyInfoPath) `
	-replace "(?<=AssemblyCopyright\(`").*(?=`"\))", $Copyright |
	sc -Path $AssemblyInfoPath -Encoding UTF8;

# Build the solution in release mode
$SolutionPath = Join-Path -Path $SolutionRoot -ChildPath "Umbraco.RestApi.sln";

#restore nuget packages
Write-Host "Restoring nuget packages..."
& $NuGet restore $SolutionPath

# clean sln for all deploys
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount /t:Clean
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

#build
& $MSBuild "$SolutionPath" /p:Configuration=Release /maxcpucount
if (-not $?)
{
	throw "The MSBuild process returned an error code."
}

$include = @('Umbraco.RestApi.dll','Umbraco.RestApi.pdb')
$BinFolder = Join-Path -Path $SolutionRoot -ChildPath "Umbraco.RestApi\bin\Release";
New-Item "$ReleaseFolder\bin\" -Type directory
Copy-Item "$BinFolder\*.*" -Destination "$ReleaseFolder\bin\" -Include $include

# COPY THE README OVER
Copy-Item "$BuildFolder\Readme.txt" -Destination $ReleaseFolder

# COPY OVER THE NUSPEC AND BUILD THE NUGET PACKAGE
Copy-Item "$BuildFolder\UmbracoCms.RestApi.nuspec" -Destination $ReleaseFolder
$NuSpec = Join-Path -Path $ReleaseFolder -ChildPath "UmbracoCms.RestApi.nuspec";

Write-Output "DEBUGGING: " $NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber-$PreReleaseName
& $NuGet pack $NuSpec -OutputDirectory $ReleaseFolder -Version $ReleaseVersionNumber-$PreReleaseName


#TODO: Create an Umbraco package too!!!