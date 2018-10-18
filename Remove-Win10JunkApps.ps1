<#
Remove-Win10JunkApps.ps1

This utility is designed to aid administrators of Windows 10 Professional and Enterprise
with removal of applications on the Windows 10 Start menu that are included with the operating system
or to remove the automatically installed recommended apps from the Windows Store with Professional edition.

NOTE: This runs as the user and only impacts the individual user's start menu and application list.
        If you remove Windows Camera for one user, it will still show as installed for another.
        This is not add/remove programs.

This utility has no parameters as it is intended to be used by administrators in login scripts.
All variables must derive from the running environment, or be configured in this script.

How to use:
    1. Modify the list of junk apps in this script to be specific to your environment, setting to Remove those apps you don't want.
        a. You can add more apps simply by copying the format. You may need to do this as the recommended apps that are installed do change.
    2. Copy this file to the NETLOGON share on your domain controller, or to another location on the network.
    3. Create or modify a Group Policy object which will apply to the user account.
        a. Under Login Scripts, set this script as a PowerShell Script.
        b. You may also embed this in a traditional command line login script with this line:
            powershell.exe -nologo -file %logonserver%\NetLogon\Remove-Win10JunkApps.ps1 -windowstyle hidden -noprofile -executionpolicy bypass

Author: Clark B. Lebarge
Company: Long View Systems
Version: 1.0.10182018

#>

function Remove-Win10App
{
param(
[parameter()]$AppSearchString
)

Get-AppxPackage "*$AppSearchString*" | Remove-AppxPackage

}

<#Datatable of Junk Applications
Modify this table to configure which junk apps are to be removed.
Format of the table is important.
    $JunkApps.Rows.Add('APPNAME' , 'ALLOW|REMOVE') | OUT-Null #description of what's being removed.
The application name can be found using the powershell command Get-AppXPackage.
You may abbreviate the appname to catch multiple apps such as the Xbox apps included.
    ('xbox' , 'remove')
    would result in all Xbox apps being removed.

#>

$JunkApps = New-Object System.Data.DataTable("JunkApps")
$JunkApps.Columns.Add("AppName") | Out-Null
$JunkApps.Columns.Add("Action") | Out-Null

$JunkApps.Rows.Add('windowscommunicationsapps' , 'allow' ) | Out-Null    #Windows Mail and Calendar
$JunkApps.Rows.Add('xbox'                      , 'allow' ) | Out-Null    #XBox Apps, note that one app doesn't remove, but the rest do and the start menu icon is removed.
$JunkApps.Rows.Add('windowsmaps'               , 'allow' ) | Out-Null    #Maps
$JunkApps.Rows.Add('messaging'                 , 'allow' ) | Out-Null    #Messaging
$JunkApps.Rows.Add('skypeapp'                  , 'allow' ) | Out-Null    #Skype (personal version)
$JunkApps.Rows.Add('solitaire'                 , 'allow' ) | Out-Null    #Solitaire Collection
$JunkApps.Rows.Add('zunemusic'                 , 'allow' ) | Out-Null    #Groove Music
$JunkApps.Rows.Add('zunevideo'                 , 'allow' ) | Out-Null    #Movies & TV
$JunkApps.Rows.Add('bingweather'               , 'allow' ) | Out-Null    #Weather
$JunkApps.Rows.Add('wunderlist'                , 'allow' ) | Out-Null    #Wunderlist
$JunkApps.Rows.Add('stickynotes'               , 'allow' ) | Out-Null    #Sticky Notes
$JunkApps.Rows.Add('windowsfeedbackhub'        , 'allow' ) | Out-Null    #Feedback Hub
$JunkApps.Rows.Add('wiki'                      , 'allow' ) | Out-Null    #Bing Wikipedia Browser
$JunkApps.Rows.Add('money'                     , 'allow' ) | Out-Null    #Money
$JunkApps.Rows.Add('dolby'                     , 'allow' ) | Out-Null    #Dolby Access
$JunkApps.Rows.Add('windowsalarms'             , 'allow' ) | Out-Null    #Alarms & Clock
$JunkApps.Rows.Add('windowsstore'              , 'allow' ) | Out-Null    #Store, unsure if this actually disables Store or just removes the interface for this user, likely the latter.
$JunkApps.Rows.Add('3dviewer'                  , 'allow' ) | Out-Null    #Mixed Reality Viewer
$JunkApps.Rows.Add('people'                    , 'allow' ) | Out-Null    #People
$JunkApps.Rows.Add('windowscamera'             , 'allow' ) | Out-Null    #Camera, just the app, no impact to hardware.
$JunkApps.Rows.Add('gethelp'                   , 'allow' ) | Out-Null    #Get Help
$JunkApps.Rows.Add('networkspeed'              , 'allow' ) | Out-Null    #Network Speed Test
$JunkApps.Rows.Add('onenote'                   , 'allow' ) | Out-Null    #OneNote, this is the version included with Windows, not the version in Office.
$JunkApps.Rows.Add('mspaint'                   , 'allow' ) | Out-Null    #Paint 3D
$JunkApps.Rows.Add('windows.photos'            , 'allow' ) | Out-Null    #Photo Viewer
$JunkApps.Rows.Add('photoshop'                 , 'allow' ) | Out-Null    #Adobe Photoshop Express
$JunkApps.Rows.Add('print3d'                   , 'allow' ) | Out-Null    #Print 3D
$JunkApps.Rows.Add('getstarted'                , 'allow' ) | Out-Null    #Tips
$JunkApps.Rows.Add('windowsSoundRecorder'      , 'allow' ) | Out-Null    #Voice Recorder

foreach($app in $JunkApps)
{
IF($app.Action -eq 'remove')
    {
    $AppName = $App.AppName
    Remove-Win10App -AppSearchString $AppName
    }
}