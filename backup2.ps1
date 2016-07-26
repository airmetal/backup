#
#  Powershell script for Deloitte DR Backup Reinstall 
#  Version 1.0
#  Created By:  Dimension Data
#  Date: 03-09-2016
#  Usage from command-line:  C:\>powershell -NoProfile -executionpolicy bypass <full-path>\backup2.ps1 -user <DD CaaS username> -pass <DD Caas Password>
#  Command Line Option:  adding a "-skipdownloads"  as an option will disable downloading any files. Quotes are not needed.
#  NOTE:  Currently only works for North America region.

#Initialize command-line and script parameters 
param (
 [Parameter(Mandatory=$True)]
    [string]$user,
 [Parameter(Mandatory=$True)]
    [string]$pass,
    [switch]$skipdownloads
 )

$computer= $env:COMPUTERNAME
$backupinstallpath = "C:\Users\Administrator\Downloads\Windows-x64_86-BackupInstaller-"
$backuptargetpath = "C:\Users\Administrator\Downloads\"
$caasurl = "https://github.com/DimensionDataCBUSydney/DimensionData.ComputeClient/releases/download/v3.0.9/PowerShellForCaaS.msi"
$caaspath = "C:\Users\Administrator\Downloads\PowerShellForCaaS.msi"
$cvuninstallurl = "https://165.180.149.101/commvault/CVToolQUnInstallAllWinX64.exe"
$cvuninstallpath = "C:\Users\Administrator\Desktop\CVToolQUnInstallAllWinX64.exe"
$cvdirtargetpath = "C:\Users\Administrator\Desktop\cvtoolquninstallall\QUninstallAll.exe"
$cvuninstallerdir = "C:\Users\Administrator\Desktop\cvtoolquninstallall"
$caasmodsfrom = "C:\Program Files (x86)\Dimension Data\Modules\*"
$caasmodsto = "C:\Windows\System32\WindowsPowerShell\v1.0\Modules\"
$copyinstallerdir = "C:\Users\Administrator\Desktop\"
$regkey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
$regvalue = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -executionPolicy Unrestricted -File "C:\DD_Backup\backup2.ps1"' + " -user "+ $user + " -pass " + $pass + " -skipdownloads"
$regnoskipvalue = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -executionPolicy Unrestricted -File "C:\Users\Administrator\Documents\backup2.ps1"' + " -user "+ $user + " -pass " + $pass
$cvtusername = "didatapkgusr"
$cvtpassword = "vPXV7QEe2ydl1x+VhS+y"
$downloadclient = New-Object Net.WebClient
$secpasswd = new-object Security.SecureString
$pass.ToCharArray() | % { $secpasswd.AppendChar($_) }

if (![Environment]::Is64BitOperatingSystem)
{
    $backupinstallpath = "C:\Users\Administrator\Downloads\Windows-x32_86-BackupInstaller-"
    $cvuninstallpath = "C:\Users\Administrator\Desktop\CVToolQUnInstallAllWin32.exe"
    $backuptargetpath = "C:\temp\Windows-x32_86-BackupInstaller-"
    $cvuninstallurl = "https://165.180.149.101/commvault/CVToolQUnInstallAllWin32.exe"
} 

$ToolsDaemonPath = 'C:\Program Files\VMware\VMware Tools\vmtoolsd.exe'
$args= '--cmd "info-get guestinfo.ovfEnv"'
$env:Path = $env:Path + ";C:\Program Files\VMware\VMware Tools"

#Execute VMWare tools command to obtain XML document of Hypervisor network configs
$xdoc = & $ToolsDaemonPath --cmd "info-get guestinfo.ovfenv" | Out-String  

$ns = @{    xns = "http://schemas.dmtf.org/ovf/environment/1";
            xsi="http://www.w3.org/2001/XMLSchema-instance";
            oe="http://schemas.dmtf.org/ovf/environment/1";
            ve="http://www.vmware.com/schema/ovfenv"
       }

                $section =  $xdoc | Select-Xml 'xns:Environment/xns:PropertySection' -Namespace $ns
                   $s = $section | Select-Xml '//xns:Property' -Namespace $ns 
                   $key = $s[0] | Select-Xml '//@oe:key' -Namespace $ns
                   $val = $s[0] | Select-Xml '//@oe:value' -Namespace $ns

                   for($i=0; $i -lt $key.Length; $i++){
                        if($key[$i].ToString().Split(":")[0] -eq "ipV6"){
                            $ipv6addr = $val[$i]
                        }
                            
                   }
Write-Host "Starting the Backup reinstall process..."
if(!$skipdownloads){
    Write-Host "Downloading pre-requisite PowerSHell CaaS SDK"
    Invoke-WebRequest $caasurl -OutFile $caaspath
    Write-Host "Installing downloaded PowerSHell CaaS SDK"
    $args = "/i " + $caaspath + " /l*v C:\caasmsilog.txt /qn"
    (Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -Passthru).ExitCode
    Copy-Item $caasmodsfrom -Destination $caasmodsto -recurse
}
Write-Host "Checking .Net 3.5 is available. If not then it will be installed"
Install-WindowsFeature -name NET-Framework-Features

