<#
.SYNOPSIS
Convert a LaTeX manuscript into a Word document.

.DESCRIPTION
This script wraps the local Pandoc export pipeline used in this repository.
It accepts a `.tex` file path directly, auto-detects bibliography files from
the LaTeX source when possible, applies the repository-specific docx fixes,
and writes a `.docx` file.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\export_docx.ps1 .\docs\manuscripts\Root_Cause_Analysis.tex

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\export_docx.ps1 .\docs\manuscripts\Root_Cause_Analysis.tex -OutputPath .\paper_final.docx

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\export_docx.ps1 .\docs\manuscripts\Root_Cause_Analysis.tex -IncludeToc
#>

param(
    [Parameter(Position = 0)]
    [string]$TexPath = "docs\manuscripts\Root_Cause_Analysis.tex",

    [string]$OutputPath,

    [string]$TemplatePath = "template.docx",

    [string[]]$BibliographyPath,

    [string]$CslPath = "C:\Users\jiang\Zotero\styles\ieee.csl",

    [switch]$IncludeToc
)

$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$docxFilter = Join-Path $repoRoot "pandoc_docx_fix.lua"
$postprocessScript = Join-Path $repoRoot "postprocess_docx.py"
$defaultBibliography = Join-Path $repoRoot "docs\FailureMechanism202605.bib"
$utf8 = [System.Text.Encoding]::UTF8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Resolve-PathFromRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Resolve-ExistingPathFromRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $resolved = Resolve-PathFromRoot -PathValue $PathValue
    if (-not (Test-Path -LiteralPath $resolved)) {
        throw "$Description not found: $resolved"
    }

    return $resolved
}

function Ensure-ParentDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $parent = Split-Path -Parent $FilePath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Test-FileUnlocked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return $true
    }

    try {
        $stream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $stream.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Ensure-ReferenceDoc {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateFile
    )

    if ((Test-Path -LiteralPath $TemplateFile) -and (Get-Item -LiteralPath $TemplateFile).Length -gt 0) {
        return
    }

    Ensure-ParentDirectory -FilePath $TemplateFile

    $proc = Start-Process pandoc `
        -ArgumentList "--print-default-data-file=reference.docx" `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $TemplateFile

    if ($proc.ExitCode -ne 0) {
        throw "Failed to generate reference document: $TemplateFile"
    }
}

function Convert-AddedMarkupToMarkers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $builder = New-Object System.Text.StringBuilder
    $token = '\added{'
    $index = 0

    while ($index -lt $Text.Length) {
        if ($index + $token.Length -le $Text.Length -and $Text.Substring($index, $token.Length) -eq $token) {
            $contentStart = $index + $token.Length
            $cursor = $contentStart
            $depth = 1

            while ($cursor -lt $Text.Length -and $depth -gt 0) {
                $char = $Text[$cursor]
                if ($char -eq '{') {
                    $depth++
                }
                elseif ($char -eq '}') {
                    $depth--
                }
                $cursor++
            }

            if ($depth -eq 0) {
                $inner = $Text.Substring($contentStart, $cursor - $contentStart - 1)
                [void]$builder.Append('\texttt{CODXADDSTART}')
                [void]$builder.Append($inner)
                [void]$builder.Append('\texttt{CODXADDEND}')
                $index = $cursor
                continue
            }
        }

        [void]$builder.Append($Text[$index])
        $index++
    }

    return $builder.ToString()
}

function Get-BalancedGroup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [int]$StartIndex,

        [Parameter(Mandatory = $true)]
        [char]$OpenChar,

        [Parameter(Mandatory = $true)]
        [char]$CloseChar
    )

    if ($StartIndex -ge $Text.Length -or $Text[$StartIndex] -ne $OpenChar) {
        return $null
    }

    $builder = New-Object System.Text.StringBuilder
    $depth = 0

    for ($index = $StartIndex; $index -lt $Text.Length; $index++) {
        $char = $Text[$index]
        if ($char -eq $OpenChar) {
            $depth++
            if ($depth -gt 1) {
                [void]$builder.Append($char)
            }
            continue
        }

        if ($char -eq $CloseChar) {
            $depth--
            if ($depth -eq 0) {
                return @{
                    Value = $builder.ToString()
                    EndIndex = $index
                }
            }

            [void]$builder.Append($char)
            continue
        }

        [void]$builder.Append($char)
    }

    return $null
}

