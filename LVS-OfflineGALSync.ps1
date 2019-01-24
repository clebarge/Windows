<#

Powershell Script to synchronize mail enabled users from one Active Directory domain as contacts in one or many other domains.
This is done so that the Global Address List in Exchange for one organization includes that addresses in the foreign domain.
This should only be necessary in disjointed AD environments that result from mergers and acquisitions where it is not possible
to migrate and compress the environment to a single Exchange organization.

This script operates using offline connectivity where each source/target domain must run this script as a task and all sources/targets must have
access to a central file storage location.

As this script will be run as a task in each domain, all credential actions assume to be in the context of the task's configured service account.

In some ways this makes configuration easier as the configuration section only needs to know information about the local domain.

----REQUIREMENTS----
Active Directory
    - A domain user service account
        a) The script will run in the context of the service user account specified in the Task Scheduler.
        b) The service user account will require rights/permissions to run the task on the Windows server.
            - logon as a batch job
        c) This will be a service account, so password should not expire.
    - This user account requires the following delegated rights for Contacts.
        a) Modify for Contact objects.
    
Microsoft Exchange
    - Exchange version 2010 or greater supported
    - The domain user service account is added to the Recipient Management Role Group.
    - The domain user service account must be granted permission for remote powershell.
        a) In each Exchange Organization
            SET-USER -identity $domainuserserviceaccount -RemotePowerShellEnabled $True
    - Windows Authentication enabled on the Powershell virtual directory in IIS on all CAS (2010) or Mailbox (2013+) servers.
        a) This assumes that all mail/CAS servers are used, if you specify a URL that only resolves to one server, then you'd only need to modify that server's configuration. 

Server
    - Windows Server 2012R2 (NOTE: Recommended Windows Server 2016)
    - RSAT tools for Active Directory installed (if not a DC)
    - PowerShell v5.1 (will need to be installed on 2012R2, should be installed automatically on 2016)
    - PowerShell execution Policy: RemoteSigned (default for Server OS)
    - Logon as a Batch Job granted to the domain user service account. (NOTE: This should occur automatically when you use the Task Scheduler to configure the batch)
    - A folder for saving this script, and log output.
    - The POSH-SSH module is required for SFTP connectivity.
        From an elevated PS: Import-Module -Name POSH-SSH


----Aboot----
Author: Clark B. Lebarge
Company: Long View Systems
Web: https://www.longviewsystems.com
Email: clark.lebarge@lvs1.com
Version: 1.1.01242019

#>

#For testing.
param([parameter(Mandatory=$false,HelpMessage="Set testmode where commands use the -WhatIf switch to test but not create or modify.")][switch]$testMode)