Write-Host "Connecting to Dimension Data cloud"
Import-Module CaaS 
$login= New-Object System.Management.Automation.PSCredential ($user, $secpasswd) 
New-CaasConnection -ApiCredentials $login -Vendor DimensionData -Region NorthAmerica_NA
Write-Host "Successfully connect to Dimension Data cloud"

Write-Host "Locating the IPv6 address of this Server"

Write-Host "Found IPv6 address:" $ipv6addr

Write-Host "Retrieving this server's metadata from Dimension Data cloud"
# i.e. this server, by matching IPv6 address
$page = 1
$servers = Get-CaasServer

while($servers.Length -le 250){
    $serverWithBackup =  $servers | Where {$_.networkInfo.primaryNic.ipv6 -Like $ipv6addr}
    if($serverWithBackup -notlike ""){
        break
    }else{
        $page = $page + 1
        $servers = Get-CaasServer -PageNumber $page
    }
}
if($serverWithBackup -notlike ""){
    
    $backupapp = Get-WmiObject -Class Win32_Product | Where-Object {
        $_.Name -match "Cloud Backup”
    }
    Write-Host "Server name in Cloud Control for this server is" $serverWithBackup.name

    Write-host "Retrieving the download URL for the backup agent installer"
    $client = Get-CaasBackupClients -Server $serverWithBackup
    $backupinstallurl = $client.downloadUrl
    Write-Host "Download URL is:" $backupinstallurl

    $backupinstallpathMod =  $backupinstallpath + $serverWithBackup.name +".msi"
    $copyinstallerdir += $serverWithBackup.name +".msi"
    
    if($backupapp){
        Write-Host "Downloading the Commvault uninstall file"
        if(!$skipdownloads){
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            $webclient = New-Object Net.WebClient
            $webclient.Credentials = new-object System.Net.NetworkCredential($cvtusername, $cvtpassword)
            $webclient.DownloadFile($cvuninstallurl, $cvuninstallpath)
        }

        Write-Host "Executing the downloaded Commvault file to unzip compressed files"
        (Start-Process -FilePath $cvuninstallpath  -Wait -Passthru).ExitCode

        Write-Host "Executing the commavault uninstaller to remove all components"
        $exitA = (Start-Process -FilePath $cvdirtargetpath -ArgumentList "/q" -Wait -Passthru).ExitCode
        if($exitA -eq 0 ){
            Write-Host "Waiting for the silent uninstall to finish up"
            Start-Sleep -s 60
            Write-Host "Commvault agent has been removed"
            Set-ItemProperty -Path $regkey -Name "ReinstallBackup" -Value $regvalue
            Write-Host "Rebooting..."
            Start-Sleep -s 10
            Restart-Computer
        }else{
            Write-Host "Exit code returned with error:" $exitA
        }
        Write-Host "Uninstalling Cloud Backup application from DimensionData"
        $exitB = $backupapp.Uninstall()
        if($exitB.returnvalue -eq 0){
            Write-Host "Successfully removed backup application"
            Write-Host "Dimension Data Cloud Backup has been UNINSTALLED!"
            Set-ItemProperty -Path $regkey -Name "ReinstallBackup" -Value $regnoskipvalue
            Remove-Item $cvuninstallpath
            Remove-Item $cvuninstallerdir -Recurse
            Write-Host "Rebooting..."
            Start-Sleep -s 10
            Restart-Computer 
        }else{
            Write-Host "Exit code returned with error:" $exitB
        }
    }else{
        
        Write-Host "Downloading the Backup Agent Install file from CloudControl (Dimension Data cloud)"
        if(!$skipdownloads){
            $downloadclient.DownloadFile($backupinstallurl, $backupinstallpathMod)
        }
        Write-Host "Copying the Backup agent installer files to temp directory"
        Copy-Item $backupinstallpathMod -Destination $copyinstallerdir
        Start-sleep -s 3

        Write-Host "Executing the Backup agent installer"
        $args = "/i " + $copyinstallerdir + " /qn TARGETDIR=`""+ $backuptargetpath +"`" /l*v C:\backupinstmsilog.txt"
        $exit = (Start-Process -FilePath "msiexec.exe" -ArgumentList $args  -Wait -Passthru).ExitCode
        if($exit -eq 0){
            Write-Host "Waiting for the silent install to finish up"
            Start-Sleep -s 420
            Remove-Item $copyinstallerdir
            Write-Host "Dimension Data Cloud Backup has been INSTALLED!"
            Write-Host "Rebooting..."
            Start-Sleep -s 10
            Restart-Computer
        }else{
            Write-Host "Exit code returned with error:" $exit
        } 
    }
   
}else{
    Write-Host "Dimension Data Cloud Backup re-install FAILED!  Unable to retrieve server details from Dimension Data Cloud"
}
Write-Host "END"