<#
.SYNOPSIS       GUI to connect to remote SQL servers and perform a backup of a selected database
.DESCRIPTION    This script will launch a user friendly GUI that allows remote connect to a SQL server, retrieves all databases, and allows for backup to a remote network location
                Process of the script:

                    1) Check for Windows AD credentials from the user
                    2) Launch primary GUI
                    3) Provide GUI with a list of SQL servers
                    4) Provide GUI with a list of databases belonging to the SQL server
                    5) Provide GUI with a list of backup servers to use
                    6) Upon pressing "submit" - Script will log onto remote server and action the backup 

.NOTES          1) User configurable variables are listed under "Configurable Variables" in this script. This includes:
                    a) $sql_server_list - A list containing the SQL server shortnames, and hostnames/IP's
                    b) $backup_server_list - A list containing the backup server shortnames, and hostnames/IP's
                    c) $local_backupPath - The local directory path where the SQL backups are stored on the backup server, and temporarily on the SQL server

            DISCLAIMER:
            This script is provided "as is" for educational and internal IT automation purposes.
            Use with caution in production environments—no warranty is provided.
            Ensure proper permissions, backup path access, and SQL server configurations before use.
#>

#Configurable Variables:
$sql_server_list = @{                                                               #A list containing SQL servers. Please add a new line for each new server 
    "SQL Host #1" = "sqldb1"                                                        #Format: "Shortname" = "ipaddress"
}

$backup_server_list = @{                                                            #A list containing backup servers. Please add a new line for each new server
    "Backup Server #1" = "\\backup01\c$\backups"                                    #Format: "Shortname" = "UNC Path"
}

$local_backupPath = "C:\backups"                                                    #Local path to backup folder on backup server and sql server

#Script body:

#WPF XML data - Logo can be changed on line 40 in <Image Source="" tag
[xml] $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        Title="SQL Backup" Height="600" Width="600">
    <Grid>
        <Image Source="https://upload.wikimedia.org/wikipedia/commons/thumb/9/94/M_box.svg/220px-M_box.svg.png" HorizontalAlignment="Left" Height="100" Margin="10,10,0,0" VerticalAlignment="Top" Width="100"/>
        <Label Content="SQL Backup Tool" Margin="10,50,10,0" VerticalAlignment="Top" Width="574" HorizontalAlignment="Left" HorizontalContentAlignment="Center" BorderThickness="0" Cursor="None" FontSize="16" FontFamily="Segoe UI Semibold"/>
        <Label Content="Please select your system:" HorizontalAlignment="Left" Margin="40,170,0,0" VerticalAlignment="Top" Height="30" Width="225" FontSize="14"/>
        <Label Content="Please select your database:" HorizontalAlignment="Left" Margin="40,220,0,0" VerticalAlignment="Top" Height="30" Width="225" FontSize="14"/>
        <ComboBox x:Name="db_combobox" HorizontalAlignment="Left" Margin="280,170,0,0" VerticalAlignment="Top" Width="289" Height="30" VerticalContentAlignment="Center" BorderBrush="#FF00A1F1"/>
        <ListBox x:Name="db_listbox" HorizontalAlignment="Left" Height="150" Margin="280,220,0,0" VerticalAlignment="Top" Width="290" BorderBrush="#FF00A1F1" SelectionMode="Extended"/>
        <Label Content="Please select backup destination:" HorizontalAlignment="Left" Margin="40,400,0,0" VerticalAlignment="Top" Height="30" Width="225" FontSize="14"/>
        <ComboBox x:Name="backup_combobox" HorizontalAlignment="Left" Margin="280,400,0,0" VerticalAlignment="Top" Width="289" Height="30" VerticalContentAlignment="Center" BorderBrush="#FF00A1F1"/>
        <Label Content="Alternative backup path:" HorizontalAlignment="Left" Margin="40,450,0,0" VerticalAlignment="Top" Height="30" Width="225" FontSize="14"/>
        <TextBox x:Name="alt_backup" HorizontalAlignment="Left" Height="30" Margin="280,450,0,0" TextWrapping="NoWrap" Text="" VerticalAlignment="Top" Width="289" VerticalContentAlignment="Center" BorderBrush="#FF00A1F1"/>
        <Label Content="Status: " HorizontalAlignment="Left" Margin="40,530,0,0" VerticalAlignment="Top" Height="30" Width="70" FontSize="14"/>
        <Label x:Name="status" Content="" HorizontalAlignment="Left" Margin="110,530,0,0" VerticalAlignment="Top" Height="30" Width="320" FontSize="14"/>
        <Button x:Name="button" Content="Backup" HorizontalAlignment="Left" Margin="480,525,0,0" VerticalAlignment="Top" Width="80" Height="30" BorderBrush="#FF00A1F1"/>
    </Grid>
