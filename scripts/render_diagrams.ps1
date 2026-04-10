# Render all Mermaid diagrams to SVG (requires @mermaid-js/mermaid-cli installed globally).
# Usage: pwsh scripts/render_diagrams.ps1

$base = "docs/diagrams"
$out  = "docs/img"
$bg   = "#0a0a0f"

function Render-One($name) {
    $input = Join-Path $base "$name.mmd"
    $output = Join-Path $out "$name.svg"
    Write-Host "Rendering $input -> $output"
    mmdc -i $input -o $output -b $bg -w 1400 -H 900
}

$files = @("high_level","sequence","components","fsm","pipeline_timing","double_buffering","verification_flow","register_map")
foreach ($f in $files) { Render-One $f }