<#
------------CONFIGURATION------------
Modify on each source/target domain.
=====================================
#>
    #--Destination Service Selection--
    #Modify this line to set the service/location to export, currently only SFTP and FILE is supported.
    #NOTE: You'll need to load a module if the destination isn't a file share or other built in capability with PowerShell. SFTP for example requires loading POSH-SSH module.
    $DestinationService = "SFTP"

        #SFTP: Modify this section for configuring the SFTP server settings, username, and password.
        $sftpServerHostName = ""
        $sftpDestinationDir = ""
        $sftpUsername = ""
        $sftpPassword = ""     #Sorry for the plain text!

        #FILE: Modify this section for configuring the UNC path for export and import.
        #Note: This section assumes that pass-through windows authentication will work and that the account running this script has access rights to the location.
        $fileUNCPath = "\\Server\Share"

    #--Export Variables-- These are used during export.
        #This object array allows you to specify only certain OUs to export. Note that you must enclose in quotes each line, one line per OU.
        $exportSelectOUs = @(
            "OU=Good,OU=People,DC=domain,DC=com"
            "OU=Bad,OU=People,DC=domain,DC=com"
            "OU=Ugly,OU=People,DC=domain,DC=com"
            )

    
        #This filter further restricts the users selected within the OUs specified. It likely does not need modification.
        # ObjectClass should always be user, we're making contacts from users.
        # mailNickName is filtered for users that have any value, which indicates the user has a mailbox in either Exchange or Exchange Online.
        #If we hide an address from our local list, we should honor that in our export. This is a negative check on True. That way there is no ambiguity for null values.
        #Can also modify the line to include: -and not userAccountControl -bor 2
        #Which will instruct the script to ignore disabled users. As room, equipment, and shared mailboxes are disabled accounts by default this should not be included.
        $exportFilter = 'ObjectClass -eq "user" -and mailNickName -like "*" -and -not msExchHideFromAddressLists -eq $true'

        #Export Attributes, to reduce the size of the exported file, only export the attributes we'll want to send and have imported.
        #You may wish to review which attributes you export and import.
        $exportAttributes = 'description','displayName','company','givenName','mobile','postalAddress','postalCode','sn','st','streetAddress','telephoneNumber','title' ,'mail','c','co','l','facsimileTelephoneNumber','physicalDeliveryOfficeName'


    #--Import Variables-- These are used during import.
        #We need to know the internal Exchange Server PowerShell URI
        $importExchangeURI = "http://exchange.domain.com/powershell"

        #Import Domains Table.
        $importDomains = 
            @(
                [pscustomobject]@{
                Domain="domain2.com"
                OUPath="OU=domain2.com,OU=contacts,DC=domain,DC=com"
                },
                [pscustomobject]@{
                Domain="domain3.com"
                OUPath="OU=domain3.com,OU=contacts,DC=domain,DC=com"
                }
            )

        #These attributes will be imported, or attempted to be imported.
        #You may wish to review which attributes you export and import.
        $importAttributes = 'description','displayName','company','givenName','mobile','postalAddress','postalCode','sn','st','streetAddress','telephoneNumber','title' ,'mail','c','co','l','facsimileTelephoneNumber','physicalDeliveryOfficeName'

<#
------------Script Body------------
This section should require no modification for configuration.
===================================================================================
#>

#Logging, basic transcript.
    #Current Path
    $CurrentPath=Split-Path $script:MyInvocation.MyCommand.Path
    Start-Transcript $CurrentPath\GALsync.log

#Export users to a local CSV file.
    $ExportFilePath = "$env:TEMP\$env:USERDNSDOMAIN.csv"
    $sourceDomain = $env:USERDNSDOMAIN
	$objSourceDC = try{Get-ADDomainController -Discover -DomainName $sourceDomain -ErrorAction Stop}catch{write-host "Could not connect with a DC in your domain. Aborting export.";return}

	$sourceDC = [string]$objSourceDC.HostName

	write-host "Enumerating" $sourceDomain "objects using DC" $sourceDC

	### ENUMERATE USERS in the source domain.
    #For exporting only select OUs, we need to run through each OU, and combine the values into one table. We'll use a Datatable.
    $colUsers = $null
    $colUsers = New-Object System.Data.DataTable("colUsers")
    $Columns = $exportAttributes.Split(",")
    foreach($column in $Columns){
        $colUsers.Columns.Add($column) | Out-Null
        }
    foreach($OU in $exportSelectOUs){
        $OUcolUsers = try{Get-ADObject -Filter $exportFilter -Properties $exportAttributes -Server $sourceDC -SearchBase $OU | Select-Object $exportAttributes}catch{write-host "An error occured while reading AD. Aborting.";return}
            foreach($user in $OUcolUsers){
                $row = $colUsers.NewRow()
                $row['description'] = $user.description
                $row['displayName'] = $user.displayName
                $row['company'] = $user.company
                $row['givenName'] = $user.givenName
                $row['mobile'] = $user.mobile
                $row['postalAddress'] = $user.postalAddress
                $row['postalCode'] = $user.postalCode
                $row['sn'] = $user.sn
                $row['st'] = $user.st
                $row['streetAddress'] = $user.streetAddress
                $row['telephoneNumber'] = $user.telephoneNumber
                $row['title'] = $user.title
                $row['mail'] = $user.mail
                $row['c'] = $user.c
                $row['co'] = $user.co
                $row['l'] = $user.l
                $row['facsimileTelephoneNumber'] = $user.facsimileTelephoneNumber
                $row['physicalDeliveryOfficeName'] = $user.physicalDeliveryOfficeName
                $colusers.rows.Add($row) | Out-Null
                }
        }
	
    if ($colUsers.Count -eq 0)
    {
        write-host "No users found in source domain!"
        return
    }
    $colUsers | Export-Csv -NoTypeInformation -Path $ExportFilePath -Force

