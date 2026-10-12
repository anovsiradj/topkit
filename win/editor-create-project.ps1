$folderName = Split-Path -Leaf (Get-Location)
$sublimeFile = "$folderName.sublime-project"
$vscodeFile = "$folderName.code-workspace"

Write-Host "Pilih jenis project yang ingin dibuat untuk folder '$folderName':" -ForegroundColor Cyan
Write-Host "[1] Sublime Text ($sublimeFile)"
Write-Host "[2] VS Code ($vscodeFile)"
Write-Host "[3] Keduanya"
$choice = Read-Host "Pilihan (1/2/3)"

$sublimeContent = @"
{
	"folders":
	[
		{
			"path": "."
		}
	]
}
"@

$vscodeContent = @"
{
	"folders": [
		{
			"path": "."
		}
	],
	"settings": {}
}
"@

function EditorCreateStext {
	if (Test-Path $sublimeFile) {
		Write-Host "File $sublimeFile sudah ada!" -ForegroundColor Yellow
	} else {
		$sublimeContent | Out-File -FilePath $sublimeFile -Encoding utf8
		Write-Host "Berhasil membuat $sublimeFile" -ForegroundColor Green
	}
}

function EditorCreateVscode {
	if (Test-Path $vscodeFile) {
		Write-Host "File $vscodeFile sudah ada!" -ForegroundColor Yellow
	} else {
		$vscodeContent | Out-File -FilePath $vscodeFile -Encoding utf8
		Write-Host "Berhasil membuat $vscodeFile" -ForegroundColor Green
	}
}

switch ($choice) {
	'1' { EditorCreateStext }
	'2' { EditorCreateVscode }
	'3' { EditorCreateStext; EditorCreateVscode }
	Default { Write-Host "Pilihan tidak valid." -ForegroundColor Red }
}
