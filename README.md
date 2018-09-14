# Windows

Get-ADUserStatistics.ps1: Connects to Active Directory and gathers information about a user, members of a group, users in an OU, or all users in the domain.
Get-ADUserStatistics.ps1
    [-UserName] <string>
    [-Path] <string>

Get-ADUserStatistics.ps1
    [-GroupName] <string>
    [-Path] <string>

Get-ADUserStatistics.ps1
    [-OUName] <string>
    [-Path] <string>

Get-ADUserStatistics.ps1
    [-All] <switch>
    [-Path] <string>
  
  Get-RemoteIPConfig.ps1: Connects to Active Directory and gathers IP configuration from remote computers.
  Get-RemoteIPConfig
    [-ComputerName] <string>
    [-Path] <string>
    [-ServersOnly] <switch>

Get-RemoteIPConfig
    [-SearchBase] <string>
    [-RootOnly] <switch>
    [-Path] <string>
    [-ServersOnly] <switch>
