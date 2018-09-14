<#
Report on User Account Usage.

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
    
#>

param(
[parameter(ParameterSetName="All",Mandatory=$true,HelpMessage="Gather all users in the domain.")][switch]$All,
[parameter(ParameterSetName="ByUser",Mandatory=$true,HelpMessage="The user account to check.")][string]$UserName,
[parameter(ParameterSetName="ByGroup",Mandatory=$true,HelpMessage="The Group containing the users to check.")][string]$GroupName,
[parameter(ParameterSetName="ByOU",Mandatory=$true,HelpMessage="The Distinguished Name for the OU containing the users to check.")][string]$OUName,
[parameter(ParameterSetName="ByUser",Mandatory=$true,HelpMessage="The output filename and path.")]
[parameter(ParameterSetName="ByGroup",Mandatory=$true,HelpMessage="The output filename and path.")]
[parameter(ParameterSetName="ByOU",Mandatory=$true,HelpMessage="The output filename and path.")]
[parameter(ParameterSetName="All",Mandatory=$true,HelpMessage="The output filename and path.")]
[string]$Path
)

#Create the Filter for the query.

IF($UserName)
{
$Users = @{}
$Users.Add("SamAccountName",$UserName)
}

IF($GroupName)
{
$Users = Get-ADGroupMember -Identity $GroupName
}

IF($OUName)
{
$Users = Get-ADUser -Filter * -SearchBase $OUName
}

IF($All)
{
$Users = Get-ADUser -Filter *
}

#The Query

foreach($user in $users)
{
$samAccountName = $User.samAccountName
$BasicAttributes = Get-ADUser -Filter "samAccountName -like '*$samAccountName*'" -Properties * | Select-Object AccountExpires,@{N='BadPasswordTime'; E={[DateTime]::FromFileTime($_.BadPasswordTime)}},Company,Description,DisplayName,DistinguishedName, `
LastLogonDate,LogonCount,EMailAddress,SamAccountName,UserPrincipalName,Name,PasswordLastSet,Created,Modified,Enabled,PasswordNeverExpires, `
@{N='AccountExpirationDate'; E={[DateTime]::FromFileTime($_.AccountExpirationDate)}},Country,HomeDrive,Manager,OfficePhone,PasswordExpired,PasswordNotRequired,Title,CannotChangePassword

$OU = $BasicAttributes.DistinguishedName -replace '^.+?(?<!\\),',''

[string]$LogonWorkstations = Get-ADUser -Filter "samAccountName -like '*$samAccountName*'" -Properties * | Select-Object -ExpandProperty LogonWorkstations

    #expanding out the groups, only wanting to get group name.
    $Groups = Get-ADUser -Filter "samAccountName -like '*$samAccountName*'" -Properties * | Select-Object -ExpandProperty Memberof
    $MemberOf = New-Object 'System.Collections.Generic.List[system.object]'
    foreach($group in $groups)
    {
    $Name = (Get-ADGroup $group | select Name).Name

    $MemberOf.add($Name)
    }

    $MemberOf = $MemberOf -join ","


    New-Object -TypeName PSObject -Property @{
        AccountExpires = $BasicAttributes.AccountExpires
        BadPasswordTime = $BasicAttributes.BadPasswordTime
        Company = $BasicAttributes.Company
        Description = $BasicAttributes.Description
        DisplayName = $BasicAttributes.DisplayName
        OrganizationUnit = $OU
        LastLogonDate = $BasicAttributes.LastLogonDate
        LogonCount = $BasicAttributes.LogonCount
        EmailAddress = $BasicAttributes.EmailAddress
        SamAccountName = $BasicAttributes.SamAccountName
        UserPrincipalName = $BasicAttributes.UserPrincipalName
        Name = $BasicAttributes.Name
        PasswordLastSet = $BasicAttributes.PasswordLastSet
        Created = $BasicAttributes.Created
        Modified = $BasicAttributes.Modified
        Enabled = $BasicAttributes.Enabled
        PasswordNeverExpires = $BasicAttributes.PasswordNeverExpires
        AccountExpirationDate = $BasicAttributes.AccountExpirationDate
        Country = $BasicAttributes.Country
        HomeDrive = $BasicAttributes.HomeDrive
        Manager = $BasicAttributes.Manager
        OfficePhone = $BasicAttributes.OfficePhone
        PasswordExpired = $BasicAttributes.PasswordExpired
        PasswordNotRequired = $BasicAttributes.PasswordNotRequired
        Title = $BasicAttributes.Title
        CannotChangePassword = $BasicAttributes.CannotChangePassword
        LogonWorkstations = $LogonWorkstations
        MemberOf = $MemberOf
        } | Export-Csv -NoTypeInformation -Append -Path $Path
}