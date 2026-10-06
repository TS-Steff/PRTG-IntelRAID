# PRTG Intel RAID Monitor

PowerShell monitors for Intel software RAID with a **PRTG HTTP Push Data Advanced Sensor**.
Monitoring is available for both **Intel VROC** and legacy **Intel RSTe** systems.

## Repository structure

```text
PRTG-IntelRAID/
|-- VROC/
|   |-- PRTG-IntelVROC.ps1
|   |-- PRTG-IntelVROC-Task.xml
|   `-- lookups/custom/
|-- RSTe/
|   |-- PRTG-IntelRSTe.ps1
|   |-- PRTG-IntelRSTe-Task.xml
|   `-- lookups/custom/
`-- README.md
```

VROC and RSTe keep their scripts, scheduled-task templates, and PRTG lookups
separate. The repository itself can therefore be renamed later without changing
the monitor logic.

## Intel VROC

The script runs locally on the Windows server, queries `IntelVROCCli.exe` and sends the RAID status directly to PRTG. No PRTG Probe is required on the monitored server.

## Requirements

- Windows Server
- Intel VROC
- Intel VROC CLI
- PowerShell 5.1+
- PRTG HTTP Push Data Advanced Sensor
- Administrator privileges for querying Intel VROC

Default CLI path:

```text
C:\Program Files\IntelVROCCli\bin\IntelVROCCli.exe
```

The script also checks the 32-bit installation path and `PATH`. For a custom
location, use `-CliPath`.

## Monitored values

- VROC controllers
- RAID volumes
- Volume errors
- Physical disks
- Disk errors
- Array members
- Spare disks

Any volume or disk state other than `Normal` is reported as an error.

The script does not require fixed RAID levels, volume names or disk counts and can therefore be used on different servers and VROC configurations.

## Usage

```powershell
.\VROC\PRTG-IntelVROC.ps1 -PushUrl "http://prtg.example.com:5050/YOUR-PUSH-TOKEN"
```

Custom CLI path:

```powershell
.\VROC\PRTG-IntelVROC.ps1 -PushUrl "http://prtg.example.com:5050/YOUR-PUSH-TOKEN" -CliPath "D:\Tools\IntelVROCCli.exe"
```

Test locally without sending data:

```powershell
.\VROC\PRTG-IntelVROC.ps1 -DryRun
```

This runs the Intel VROC CLI normally and prints the complete PRTG XML to the
console. `-PushUrl` is not required in dry-run mode. You can combine it with
`-CliPath`.

For continuous monitoring, create a Windows Task Scheduler task that runs every
**5 minutes**:

- Program: `powershell.exe`
- Arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\sm-it.ch\scripts\VROC\PRTG-IntelVROC.ps1" -PushUrl "http://prtg.example.com:5050/YOUR-PUSH-TOKEN"`
- Configure the task to run whether the user is logged on or not.
- Enable **Run with highest privileges** because IntelVROCCli may otherwise
  return `REQUEST_FAILED`.

Alternatively, import `VROC\PRTG-IntelVROC-Task.xml` into Task Scheduler. The
template runs every five minutes as `SYSTEM` with highest privileges and uses
`C:\sm-it.ch\scripts\VROC\PRTG-IntelVROC.ps1`. After importing it, open the task
action and replace `PRTG-SERVER` and `REPLACE_WITH_PRTG_PUSH_TOKEN` with
the values from the sensor's HTTP Push URL.
Do not save a real Push URL in the repository.


## Intel RSTe

The RSTe monitor is intended for older Intel Rapid Storage Technology enterprise
installations that expose their storage state through Intel's installed
PSI/PSIClient .NET components.

The script runs locally on the Windows server and sends the RAID status directly
to PRTG. No PRTG Probe is required on the monitored server.

### Requirements

- Windows Server
- Intel Rapid Storage Technology enterprise (RSTe) with the management components installed
- Windows PowerShell 5.1
- **32-bit PowerShell process**
- PRTG HTTP Push Data Advanced Sensor
- Administrator/SYSTEM privileges

The default RSTe installation path is:

```text
C:\Program Files (x86)\Intel\Intel(R) Rapid Storage Technology enterprise
```

The script loads the installed Intel assemblies from this directory. For a
different installation location, use `-RSTePath`.

> **Important:** The RSTe script must run in a fresh 32-bit Windows PowerShell
> process. Do not use the 64-bit `powershell.exe` from `System32`.

Use:

```text
C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe
```

