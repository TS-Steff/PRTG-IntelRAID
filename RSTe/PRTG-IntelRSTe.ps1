#requires -Version 5.1
<#
.SYNOPSIS
    Intel RSTe Monitoring fuer PRTG HTTP Push Data Advanced

.DESCRIPTION
    - Liest Intel Rapid Storage Technology enterprise (RSTe) ueber die
      installierten Intel PSI/PSIClient .NET-Komponenten aus.
    - Prueft alle Controller, Volumes und Disks.
    - Sendet Status per HTTP/HTTPS POST an PRTG.
    - Keine serverspezifische RAID-Konfiguration notwendig.
    - Fuehrt keine Storage-/RAID-Aktionen aus.

.PARAMETER PushUrl
    Push-URL des PRTG HTTP Push Data Advanced Sensors.

.PARAMETER RSTePath
    Installationspfad von Intel Rapid Storage Technology enterprise.

.PARAMETER DryRun
    Fuehrt die RSTe-Abfrage aus und schreibt das PRTG-XML auf stdout,
    ohne Daten zu senden. PushUrl ist in diesem Modus nicht erforderlich.

.EXAMPLE
    .\PRTG-IntelRSTe.ps1 -PushUrl "https://prtg.domain.tld:5051/TOKEN"

.EXAMPLE
    .\PRTG-IntelRSTe.ps1 -DryRun

.NOTES
    Das Skript muss in einem frischen 32-Bit Windows PowerShell 5.1 Prozess
    ausgefuehrt werden:
    C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe
#>

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$PushUrl,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RSTePath = 'C:\Program Files (x86)\Intel\Intel(R) Rapid Storage Technology enterprise',

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------

$VolumeWarningStates = @(
    'Initializing',
    'Rebuilding',
    'Verifying',
    'VerifyAndFix',
    'GeneralMigration',
    'StateChanging',
    'DiskReplace',
    'ManualSyncing',
    'ManualReverseSyncing',
    'Syncing',
    'SyncPausedDCPowerSave',
    'ReverseSyncing'
)

$HealthyVolumeStates = @('Normal')
$HealthyDiskStates   = @('Normal')
$ArrayMemberUsages   = @('ArrayMember', 'ArrayMemberReadOnlyMount')
$SpareUsages         = @('Spare')

$RequiredAssemblies = @(
    'IAStorCommon.dll',
    'IAStorUtil.dll',
    'PsiData.dll',
    'PSI.dll',
    'PSIClient.dll'
)

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
        [long]$Value,

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
        [void]$Builder.AppendLine('    <unit>Count</unit>')
    }
    else {
        [void]$Builder.AppendLine('    <unit>Custom</unit>')
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
        # Invoke-WebRequest Exceptions koennen die URL und damit den
        # geheimen Push-Token enthalten. Deshalb nicht weiterreichen.
        throw 'PRTG-Uebertragung fehlgeschlagen.'
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
            Write-Error 'PRTG-Uebertragung fehlgeschlagen; Push-URL wird nicht protokolliert.'
        }
    }

    exit 1
}

# ---------------------------------------------------------------------------
# Parameter / Umgebung pruefen
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

if ([Environment]::Is64BitProcess) {
    Send-PrtgSystemError -Message (
        'Das Skript muss in 32-Bit Windows PowerShell 5.1 laufen. ' +
        'Verwende C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe.'
    )
}

if (-not (Test-Path -LiteralPath $RSTePath -PathType Container)) {
    Send-PrtgSystemError -Message 'Intel RSTe Installationsverzeichnis nicht gefunden.'
}

# ---------------------------------------------------------------------------
# RSTe auslesen
# ---------------------------------------------------------------------------