</Window>
"@

Add-Type -AssemblyName PresentationFramework                                            #Add WPF assemblies
$Global:syncHash = [hashtable]::Synchronized(@{})                                       #Create hashtable to store all WPF components
$reader = (New-Object System.Xml.XmlNodeReader $xaml)                                   #Create new object for XAML reader
    $syncHash.Window = [Windows.Markup.XamlReader]::Load($reader)                       #Local XPF Window 
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | % {
        $syncHash.Add($_.Name,$syncHash.Window.FindName($_.Name) )
    }

$global:datasets = @()                                                                  #New array to keep DB information

function get-dataset {                                                                  #Function to retrieve databases from SQL server
    param($server)
    try{
        $result = Invoke-Command -ComputerName $server -Credential $Global:creds -ErrorAction Stop -ScriptBlock{
            import-module sqlps -DisableNameChecking                                    #Import SQLPS module
            $getInstances = Get-ChildItem SQLSERVER:\\SQL\$env:COMPUTERNAME | select -ExpandProperty displayname #Get a list of instances
            if ($getInstances.count -ne 1){                                             #If the number of SQL instances is not 1
                return "No single instance found"
                break;                                                                  #Stop the function and return an error
            }
            else{                                                                       #If there is 1 SQL instance
                $dbs = Get-ChildItem SQLSERVER:\SQL\$env:COMPUTERNAME\$getInstances\databases | select -ExpandProperty Name #Get the name of the SQL instance, and get DBs
                return $dbs                                                             #Return database object from the SQL server
            }
        }
        $global:datasets += $result                                                     #Add all databases to the global variable for Datasets
        $global:serverInstance = $getInstances                                          #Get the name of the SQL instance
        $global:datasets = $global:datasets | sort -unique                              #Remove any duplicates that might occur
        $result = $null                                                                 #Set the invooke-command result item to $null for next run
    }
    catch{
        write-host "Couldn't get list of databases from $server" -f Red
        $syncHash.status.Content = "ERROR: Failed to connect to $server"
    }
}

$Global:creds = Get-Credential                                                          #Request credentials from user, before running the GUI
$syncHash.button.IsEnabled = $false                                                     #Disable the button on GUI on start
$index = 0                                                                              #Set index to 0 for tracking SQL servers
$sql_list = @()                                                                         #Create an empty array for keeping a list of SQL servers
$sql_server_list.Keys | foreach {                                                       #Create an object that includes: a shortname and hostname for each SQL server
    $obj = New-Object psobject
    $obj | Add-Member NoteProperty "shortname" -Value $_
    $obj | Add-Member NoteProperty "hostname" -Value ($sql_server_list.Values | select -Index $index)
    $index++
    $sql_list += $obj
}

$index = 0                                                                              #Set index to 0 for tracking backup servers (same as above)
$backup_list = @()                                                                      #Create an empty array for keeping list of backup servers
$backup_server_list.Keys | foreach {                                                    #Create an object that includes: a shortname and hostname for each backup server
    $obj = New-Object psobject
    $obj | Add-Member NoteProperty "shortname" -Value $_
    $obj | Add-Member NoteProperty "hostname" -Value ($backup_server_list.Values | select -Index $index)
    $index++
    $backup_list += $obj
}

$sql_list | foreach {                                                                   #Go though each SQL server in the list, and:
    $syncHash.db_combobox.Items.Add($_.shortname) | Out-Null                            #Add the sql server shortname to the GUI's DB combobox
}

$syncHash.db_combobox.Add_SelectionChanged({                                            #If the DB combobox selection has been changed, add an event to:
    $error.Clear()                                                                      #Clear any existing errors
        $connectTo = ($sql_list | where {$_.shortname -eq $syncHash.db_combobox.SelectedItem}).hostname     #Retrieve the hostname of the selected SQL server
        get-dataset -server $connectTo                                                  #Call the get-dataset function to retrieve list of DB's
        $syncHash.db_listbox.items.Clear()                                              #Clear the DB listbox (to ensure fresh results on each selection of DB combobox)
        if (!($error)){                                                                 #If there is no error, then:
            if ($syncHash.db_combobox.SelectedItem){                                    #If there is a selected SQL server
                write-host "Retrieving databases from $connectTo" -f Green              #Update status on the GUI
                $syncHash.status.Content = "Connected to $connectTo"
                $global:datasets | foreach {
                    $syncHash.db_listbox.Items.Add($_) | Out-Null                       #Add each SQL database to the DB listbox
            }
        }
    }
})

