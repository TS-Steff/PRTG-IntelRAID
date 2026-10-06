<#
.SYNOPSIS
    Intel VROC Monitoring für PRTG HTTP Push Data Advanced

.DESCRIPTION
    - Liest Intel VROC über IntelVROCCli.exe aus
    - Prüft alle Controller, Volumes und Disks
    - Sendet Status per HTTP/HTTPS POST an PRTG
    - Keine serverspezifische RAID-Konfiguration notwendig

.PARAMETER PushUrl
    Push-URL des PRTG HTTP Push Data Advanced Sensors.

.PARAMETER CliPath
    Optionaler Pfad zu IntelVROCCli.exe. Ohne Angabe werden die bekannten
    Installationspfade und anschliessend PATH durchsucht.

.PARAMETER DryRun
    Führt die VROC-Abfrage aus und schreibt das PRTG-XML auf stdout, ohne
    Daten zu senden. PushUrl ist in diesem Modus nicht erforderlich.

.EXAMPLE
    .\PRTG-IntelVROC.ps1 -PushUrl "http://prtg.domain.tld:5050/TOKEN"

.EXAMPLE
    .\PRTG-IntelVROC.ps1 -DryRun
#>

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PushUrl,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CliPath,

    [Parameter()]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------

$CliPaths = @(
    'C:\Program Files\IntelVROCCli\bin\IntelVROCCli.exe',
    'C:\Program Files (x86)\IntelVROCCli\bin\IntelVROCCli.exe'
)

$TempFile = Join-Path `
    $env:TEMP `
    ("IntelVROC-{0}.xml" -f [guid]::NewGuid().ToString('N'))

# ---------------------------------------------------------------------------
# Funktionen
# ---------------------------------------------------------------------------