function Simplify-MakecellCommands {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $builder = New-Object System.Text.StringBuilder
    $token = '\makecell'
    $index = 0

    while ($index -lt $Text.Length) {
        if ($index + $token.Length -le $Text.Length -and $Text.Substring($index, $token.Length) -eq $token) {
            $cursor = $index + $token.Length

            while ($cursor -lt $Text.Length -and [char]::IsWhiteSpace($Text[$cursor])) {
                $cursor++
            }

            if ($cursor -lt $Text.Length -and $Text[$cursor] -eq '[') {
                $optionGroup = Get-BalancedGroup -Text $Text -StartIndex $cursor -OpenChar '[' -CloseChar ']'
                if ($null -eq $optionGroup) {
                    [void]$builder.Append($Text[$index])
                    $index++
                    continue
                }

                $cursor = $optionGroup.EndIndex + 1
                while ($cursor -lt $Text.Length -and [char]::IsWhiteSpace($Text[$cursor])) {
                    $cursor++
                }
            }

            if ($cursor -lt $Text.Length -and $Text[$cursor] -eq '{') {
                $contentGroup = Get-BalancedGroup -Text $Text -StartIndex $cursor -OpenChar '{' -CloseChar '}'
                if ($null -ne $contentGroup) {
                    $content = [regex]::Replace($contentGroup.Value, '\\\\\s*', ' ')
                    $content = [regex]::Replace($content, '\s+', ' ').Trim()
                    [void]$builder.Append($content)
                    $index = $contentGroup.EndIndex + 1
                    continue
                }
            }
        }

        [void]$builder.Append($Text[$index])
        $index++
    }

    return $builder.ToString()
}

function Simplify-RuntimeStatisticsTable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $runtimeTablePattern = '(?s)\\begin\{table\}\[[^\]]*\]\s*\\centering\s*\\caption\{Comparison of Runtime Components under Different Scenarios\.\}\s*\\label\{tab:runtime_stat\}.*?\\end\{table\}'
    $runtimeTableReplacement = @'
\begin{table}[H]
    \centering
    \caption{Comparison of Runtime Components under Different Scenarios.}
    \label{tab:runtime_stat}
    \begin{tabular}{lllll}
    \hline
    ID & Total Runtime & Runtime per Generation (Total) & Runtime per Generation (Sim.) & Sim. Ratio \\
    \hline
    $S_{1008}$ & 195.09 s  & 0.82 s   & 0.78 s  & 95.12\% \\
    $S_{1009}$ & 747.62 s  & 3.16 s   & 3.12 s  & 98.73\% \\
    $S_{1010}$ & 1693.38 s & 7.22 s   & 7.17 s  & 99.30\% \\
    \hline
    \end{tabular}
\end{table}

\noindent\footnotesize Note: The runtime per generation is reported based on the longest time-per-generation computation. Sim denotes the simulator runtime.\normalsize
'@

    $runtimeTableMatch = [regex]::Match($Text, $runtimeTablePattern)
    if ($runtimeTableMatch.Success) {
        return $Text.Replace($runtimeTableMatch.Value, $runtimeTableReplacement)
    }

    return $Text
}

function Apply-ExportOnlyPatches {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $patched = $Text.Replace("../figures/framework/TE_01.pdf", "../figures/framework/TE_01.png")
    $patched = Convert-AddedMarkupToMarkers -Text $patched
    $patched = Simplify-MakecellCommands -Text $patched
    $patched = Simplify-RuntimeStatisticsTable -Text $patched
    return $patched
}

function Resolve-BibliographyCandidate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate,

        [Parameter(Mandatory = $true)]
        [string]$BaseDirectory
    )

    $value = $Candidate.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($value))) {
        $value = "$value.bib"
    }

    if ([System.IO.Path]::IsPathRooted($value)) {
        return [System.IO.Path]::GetFullPath($value)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory $value))
}

function Get-BibliographyPathsFromTex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TexContent,

        [Parameter(Mandatory = $true)]
        [string]$TexFile
    )

    $texDirectory = Split-Path -Parent $TexFile
    $patterns = @(
        '\\bibliography\s*{(?<paths>[^}]+)}',
        '\\addbibresource(?:\[[^\]]*\])?\s*{(?<paths>[^}]+)}'
    )

    $results = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($TexContent, $pattern)) {
            $items = $match.Groups['paths'].Value -split ','
            foreach ($item in $items) {
                $resolved = Resolve-BibliographyCandidate -Candidate $item -BaseDirectory $texDirectory
                if ($resolved -and -not $seen.ContainsKey($resolved)) {
                    $results.Add($resolved)
                    $seen[$resolved] = $true
                }
            }
        }
    }

    return $results.ToArray()
}