The monitor only reads the Intel storage model. It does not invoke Intel storage
actions such as create, delete, rebuild, mark failed or modify RAID configuration.

### Monitored values

- RSTe controllers
- RAID volumes
- Volume warnings
- Volume errors
- Physical disks
- Disk errors
- Array members
- Spare disks
- Bad blocks

`Normal` is considered healthy for volumes and disks. Transitional volume states
such as rebuilding, verifying, syncing and migration are reported as warnings.
Other non-normal volume states and non-normal disk states are reported as errors.

The script does not require fixed RAID levels, volume names or disk counts.

### Usage

Test locally without sending data:

```powershell
C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe `
  -NoProfile -File ".\RSTe\PRTG-IntelRSTe.ps1" -DryRun
```

A healthy system returns PRTG XML similar to:

```text
RSTe OK - 2 Volumes, 7 Disks, 0 Spares - System RAID1_000, Data RAID5_000
```

For a real push:

```powershell
C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe `
  -NoProfile -File ".\RSTe\PRTG-IntelRSTe.ps1" `
  -PushUrl "https://prtg.example.com:5051/YOUR-PUSH-TOKEN"
```

For continuous monitoring, run the script every **5 minutes** in a fresh
32-bit PowerShell process. The recommended task runs as `SYSTEM` with highest
privileges and ignores a new trigger while the previous instance is still
running.

Alternatively, import `RSTe\PRTG-IntelRSTe-Task.xml` into Task Scheduler and
replace the placeholder Push URL with the URL of the PRTG sensor. The template
uses `C:\sm-it.ch\scripts\RSTe\PRTG-IntelRSTe.ps1`. Verify this path after
import and do not save a real Push URL in the repository.

### RSTe PRTG lookups

Copy the `.ovl` files from `RSTe\lookups\custom` to the custom lookup directory
on the PRTG system that receives the push data:

```powershell
Copy-Item ".\RSTe\lookups\custom\*.ovl" "C:\Program Files (x86)\PRTG Network Monitor\lookups\custom\"
```

Then reload lookup files in **Setup | System Administration | Administrative
Tools**.

The RSTe monitor uses these lookups:

- `sm-it.intelrste.volumewarnings` — `0` OK, `>0` Warning
- `sm-it.intelrste.volumeerrors` — `0` OK, `>0` Error
- `sm-it.intelrste.diskerrors` — `0` OK, `>0` Error
- `sm-it.intelrste.badblocks` — `0` OK, `>0` Error

Install and reload the lookup files before the first real push. PRTG applies
lookup metadata when it creates the channels. If the channels already exist
without the correct lookup, recreate the sensor or assign the matching lookup
manually in the channel settings.


## PRTG

Create an **HTTP Push Data Advanced Sensor** and use its Push URL when calling the script.

It is recommended to configure PRTG to set the sensor to **Down** if no data is received for approximately **10 minutes**. This also detects server, task or connectivity failures.

### PRTG lookups

Copy both `.ovl` files from `VROC\lookups\custom` to the custom lookup directory
on the PRTG probe that receives the push data:

```powershell
Copy-Item ".\VROC\lookups\custom\*.ovl" "C:\Program Files (x86)\PRTG Network Monitor\lookups\custom\"
```

In PRTG, open **Setup | System Administration | Administrative Tools** and
reload lookup files. The `Volume Errors` and `Disk Errors` channels use the
`Custom` unit and receive their lookup automatically when PRTG creates them:

- `sm-it.intelvroc.volumeerrors`
- `sm-it.intelvroc.diskerrors`

PRTG only reads the unit and lookup from push XML when it first creates a
channel. If the channels already show the `#` unit, either recreate the sensor
after installing the lookup files, or edit both channel settings: select the
`Custom` unit, select the matching lookup above, and disable channel limits.

## Security

The PRTG Push URL contains an authentication token.

- The examples use PRTG's default HTTP port `5050`; use HTTPS when available
- Do not commit real Push URLs or tokens to Git
- Do not include tokens in logs

## Tested with

### Intel VROC

- Intel VROC CLI 9.4.0.10037
- Intel VROC SATA 9.4.0.10037

### Intel RSTe

- Intel Rapid Storage Technology enterprise 5.5.4.1036
- Intel PSI/PSIClient management components
- RAID1 and RAID5 volumes

### PRTG

- PRTG HTTP Push Data Advanced Sensor

## License

See [LICENSE](LICENSE).

## Disclaimer

This project is not affiliated with or endorsed by Intel or Paessler.