#Upload the export to the service selected.
    #SFTP
    IF($DestinationService -eq "SFTP"){
        $Password = ConvertTo-SecureString $sftpPassword -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential ($sftpUsername, $Password)

        # Establish the SFTP connection
        $sftpSession = try{New-SFTPSession -ComputerName $sftpServerHostName -Credential $Credential}catch{write-host "Could not connect to SFTP server. Aborting.";return}

        # Upload the file to the SFTP path
        try{Set-SFTPFile -SessionId ($sftpSession).SessionId -LocalFile $ExportFilePath -RemotePath $sftpDestinationDir -Overwrite}catch{write-host "Could not upload file to SFTP.";continue}

        }
    #FILE
    IF($DestinationService -eq "FILE"){
        #Copy the file to the UNC path.
        Copy-Item -Path $ExportFilePath -Destination $fileUNCPath -Force 
        }

#Before importing, we'll wait two minutes to ensure the other domains have uploaded. Then we'll do an import action.
#In test mode the delay is shortened to five seconds.
IF($testMode -eq $true){Start-Sleep 5}ELSE{Start-Sleep 120}

#Import Actions
#Need to run for each source domain.
    foreach($sourceDomain in $importDomains){
        $DomainName = $sourceDomain.Domain
        $OUPath = $sourceDomain.OUPath
        #Download the file from the selected service.
        IF($DestinationService -eq "SFTP"){
            # download the file to the local temp path.
            try{Get-SFTPFile -SessionId ($sftpSession).SessionId -LocalPath $env:TEMP -RemoteFile "$sftpDestinationDir/$DomainName.csv" -Overwrite -NoProgress}catch{write-host "Could not download $sourceDomain CSV. Skipping.";continue}
            $colUsers = try{import-csv -Path "$env:TEMP\$DomainName.csv"}catch{write-host "An error occurred while importing the CSV file. Skipping." ; continue}
            }
        IF($DestinationService -eq "FILE"){
            $sourceFile = "$fileUNCPath\$DomainName.csv"
            Copy-Item -Path $sourceFile -Destination $env:TEMP -Force
            }

        $colContacts = @()
        $colAddContact = @()
        $colDelContact = @()
        $colUpdContact = @()
        $arrUserMail = @()
        $arrContactMail = @()

        $objTargetDC = try{Get-ADDomainController -Discover -DomainName $env:USERDNSDOMAIN -ErrorAction Stop}catch{write-host "A problem occured while searching for a domain controller. Aborting.";return}
        $targetDC = [string]$objTargetDC.HostName

        foreach ($user in $colUsers)
        {
            $arrUserMail += $user.mail
        }
        $colContacts = try{Get-ADObject -Filter 'objectClass -eq "contact"' -Server $targetDC -SearchBase $OUPath -Properties targetAddress -ErrorAction Stop}catch{write-host "Error reading contacts from AD. Aborting." ;return}
        
        foreach ($contact in $colContacts)
        {
            $strAddress = $contact.targetAddress -replace "SMTP:",""
            $arrContactMail += $strAddress
        }

        
        ### FIND CONTACTS TO ADD AND UPDATE

        foreach ($user in $colUsers)
        {
            if ($arrContactMail -contains $user.mail)
            {
                write-host "Contact found for " $user.mail
                $colUpdContact += $user
            }
            else
            {
                write-host "No contact found for " $user.mail
                $colAddContact += $user
            }
        }

        ### FIND CONTACTS TO DELETE

        foreach ($address in $arrContactMail)
        {
            if ($arrUserMail -notcontains $address)
            {
                $colDelContact += $address
                write-host "Contact will be deleted for" $address
            }
        }

        write-host ""
        write-host "Updating" $targetDomain "using DC" $targetDC

        ### ADDS

        foreach ($user in $colAddContact)
        {
            write-host "ADDING contact for " $user.mail

            $targetAddress = "SMTP:" + $user.mail
            $alias = "c-" + $user.mail.split("@")[0]

            $hashAttribs = @{'targetAddress' = $targetAddress}
                $hashAttribs.add("mailNickname", $alias)

            foreach ($attrib in $importAttributes)
            {
                if ($null -ne $user.attrib -and $user.$attrib.length -ge "1") { $hashAttribs.add($attrib, $user.$attrib) }
            }

            # Create Contact Object
            IF($testMode){
                try{New-ADObject -name $user.displayName -type contact -Path $OUPath -Description $user.description -server $targetDC -OtherAttributes $hashAttribs -WhatIf}catch{write-host "A problem may have occurred while creating contact for $user.displayname.";continue}    
                }
            ELSE{
                try{New-ADObject -name $user.displayName -type contact -Path $OUPath -Description $user.description -server $targetDC -OtherAttributes $hashAttribs}catch{write-host "A problem occurred while creating contact for $user.displayname. Skipping.";continue}
                }
        # Exchange - Run update-recipient to ensure contact is Exchange-enabled. Skipped if running in test mode.
        IF(!$testMode){
        $SO = New-PSSessionOption -SkipCACheck -SkipCNCheck –SkipRevocationCheck –ProxyAccessType None
        if ($null -eq $PSSession) {$PSSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $importExchangeURI -SessionOption $SO}
        try{Invoke-Command -Session $PSSession -ScriptBlock{param ($alias,$targetDC) Update-Recipient -Identity $alias -DomainController $targetDC} -ArgumentList $alias,$targetDC}catch{write-host "An error occured while updating the recipient for $user.displayname.";continue}
        }

        }

        ### UPDATES

        foreach ($user in $colUpdContact)
        {
            write-host "VERIFYING contact for " $user.mail

            $targetAddress = "SMTP:" + $user.mail
            $alias = "c-" + $user.mail.split("@")[0]

            $strFilter = "targetAddress -eq ""SMTP:" + $user.mail + """"
            
            $colContacts = try{Get-ADObject -Filter $strFilter -searchbase $OUPath -server $targetDC -Properties *}catch{write-host "An error occured reading contacts from AD. Aborting.";return}
            
            foreach ($contact in $colContacts)
            {
                $hashAttribs = @{}
                foreach ($attrib in $importAttributes)
                {
                    if ($null -ne $user.attrib -and $user.$attrib.length -ge "1" -and $user.$attrib -ne $contact.$attrib)
                    {
                        write-host "	Changing " $attrib
                        write-host "		Before: " $contact.$attrib
                        write-host "		After: " $user.$attrib
                        $hashAttribs.add($attrib, $user.$attrib)
                    }
                }
                if ($hashAttribs.Count -gt 0)
                {
                    IF($testMode){
                    Set-ADObject -identity $contact -server $targetDC -Replace $hashAttribs -WhatIf
                    }
                    ELSE{
                    Set-ADObject -identity $contact -server $targetDC -Replace $hashAttribs
                    }
                }
            }

        }

        ### DELETES

        foreach ($contact in $colDelContact)
        {
            write-host "DELETING contact for " $contact
            $strFilter = "targetAddress -eq ""SMTP:" + $contact + """"
            IF($testMode){
            Get-ADObject -Filter $strFilter -searchbase $OUPath -server $targetDC  | Remove-ADObject -server $targetDC -Confirm:$false -WhatIf
            }
            ELSE{
            Get-ADObject -Filter $strFilter -searchbase $OUPath -server $targetDC  | Remove-ADObject -server $targetDC -Confirm:$false
            }
        }
    }  
        
#Disconnect all SFTP Sessions
try{Get-SFTPSession | ForEach-Object { Remove-SFTPSession -SessionId ($_.SessionId) }}catch{}
Stop-Transcript