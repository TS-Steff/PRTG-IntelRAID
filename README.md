# PRTG Intel VROC Monitor

PowerShell script for monitoring **Intel VROC RAID** with a **PRTG HTTP Push Data Advanced Sensor**.

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
.\PRTG-IntelVROC.ps1 -PushUrl "http://prtg.example.com:5050/YOUR-PUSH-TOKEN"
```

Custom CLI path:

```powershell
.\PRTG-IntelVROC.ps1 -PushUrl "http://prtg.example.com:5050/YOUR-PUSH-TOKEN" -CliPath "D:\Tools\IntelVROCCli.exe"
```

Test locally without sending data:

```powershell
.\PRTG-IntelVROC.ps1 -DryRun
```

This runs the Intel VROC CLI normally and prints the complete PRTG XML to the
console. `-PushUrl` is not required in dry-run mode. You can combine it with
`-CliPath`.

For continuous monitoring, create a Windows Task Scheduler task that runs every
**5 minutes**:

- Program: `powershell.exe`
- Arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\PRTG-IntelVROC.ps1" -PushUrl "http://prtg.example.com:5050/YOUR-PUSH-TOKEN"`
- Configure the task to run whether the user is logged on or not.
- Enable **Run with highest privileges** because IntelVROCCli may otherwise
  return `REQUEST_FAILED`.

Alternatively, import `PRTG-IntelVROC-Task.xml` into Task Scheduler. The
template runs every five minutes as `SYSTEM` with highest privileges and uses
`C:\sm-it.ch\scripts\PRTG-IntelVROC.ps1`. After importing it, open the task
action and replace `PRTG-SERVER` and `REPLACE_WITH_PRTG_PUSH_TOKEN` with
the values from the sensor's HTTP Push URL.
Do not save a real Push URL in the repository.

## PRTG

Create an **HTTP Push Data Advanced Sensor** and use its Push URL when calling the script.

It is recommended to configure PRTG to set the sensor to **Down** if no data is received for approximately **10 minutes**. This also detects server, task or connectivity failures.

### PRTG lookups

Copy both `.ovl` files from `lookups\custom` to the custom lookup directory
on the PRTG probe that receives the push data:

```powershell
Copy-Item ".\lookups\custom\*.ovl" "C:\Program Files (x86)\PRTG Network Monitor\lookups\custom\"
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

- Intel VROC CLI 9.4.0.10037
- Intel VROC SATA 9.4.0.10037
- PRTG HTTP Push Data Advanced Sensor

## License

See [LICENSE](LICENSE).

## Disclaimer

This project is not affiliated with or endorsed by Intel or Paessler.