$backup_list | foreach {
    $syncHash.backup_combobox.Items.Add($_.shortname) | Out-Null                        #Add all backup servers (shortname) to the backup combobox
}

$syncHash.alt_backup.Add_SelectionChanged({                                             #If the user has selected the alternative backup path, then:
    if ($syncHash.alt_backup.Text.Length -gt 2){                                        #Check if the user has entered a path containing more than 2 chars
        $syncHash.backup_combobox.IsEnabled = $false                                    #Disable the backup combobox
        $syncHash.button.IsEnabled = $true                                              #Enable the GUI button
    }
    else{                                                                               #If the user has selected the alternative backup, but not added anything,
        $syncHash.backup_combobox.IsEnabled = $true                                     #Enable the backup combobox
        $syncHash.button.IsEnabled = $false                                             #Disable the button
    }
})

$syncHash.backup_combobox.Add_SelectionChanged({                                        #Check if the user has changed the value of the backup combobox
    $syncHash.button.IsEnabled = $true
})

$syncHash.button.Add_Click({                                                            #When the button is clicked:
    if ($syncHash.backup_combobox.SelectedItem){                                        #Get the backup server hostname from the shortname selected and form the UNC path
        $use_backupServer = $backup_list | where {$_.shortname -eq $syncHash.backup_combobox.SelectedItem} | select -ExpandProperty hostname
    }
    if ($syncHash.alt_backup.Text.Length -gt 2){                                        #If the alternative backup path is selected, get the backup path from the text box
        $use_backupServer = $syncHash.alt_backup.Text
    }

    $syncHash.status.Content = "Backing up selected databases..."
    write-host "Backing up selected databases" -f Green
    $server = $sql_list | where {$_.shortname -eq $syncHash.db_combobox.SelectedItem} | select -ExpandProperty hostname     #Get the SQL server hostname from the shortname selected
    $dbsToBackup = $syncHash.db_listbox.SelectedItems                                   #Create a variable to store names of all DB's selected that are to be backed up
    
    #Invoke a remote connection to the SQL server, pass the database names, backup server, and local backup folder paths as arguments
    $result = Invoke-Command -ComputerName $server -Credential $Global:creds -Authentication Credssp -ArgumentList $dbsToBackup,$use_backupServer,$local_backupPath -ScriptBlock {
        import-module sqlps -DisableNameChecking                                        #Import the SQLPS module
        $getInstances = Get-ChildItem SQLSERVER:\\SQL\$env:COMPUTERNAME | select -ExpandProperty displayname    #Get the instance of the SQL server
            try{
            $backupR = $args[1]                                                         #Set argument to remote backup variable
            $backupL = $args[2]                                                         #Set argument to local backup variable
            $args[0] | foreach {                                                        #Loop through each database name, and:
                $fileName = $_ + "_" + (get-date -f hhmm) + "_" + (get-date -f dd-MM-yy) + "_" + "SQLBackup"     #Set the filename
                $filePath = $backupL + "\" + $fileName + ".bak"                                             #Set the file path
                Backup-SqlDatabase -ServerInstance $env:COMPUTERNAME\$getInstances -Database $_ -BackupFile $filePath  #Execute the SQL backup command        
                Move-Item -Path $filePath -Destination $backupR                                  #Move the sql backup to the backup server
                }
            }
            catch{
                    return "TError"
                }
    }
    if ($result -match "PathError"){                                                    #If the return value is "PathError", this indicates backup path is invalid
        $syncHash.status.Content = "ERROR: Couldn't access the backup path"
        write-host "Cannot access backup path" -f Red
    }
    elseif ($result -match "TError"){                                                   #If the return value is "TError", this indicates backup cannot be processed
        $syncHash.status.content = "ERROR: Couldn't perform backup transaction"
        write-host "Cannot perform backup" -f Red
    }
    else{
        $syncHash.status.Content = "Done"
    }
})

$syncHash.Window.ShowDialog() | Out-Null                                                #Launch the main GUI

$syncHash.Window.Add_Closing({$_.Cancel = $true})                                       #Close window
exit