function ConvertTo-XmlSafe {
    param([AllowEmptyString()][string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    return [System.Security.SecurityElement]::Escape($Text)
}


function Format-PrtgText {
    param([AllowEmptyString()][string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    # PRTG schneidet Sensortexte bei # ab und erlaubt maximal 2000 Zeichen.
    $Text = ($Text -replace '#', 'Nr.') -replace '\s+', ' '
    $Text = $Text.Trim()

    if ($Text.Length -gt 2000) {
        return $Text.Substring(0, 1997) + '...'
    }

    return $Text
}


function Add-PrtgChannel {
    param (
        [Parameter(Mandatory)]
        [System.Text.StringBuilder]$Builder,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$Value,

        [string]$ValueLookup
    )

    [void]$Builder.AppendLine('  <result>')
    [void]$Builder.AppendLine(
        "    <channel>$(ConvertTo-XmlSafe $Name)</channel>"
    )
    [void]$Builder.AppendLine(
        "    <value>$Value</value>"
    )
    if ([string]::IsNullOrWhiteSpace($ValueLookup)) {
        [void]$Builder.AppendLine(
            '    <unit>Count</unit>'
        )
    }
    else {
        [void]$Builder.AppendLine(
            '    <unit>Custom</unit>'
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($ValueLookup)) {
        [void]$Builder.AppendLine(
            "    <valuelookup>$(ConvertTo-XmlSafe $ValueLookup)</valuelookup>"
        )
    }

    [void]$Builder.AppendLine('  </result>')
}


function Send-PrtgData {
    param (
        [Parameter(Mandatory)]
        [string]$Xml
    )

    try {
        if ($PushUri.Scheme -eq 'https') {
            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor
                [Net.SecurityProtocolType]::Tls12
        }

        Invoke-WebRequest `
            -Uri $PushUri `
            -Method Post `
            -ContentType 'application/xml; charset=utf-8' `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($Xml)) `
            -UseBasicParsing `
            -MaximumRedirection 0 `
            -TimeoutSec 30 | Out-Null
    }
    catch {
        # Die Exception von Invoke-WebRequest kann die URL und damit den
        # geheimen Push-Token enthalten. Deshalb bewusst nicht weiterreichen.
        throw 'PRTG-Übertragung fehlgeschlagen.'
    }
}


function Send-PrtgSystemError {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )

    $Message = Format-PrtgText $Message

    $xml = @"
<prtg>
  <error>1</error>
  <text>$(ConvertTo-XmlSafe $Message)</text>
</prtg>
"@

    if ($DryRun) {
        Write-Output $xml
    }
    else {
        try {
            Send-PrtgData -Xml $xml
        }
        catch {
            Write-Error 'PRTG-Übertragung fehlgeschlagen; Push-URL wird nicht protokolliert.'
        }
    }

    exit 1
}

# ---------------------------------------------------------------------------
# Parameter prüfen
# ---------------------------------------------------------------------------

$PushUri = $null

if (-not $DryRun) {
    if (
        [string]::IsNullOrWhiteSpace($PushUrl) -or
        -not [Uri]::TryCreate(
            $PushUrl,
            [UriKind]::Absolute,
            [ref]$PushUri
        ) -or
        $PushUri.Scheme -notin @('http', 'https')
    ) {
        Write-Error 'PushUrl muss eine absolute HTTP- oder HTTPS-URL sein.'
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Intel VROC CLI suchen
# ---------------------------------------------------------------------------

if ($CliPath) {
    if (-not (Test-Path -LiteralPath $CliPath -PathType Leaf)) {
        Send-PrtgSystemError -Message 'Der angegebene Intel-VROC-CLI-Pfad existiert nicht.'
    }

    $Cli = (Resolve-Path -LiteralPath $CliPath).Path
}
else {
    $Cli = $CliPaths |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1

    if (-not $Cli) {
        $CliCommand = Get-Command `
            -Name 'IntelVROCCli.exe' `
            -CommandType Application `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($CliCommand) {
            $Cli = $CliCommand.Source
        }
    }
}

if (-not $Cli) {
    Send-PrtgSystemError `
        -Message 'Intel VROC CLI nicht gefunden.'
}

# ---------------------------------------------------------------------------
# VROC auslesen
# ---------------------------------------------------------------------------

try {

    $CliOutput = & $Cli `
        --xml `
        --xmlfile $TempFile 2>&1

    $CliExitCode = $LASTEXITCODE

    if ($CliExitCode -ne 0) {

        Send-PrtgSystemError `
            -Message (
                "Intel VROC CLI Fehler " +
                "(ExitCode $CliExitCode): " +
                ($CliOutput -join ' ')
            )
    }

    if (-not (Test-Path $TempFile)) {

        Send-PrtgSystemError `
            -Message 'Intel VROC CLI hat keine XML-Datei erzeugt.'
    }

    $XmlReader = $null

    try {
        $XmlSettings = New-Object System.Xml.XmlReaderSettings
        $XmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $XmlSettings.XmlResolver = $null

        $XmlReader = [System.Xml.XmlReader]::Create(
            $TempFile,
            $XmlSettings
        )

        $VrocXml = New-Object System.Xml.XmlDocument
        $VrocXml.XmlResolver = $null
        $VrocXml.Load($XmlReader)
    }
    catch {
        Send-PrtgSystemError `
            -Message "VROC XML ungültig: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $XmlReader) {
            $XmlReader.Dispose()
        }
    }

    # -----------------------------------------------------------------------
    # Controller
    # -----------------------------------------------------------------------

    $Controllers = @(
        @($VrocXml.Controllers.Controller) |
            Where-Object { $null -ne $_ }
    )

    if ($Controllers.Count -eq 0) {

        Send-PrtgSystemError `
            -Message 'Kein Intel VROC Controller gefunden.'
    }

    # -----------------------------------------------------------------------
    # Volumes und Disks
    # -----------------------------------------------------------------------

    $Volumes = @(
        foreach ($Controller in $Controllers) {

            @($Controller.Volumes.Volume) |
                Where-Object { $null -ne $_ }
        }
    )

    $Disks = @(
        foreach ($Controller in $Controllers) {

            @($Controller.EndDevices.EndDevice) |
                Where-Object {
                    $null -ne $_ -and
                    [string]$_.Type -eq 'Disk'
                }
        }
    )

    # -----------------------------------------------------------------------
    # Fehlerzustände
    # -----------------------------------------------------------------------

    $BadVolumes = @(
        $Volumes |
            Where-Object {
                -not [string]::Equals(
                    [string]$_.State,
                    'Normal',
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
    )

    $BadDisks = @(
        $Disks |
            Where-Object {
                -not [string]::Equals(
                    [string]$_.State,
                    'Normal',
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
    )

    $ArrayMembers = @(
        $Disks |
            Where-Object {
                [string]::Equals(
                    [string]$_.Usage,
                    'Array member',
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
    )

    $Spares = @(
        $Disks |
            Where-Object {
                [string]::Equals(
                    [string]$_.Usage,
                    'Spare',
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            }
    )

    # -----------------------------------------------------------------------
    # Problemtexte
    # -----------------------------------------------------------------------

    $Problems = @()

    foreach ($Volume in $BadVolumes) {

        $VolumeName = [string]$Volume.Name

        if ([string]::IsNullOrWhiteSpace($VolumeName)) {
            $VolumeName = '(unbenannt)'
        }

        $Problems += (
            "Volume '$VolumeName' = $($Volume.State)"
        )
    }

    foreach ($Disk in $BadDisks) {

        $DiskName = [string]$Disk.ScsiAddress

        if ([string]::IsNullOrWhiteSpace($DiskName)) {
            $DiskName = [string]$Disk.ModelNo
        }

        if ([string]::IsNullOrWhiteSpace($DiskName)) {
            $DiskName = [string]$Disk.SerialNumber
        }

        if ([string]::IsNullOrWhiteSpace($DiskName)) {
            $DiskName = '(unbekannt)'
        }

        $Problems += (
            "Disk '$DiskName' = $($Disk.State)"
        )
    }

    # -----------------------------------------------------------------------
    # PRTG XML
    # -----------------------------------------------------------------------

    $Prtg = [System.Text.StringBuilder]::new()

    [void]$Prtg.AppendLine('<prtg>')

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Controllers' `
        -Value $Controllers.Count

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Volumes' `
        -Value $Volumes.Count

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Volume Errors' `
        -Value $BadVolumes.Count `
        -ValueLookup 'sm-it.intelvroc.volumeerrors'

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Disks' `
        -Value $Disks.Count

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Disk Errors' `
        -Value $BadDisks.Count `
        -ValueLookup 'sm-it.intelvroc.diskerrors'

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Array Members' `
        -Value $ArrayMembers.Count

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Spare Disks' `
        -Value $Spares.Count

    # -----------------------------------------------------------------------
    # Sensor-Text
    # -----------------------------------------------------------------------

    if ($Problems.Count -gt 0) {

        $SensorText =
            'VROC ERROR - ' +
            ($Problems -join '; ')
    }
    else {

        $VolumeInfo = @(
            foreach ($Volume in $Volumes) {

                "$($Volume.Name) RAID $($Volume.RaidLevel)"
            }
        )

        $SensorText =
            "VROC OK - " +
            "$($Volumes.Count) Volume(s), " +
            "$($Disks.Count) Disk(s), " +
            "$($Spares.Count) Spare(s)"

        if ($VolumeInfo.Count -gt 0) {

            $SensorText += `
                ' - ' + ($VolumeInfo -join ', ')
        }
    }

    $SensorText = Format-PrtgText $SensorText

    [void]$Prtg.AppendLine(
        "  <text>$(ConvertTo-XmlSafe $SensorText)</text>"
    )

    [void]$Prtg.AppendLine('</prtg>')

}
catch {

    Send-PrtgSystemError `
        -Message "VROC Monitoring Fehler: $($_.Exception.Message)"
}
finally {

    if (Test-Path $TempFile) {

        Remove-Item `
            -LiteralPath $TempFile `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

if ($DryRun) {
    Write-Output $Prtg.ToString()
}
else {
    # Erst nach der VROC-Verarbeitung senden, damit Übertragungsfehler nicht
    # als VROC-Fehler erneut an dieselbe URL gesendet werden.
    try {
        Send-PrtgData -Xml $Prtg.ToString()
        Write-Output $SensorText
    }
    catch {
        Write-Error 'PRTG-Übertragung fehlgeschlagen; Push-URL wird nicht protokolliert.'
        exit 1
    }
}