try {
    foreach ($Assembly in $RequiredAssemblies) {
        $AssemblyPath = Join-Path $RSTePath $Assembly

        if (-not (Test-Path -LiteralPath $AssemblyPath -PathType Leaf)) {
            throw "Erforderliche Intel RSTe Assembly fehlt: $Assembly"
        }

        [Reflection.Assembly]::LoadFrom($AssemblyPath) | Out-Null
    }

    if (-not [PSIClient.PsiClient]::Init()) {
        throw 'Intel PSIClient Initialisierung fehlgeschlagen.'
    }

    $Client = [PSIClient.PsiClient]::Instance

    if ($null -eq $Client) {
        throw 'Intel PSIClient Instanz ist nach der Initialisierung nicht verfuegbar.'
    }

    $SDM = $Client.SystemDataModel

    if ($null -eq $SDM) {
        throw 'Intel PsiSystemDataModel ist nach der Initialisierung nicht verfuegbar.'
    }

    $Controllers = @(
        @($SDM.ControllerCollection) |
            Where-Object { $null -ne $_ }
    )

    $Volumes = @(
        @($SDM.VolumeCollection) |
            Where-Object { $null -ne $_ }
    )

    $Disks = @(
        @($SDM.DiskCollection) |
            Where-Object { $null -ne $_ }
    )

    if ($Controllers.Count -eq 0) {
        throw 'Kein Intel RSTe Controller gefunden.'
    }

    # -----------------------------------------------------------------------
    # Zustaende auswerten
    # -----------------------------------------------------------------------

    $VolumeWarnings = @(
        $Volumes |
            Where-Object {
                [string]$_.State -in $VolumeWarningStates
            }
    )

    $VolumeErrors = @(
        $Volumes |
            Where-Object {
                $State = [string]$_.State
                $State -notin $HealthyVolumeStates -and
                $State -notin $VolumeWarningStates
            }
    )

    $DiskErrors = @(
        $Disks |
            Where-Object {
                [string]$_.State -notin $HealthyDiskStates
            }
    )

    $ArrayMembers = @(
        $Disks |
            Where-Object {
                [string]$_.Usage -in $ArrayMemberUsages
            }
    )

    $Spares = @(
        $Disks |
            Where-Object {
                [string]$_.Usage -in $SpareUsages
            }
    )

    [long]$BadBlocks = 0

    foreach ($Volume in $Volumes) {
        if ($null -ne $Volume.BadBlocks) {
            try {
                $BadBlocks += [long]$Volume.BadBlocks
            }
            catch {
                throw "BadBlocks von Volume '$([string]$Volume.Volume)' ist ungueltig."
            }
        }
    }

    # -----------------------------------------------------------------------
    # Problemtexte
    # -----------------------------------------------------------------------

    $Problems = @()

    foreach ($Volume in $VolumeWarnings) {
        $VolumeName = [string]$Volume.Volume

        if ([string]::IsNullOrWhiteSpace($VolumeName)) {
            $VolumeName = '(unbenannt)'
        }

        $Problems += "WARN Volume '$VolumeName' = $([string]$Volume.State)"
    }

    foreach ($Volume in $VolumeErrors) {
        $VolumeName = [string]$Volume.Volume

        if ([string]::IsNullOrWhiteSpace($VolumeName)) {
            $VolumeName = '(unbenannt)'
        }

        $Problems += "ERROR Volume '$VolumeName' = $([string]$Volume.State)"
    }

    foreach ($Disk in $DiskErrors) {
        $DiskName = [string]$Disk.DeviceID

        if ([string]::IsNullOrWhiteSpace($DiskName)) {
            $DiskName = '(unbekannt)'
        }

        $Problems += "ERROR Disk '$DiskName' = $([string]$Disk.State)"
    }

    if ($BadBlocks -gt 0) {
        $Problems += "ERROR Bad Blocks = $BadBlocks"
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
        -Name 'Volume Warnings' `
        -Value $VolumeWarnings.Count `
        -ValueLookup 'sm-it.intelrste.volumewarnings'

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Volume Errors' `
        -Value $VolumeErrors.Count `
        -ValueLookup 'sm-it.intelrste.volumeerrors'

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Disks' `
        -Value $Disks.Count

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Disk Errors' `
        -Value $DiskErrors.Count `
        -ValueLookup 'sm-it.intelrste.diskerrors'

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Array Members' `
        -Value $ArrayMembers.Count

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Spare Disks' `
        -Value $Spares.Count

    Add-PrtgChannel `
        -Builder $Prtg `
        -Name 'Bad Blocks' `
        -Value $BadBlocks `
        -ValueLookup 'sm-it.intelrste.badblocks'

    # -----------------------------------------------------------------------
    # Sensor-Text
    # -----------------------------------------------------------------------

    if ($Problems.Count -gt 0) {
        $SensorText = 'RSTe - ' + ($Problems -join '; ')
    }
    else {
        $VolumeInfo = @(
            foreach ($Volume in $Volumes) {
                $Name = [string]$Volume.Volume
                $Raid = [string]$Volume.RaidType

                if ([string]::IsNullOrWhiteSpace($Name)) {
                    $Name = '(unbenannt)'
                }

                if ([string]::IsNullOrWhiteSpace($Raid)) {
                    "$Name"
                }
                else {
                    "$Name $Raid"
                }
            }
        )

        $SensorText =
            "RSTe OK - " +
            "$($Volumes.Count) Volumes, " +
            "$($Disks.Count) Disks, " +
            "$($Spares.Count) Spares"

        if ($VolumeInfo.Count -gt 0) {
            $SensorText += ' - ' + ($VolumeInfo -join ', ')
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
        -Message "RSTe Monitoring Fehler: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
# Ausgabe / Push
# ---------------------------------------------------------------------------

if ($DryRun) {
    Write-Output $Prtg.ToString()
}
else {
    # Erst nach der RSTe-Verarbeitung senden, damit Uebertragungsfehler nicht
    # als RSTe-Fehler erneut an dieselbe URL gesendet werden.
    try {
        Send-PrtgData -Xml $Prtg.ToString()
        Write-Output $SensorText
    }
    catch {
        Write-Error 'PRTG-Uebertragung fehlgeschlagen; Push-URL wird nicht protokolliert.'
        exit 1
    }
}