function Resolve-BibliographyPaths {
    param(
        [string[]]$RequestedPaths,

        [Parameter(Mandatory = $true)]
        [string]$TexContent,

        [Parameter(Mandatory = $true)]
        [string]$TexFile
    )

    $results = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    if ($RequestedPaths -and $RequestedPaths.Count -gt 0) {
        foreach ($path in $RequestedPaths) {
            $resolved = Resolve-BibliographyCandidate -Candidate $path -BaseDirectory $repoRoot
            if ($resolved -and -not $seen.ContainsKey($resolved)) {
                $results.Add($resolved)
                $seen[$resolved] = $true
            }
        }
    }
    else {
        foreach ($path in (Get-BibliographyPathsFromTex -TexContent $TexContent -TexFile $TexFile)) {
            if ($path -and -not $seen.ContainsKey($path)) {
                $results.Add($path)
                $seen[$path] = $true
            }
        }

        if ($results.Count -eq 0 -and (Test-Path -LiteralPath $defaultBibliography)) {
            $resolvedDefault = [System.IO.Path]::GetFullPath($defaultBibliography)
            $results.Add($resolvedDefault)
            $seen[$resolvedDefault] = $true
        }
    }

    $existing = New-Object System.Collections.Generic.List[string]
    foreach ($path in $results) {
        if (Test-Path -LiteralPath $path) {
            $existing.Add($path)
        }
        else {
            Write-Warning "Bibliography file not found and will be skipped: $path"
        }
    }

    return $existing.ToArray()
}

function Get-DefaultOutputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TexFile
    )

    $directory = Split-Path -Parent $TexFile
    $name = [System.IO.Path]::GetFileNameWithoutExtension($TexFile)
    return Join-Path $directory "$name.docx"
}

$manuscript = Resolve-ExistingPathFromRoot -PathValue $TexPath -Description "TeX file"
$resourcePath = Split-Path -Parent $manuscript
$template = Resolve-PathFromRoot -PathValue $TemplatePath

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $output = Get-DefaultOutputPath -TexFile $manuscript
}
else {
    $output = Resolve-PathFromRoot -PathValue $OutputPath
}

Ensure-ParentDirectory -FilePath $output
Ensure-ReferenceDoc -TemplateFile $template

if (-not (Test-FileUnlocked -FilePath $output)) {
    throw "Output file is in use. Close Word and retry: $output"
}

$content = [System.IO.File]::ReadAllText($manuscript, $utf8)
$patchedContent = Apply-ExportOnlyPatches -Text $content
$bibliographyPaths = Resolve-BibliographyPaths -RequestedPaths $BibliographyPath -TexContent $content -TexFile $manuscript

$tempManuscriptName = "{0}.docx-export.tmp.tex" -f [System.IO.Path]::GetFileNameWithoutExtension($manuscript)
$tempManuscript = Join-Path $resourcePath $tempManuscriptName
[System.IO.File]::WriteAllText($tempManuscript, $patchedContent, $utf8NoBom)

try {
    $pandocArgs = @(
        "-f",
        "latex",
        "-s",
        $tempManuscript,
        "--resource-path=$resourcePath",
        "--lua-filter=$docxFilter",
        "-o",
        $output,
        "--reference-doc=$template",
        "--number-sections"
    )

    foreach ($bib in $bibliographyPaths) {
        $pandocArgs += "--bibliography=$bib"
    }

    if ($bibliographyPaths.Count -gt 0) {
        $pandocArgs += "--citeproc"
        $resolvedCsl = Resolve-PathFromRoot -PathValue $CslPath
        if (Test-Path -LiteralPath $resolvedCsl) {
            $pandocArgs += "--csl=$resolvedCsl"
        }
        else {
            Write-Warning "CSL file not found. Pandoc will use its default citation formatting: $resolvedCsl"
        }
    }
    else {
        Write-Warning "No bibliography file detected. Citations may remain unresolved in the docx output."
    }

    if ($IncludeToc) {
        $pandocArgs += "--toc"
    }

    Write-Host "Exporting $manuscript"
    Write-Host "Output    $output"

    & pandoc @pandocArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & python $postprocessScript $output
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    Write-Host "Generated $output"
}
finally {
    Remove-Item -LiteralPath $tempManuscript -ErrorAction SilentlyContinue
}
