<#
Powershell script to query one or all windows computers in a domain for their configured IP Address, Subnet Mask, Default Gateway, DNS Servers, and DNS Suffix Search List.
The script reports on whether the server is online, to explain empty lines by using test-connection.
Additionally the report includes the AD Site the computer is associated with, and the result of a DNS query for the name to verify the registered IP addresses.

The general purpose of all this being to document and find anomalies which cause network issues, often appearing to be random in cause.

Primarily the intended target is server computers.

Get-RemoteIPConfig
    [-ComputerName] <string>
    [-Path] <string>
    [-ServersOnly] <switch>

Get-RemoteIPConfig
    [-SearchBase] <string>
    [-RootOnly] <switch>
    [-Path] <string>
    [-ServersOnly] <switch>
    
Required Parameters:
No parameters are required, when run without parameters the script will gather this information for all computers in Active Directory.

Optional Parameters:
ComputerName: The name of the specific computer to query. This accepts partial names.
SearchBase: The OU which contains the windows computers to query. This needs to be the full and correct path.
RootOnly: Used with the SearchBase switch, causes the report to only query computers in the specified OU, and not child OUs.
Path: The path and file name for the output CSV file. If omitted the path is the current directory, and the file name is RemoteIPConfigDDMMYYYY.csv
ServersOnly: Modifies the query to include only Windows Server operating systems.

Examples:

Report on a single server.
Get-RemoteIPConfig -ComputerName "server.domain.com"

Report on all servers in a specific OU.
Get-RemoteIPConfig -SearchBase "OU=Servers,OU=Maine,DC=domain,DC=com" -RootOnly -ServersOnly

Report on all windows systems with SQL in the computer name.
Get-RemoteIPConfig -ComputerName "SQL"

#>

param(
[parameter(ParameterSetName="SearchBase",mandatory=$false,HelpMessage="The name or partial name of the computer or computers to query.")]
[parameter(ParameterSetName="Computer",mandatory=$false,HelpMessage="The name or partial name of the computer or computers to query.")]
[string]$ComputerName,
[parameter(ParameterSetName="SearchBase",Mandatory=$true,HelpMessage="The path of the OU which contains the computers to query.")]
[string]$SearchBase,
[parameter(ParameterSetName="SearchBase",Mandatory=$false,HelpMessage="When using SearchBase, this switch limits the query to only the specific container.")]
[switch]$RootOnly,
[parameter(ParameterSetName="Computer",mandatory=$false,HelpMessage="The path and filename to output the CSV file.")]
[parameter(ParameterSetName="SearchBase",Mandatory=$false,HelpMessage="The path and filename to output the CSV file.")]
[string]$Path,
[parameter(ParameterSetName="Computer",Mandatory=$false,HelpMessage="Search for Servers only.")]
[parameter(ParameterSetName="SearchBase",Mandatory=$false,HelpMessage="Search for Servers only.")]
[switch]$ServersOnly
)

#Current Path
$CurrentPath=Split-Path $script:MyInvocation.MyCommand.Path

#CSV File name

IF($Path)
{
$FileName = $Path
}
ELSE
{
$DTStamp = (Get-Date -Format MMddyyyy).ToString()
$FileName = "$CurrentPath\RemoteIPConfig$DTStamp.csv"

}

#Set Search Base
IF($SearchBase)
{
$SearchBase = $SearchBase
}
ELSE
{
$SearchBase = (Get-ADDomain).DistinguishedName
}

#Set Search Scope
IF($RootOnly)
{
$SearchScope = 1
}
ELSE
{
$SearchScope = 2
}

#Set the Computer Name to use in the query.
IF($ComputerName)
{
$ComputerName = "'*$ComputerName*'"
}
ELSE
{
$ComputerName = "'*'"
}

#Query Servers Only.
IF($ServersOnly)
{
$OSQuery = "'*windows*server*'"
}
ELSE
{
$OSQuery = "'*windows*'"
}

#Gather list of servers into a variable.
$Servers = Get-ADComputer -Filter "Enabled -eq 'True' -and OperatingSystem -like $OSQuery -and DNSHostName -like $ComputerName" -SearchBase $SearchBase -SearchScope $SearchScope -Properties OperatingSystem

foreach ($Server in $Servers){
   
   write-host "Testing $Server"
   #Get IPs registered in DNS for that name.
   #Test if the system is online.
   $PingResponse = Test-Connection -ComputerName $Server.DNSHostName -quiet -Count 2
   
   IF($PingResponse -eq $true){
       $RegisteredIPs = [string](Resolve-DnsName $Server.DNSHostName).IPAddress

       #Get the server's site  
       $clientsitename = (Get-WmiObject -ComputerName $Server.DNSHostName -Query "Select ClientSiteName from Win32_NTDomain" -ErrorAction SilentlyContinue).ClientSiteName

        #For each server, gather list of Ethernet adapters
        $Nics = Get-WmiObject -ComputerName $Server.DNSHostName -Namespace Root\CimV2 -Query "Select * from Win32_NetworkAdapter where AdapterType like 'Ethernet%'" -ErrorAction SilentlyContinue
        
        #For each ethernet adapter, gather IP Address, Subnetmask, DNSSuffixSearchOrder, DNS Servers
            foreach($Nic in $Nics){    
            $q = ("Select * from Win32_NetworkAdapterConfiguration Where Index=" + $Nic.deviceID)
            $Nac = Get-WmiObject -ComputerName $Server.DNSHostName -Namespace Root\Cimv2 -Query $q -ErrorAction SilentlyContinue
            $DNSDomainSuffixSearchOrder = [string]$nac.DNSDomainSuffixSearchOrder
            $DNSServerSearchOrder = [string]$nac.DNSServerSearchOrder
            $IPAddress = [string]$nac.IPAddress
            $SubnetMask = [string]$Nac.IPSubnet
            $DefaultGateway = [string]$nac.DefaultIPGateway
            $ClientSiteName = [string]$ClientSiteName
              
        
        
                New-Object -TypeName PSObject -Property @{
                    ServerName = $Server.Name
                    OperatingSystem = $Server.OperatingSystem
                    EthernetAdapter = $Nic.Name
                    IPAddress = $IPAddress
                    SubnetMask = $SubnetMask
                    DefaultGateway = $DefaultGateway
                    DNSServers = $DNSServerSearchOrder
                    DNSSuffixes = $DNSDomainSuffixSearchOrder
                    Site = $ClientSiteName
                    Online = $PingResponse
                    RegisteredIPs = $RegisteredIPs
                } | export-csv -NoTypeInformation -Path $FileName -Append
            }
    }
    ELSE{
        $RegisteredIPs = ""
        $clientsitename = ""
        $DNSDomainSuffixSearchOrder = ""
        $DNSServerSearchOrder = ""
        $DefaultGateway = ""
        $SubnetMask = ""
        $IPAddress = ""
        $Nic = ""
        
        New-Object -TypeName PSObject -Property @{
                    ServerName = $Server.Name
                    OperatingSystem = $Server.OperatingSystem
                    EthernetAdapter = $Nic.Name
                    IPAddress = $IPAddress
                    SubnetMask = $SubnetMask
                    DefaultGateway = $DefaultGateway
                    DNSServers = $DNSServerSearchOrder
                    DNSSuffixes = $DNSDomainSuffixSearchOrder
                    Site = $ClientSiteName
                    Online = $PingResponse
                    RegisteredIPs = $RegisteredIPs
        } | export-csv -NoTypeInformation -Path $FileName -Append
    }     
     
} 
