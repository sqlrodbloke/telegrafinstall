
param([String]$Server,[int]$interval,[String]$SourceFolder,[switch]$upgradetelegrafexe)

	
function Set-TelegrafConfig {
    <#
        
        .DESCRIPTION
            Generates the required Telegraf config for a target server from a template file
            Also grants required permissions for Telegraf service account used.
            Will default to permission [NT AUTHORITY\SYSTEM] if not specified.

            Returns the Path of the config file generated
        .NOTES          
        Usage: Set-TelegrafConfig -Computername SQLServer1 -TemplateConfig='D:\GIT\DBA-Telegraf\Files\sqlserver_telegraf_Template.conf' -$SQLServAcc '[NT AUTHORITY\SYSTEM]'

    #>
    
    Param ([string]$computername,
            [String]$templateConfig,
            [String]$SQLServAcc
        )

try {
If (-not $SQLServAcc){$SQLServAcc="[NT AUTHORITY\SYSTEM]"}
$OutputConf=(Split-Path $templateConfig)+"\sqlserver_telegraf_$servername.conf"

$Confblock=$null
Write-Host "Obtaining list of SQL Instances from $computername" -ForegroundColor Cyan
$SQLInstances = Invoke-Command -ComputerName $ComputerName {
    (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances
    }

If ($SQLInstances){
    foreach ($sql in $SQLInstances) {      
    $InstanceName = "$computername\$sql".Replace('\MSSQLSERVER','')
   
    Write-Host "Adding Telegraf SQL Permissions to $InstanceName" -ForegroundColor Cyan
    Invoke-Sqlcmd -ServerInstance $InstanceName -Database master -Query "GRANT VIEW SERVER STATE TO $SQLServAcc; GRANT VIEW ANY DEFINITION TO $SQLServAcc;" -ConnectionTimeout 15 -QueryTimeout 15
    
    $InstanceName = $InstanceName.Replace('\','\\')
    $Confline='"'+"Server=$InstanceName;Database=master;Integrated Security=SSPI;log=1;"+'",'  
    $Confblock+="$Confline`n"

    }  
    Write-Host "SQL Connection String Block:" -ForegroundColor Magenta
    Write-Host $Confblock -ForegroundColor Magenta

    $Change = Get-Content $templateConfig
    $Change=$Change | ForEach-Object {$_  -Replace "<_ServersPlaceHolders_>","$ConfBlock" }  
    $Change=$Change | ForEach-Object {$_  -Replace "<_collectioninterval_>","$interval" }  
    $Change | Set-Content $OutputConf 
    }
else {      
    Write-Host "SQL Instances Not Detected on $Computername " -ForegroundColor Red
    }

If (Test-Path -Path $OutputConf -PathType Leaf){
    Return $OutputConf
    }
}
catch
    {
        Write-Host "----- Exception -----"
        Write-Host  $_.Exception
        Write-Host  $_.Exception.Response.StatusCode
        Write-Host  $_.Exception.Response.StatusDescription
    }

}

## MAIN


If (-not $Server){
    Write-Host "Server name must be passed as a parameter" -ForegroundColor Red
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host ".\install-telegraf.ps1 -server {Servername} -Interval (Optional) {Collection interval in seconds -default 60} "  -ForegroundColor Green 
    Write-host "-SourceFolder (optional) {Path to config templates} "  -ForegroundColor Green 
    Write-host "-upgradetelegrafexe (optional switch to copy new telegraf.exe)" -ForegroundColor Green 
    Return
}



#Default to 60s interval collection if not supplied
If (-not $interval){
    $interval=60
}

try {
    

$scriptpath = Split-Path $script:MyInvocation.MyCommand.Path

If (-not $SourceFolder){
    $SourceFolder=$scriptpath
}

$Logpath="$scriptpath\Logs"
$LogName="InstallTelegraf"


If(-not (test-path -PathType container $Logpath))
{
      New-Item -ItemType Directory -Path $Logpath
}

Start-Transcript -Path "$Logpath\$LogName-$($Server.Replace('\','_'))-$(Get-Date -format dd-MM-yyyy-hhmm).log" -IncludeInvocationHeader

$SourceFile='sqlserver_telegraf_Template.conf'

$templateConfig=Join-Path $SourceFolder $SourceFile

Clear-Host
Write-Host "Generating Telegraf Config files..." -ForegroundColor Cyan


#Installation / Update
#Check if service present

$service = Get-Service -Computername $server -Name telegraf -ErrorAction SilentlyContinue
if($null -eq $service)
{
    Write-Host "Looking for Telegraf Service....NOT FOUND."
    Write-Host "Creating  folder $TargetFolder on $server"
    Invoke-Command -ComputerName $server -ScriptBlock { New-Item -ItemType Directory -Force -Path "C:\Program Files\Telegraf"}
    Write-Host "Copying required files to Server $server"

    $OutputConffile=Set-TelegrafConfig -Computername $server -TemplateConfig $templateConfig
    Write-Host $OutputConffile -ForegroundColor Magenta

    Move-Item  $OutputConffile -Destination "\\$server\C$\Program Files\telegraf\sqlserver_telegraf.conf" -Force


    Copy-Item $SourceFolder\telegraf.exe -Destination "\\$server\c$\Program Files\telegraf\" -Force
    Invoke-Command -ComputerName $server -ScriptBlock {& "C:\Program Files\Telegraf\telegraf.exe"  --service install --config "C:\Program Files\Telegraf\sqlserver_telegraf.conf"}

} else {
    Write-Host "Telegraf Service already exists, replacing config file with new version."
	Write-Host "Stopping Telegraf Service." -ForegroundColor Cyan
    Invoke-Command -ComputerName $server -ScriptBlock {& "C:\Program Files\Telegraf\telegraf.exe" --service stop}
    Write-Host "Copying Telegraf files to Target Server $server" -ForegroundColor Cyan
    $OutputConffile=Set-TelegrafConfig -Computername $server -TemplateConfig $templateConfig -pluginconfig $pluginconfig
    Move-Item  $OutputConffile -Destination "\\$server\C$\Program Files\telegraf\sqlserver_telegraf.conf" -Force
    If ($upgradetelegrafexe){
        Write-Host "...also copying new Telegraf.exe file as requested" -ForegroundColor Yellow
        Copy-Item  "$SourceFolder\telegraf.exe" -Destination "\\$server\C$\Program Files\telegraf\telegraf.exe" -Force
    }

}

    Write-Host "Starting Telegraf Service." -ForegroundColor Cyan
    Invoke-Command -ComputerName $server -ScriptBlock {& "C:\Program Files\Telegraf\telegraf.exe" --service start}
	Write-Host "Telegraf installation/config Complete." -ForegroundColor Green
}
catch {
    $exception = $_.Exception.Message
    write-host "Failed Telegraf Installation: $Server - $exception" -ForegroundColor Red
}

finally {
Stop-Transcript
}

