function New-DbaLogShippingSecondaryDatabase {
	<#
.SYNOPSIS 
New-DbaLogShippingSecondaryDatabase sets up a secondary databases for log shipping. 

.DESCRIPTION
New-DbaLogShippingSecondaryDatabase sets up a secondary databases for log shipping.
This is executed on the secondary server.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER BufferCount
The total number of buffers used by the backup or restore operation.
The default is -1.

.PARAMETER BlockSize
The size, in bytes, that is used as the block size for the backup device.
The default is -1.

.PARAMETER DisconnectUsers
If set to 1, users are disconnected from the secondary database when a restore operation is performed.
Te default is 0.

.PARAMETER HistoryRetention
Is the length of time in minutes in which the history is retained.
The default is 14420.

.PARAMETER MaxTransferSize
The size, in bytes, of the maximum input or output request which is issued by SQL Server to the backup device. 

.PARAMETER PrimaryServer
The name of the primary instance of the Microsoft SQL Server Database Engine in the log shipping configuration.

.PARAMETER PrimaryDatabase
Is the name of the database on the primary server. 

.PARAMETER RestoreAll
If set to 1, the secondary server restores all available transaction log backups when the restore job runs. 
The default is 1.

.PARAMETER RestoreDelay
The amount of time, in minutes, that the secondary server waits before restoring a given backup file.
The default is 0.

.PARAMETER RestoreMode
The restore mode for the secondary database. The default is 0.
0 = Restore log with NORECOVERY.
1 = Restore log with STANDBY. 

.PARAMETER RestoreThreshold
The number of minutes allowed to elapse between restore operations before an alert is generated.

.PARAMETER SecondaryDatabase
Is the name of the secondary database.

.PARAMETER ThresholdAlert
Is the alert to be raised when the backup threshold is exceeded. 
The default is 14420.

.PARAMETER ThresholdAlertEnabled
Specifies whether an alert is raised when backup_threshold is exceeded. 

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.PARAMETER Force
The force parameter will ignore some errors in the parameters and assume defaults.
It will also remove the any present schedules with the same name for the specific job.

.NOTES 
Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Log shippin, secondary database
	
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/New-DbaLogShippingSecondaryDatabase

.EXAMPLE   
New-DbaLogShippingSecondaryDatabase -SqlInstance sql2 -SecondaryDatabase DB1_DR -PrimaryServer sql1 -PrimaryDatabase DB1 -RestoreDelay 0 -RestoreMode standby -DisconnectUsers -RestoreThreshold 45 -ThresholdAlertEnabled -HistoryRetention 14420 

#>

	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
	
	param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,

		[System.Management.Automation.PSCredential]
		$SqlCredential,

		[int]$BufferCount = -1,
        
		[int]$BlockSize = -1,

		[switch]$DisconnectUsers,

		[int]$HistoryRetention = 14420,

		[int]$MaxTransferSize,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$PrimaryServer,

		[System.Management.Automation.PSCredential]
		$PrimarySqlCredential,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$PrimaryDatabase,

		[int]$RestoreAll = 1,

		[int]$RestoreDelay = 0,

		[ValidateSet(0, 'NoRecovery', 1, 'Standby')]
		[object]$RestoreMode = 0,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[int]$RestoreThreshold,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$SecondaryDatabase,

		[int]$ThresholdAlert = 14420,

		[switch]$ThresholdAlertEnabled,

		[switch]$Silent,

		[switch]$Force
	)

	# Try connecting to the instance
	Write-Message -Message "Attempting to connect to $SqlInstance" -Level Verbose
	try {
		$ServerSecondary = Connect-DbaSqlServer -SqlInstance $SqlInstance -SqlCredential $SqlCredential
	}
	catch {
		Stop-Function -Message "Could not connect to Sql Server instance $SqlInstance.`n$_" -Target $SqlInstance -Continue
	}

	# Try connecting to the instance
	Write-Message -Message "Attempting to connect to $PrimaryServer" -Level Verbose
	try {
		$ServerPrimary = Connect-DbaSqlServer -SqlInstance $PrimaryServer -SqlCredential $PrimarySqlCredential
	}
	catch {
		Stop-Function -Message "Could not connect to Sql Server instance $PrimaryServer.`n$_" -Target $PrimaryServer -Continue
	}

	# Check if the database is present on the primary sql server
	if ($ServerPrimary.Databases.Name -notcontains $PrimaryDatabase) {
		Stop-Function -Message "Database $PrimaryDatabase is not available on instance $PrimaryServer" -Target $PrimaryServer -Continue
	}

	# Check if the database is present on the primary sql server
	if ($ServerSecondary.Databases.Name -notcontains $SecondaryDatabase) {
		Stop-Function -Message "Database $SecondaryDatabase is not available on instance $ServerSecondary" -Target $SqlInstance -Continue
	}

	# Check the restore mode
	if ($RestoreMode -notin 0, 1) {
		$RestoreMode = switch ($RestoreMode) { "NoRecovery" { 0}  "Standby" { 1 } }
		Write-Message -Message "Setting restore mode to $RestoreMode." -Level Verbose
	}

	# Check the if Threshold alert needs to be enabled
	if ($ThresholdAlertEnabled) {
		[int]$ThresholdAlertEnabled = 1
		Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
	}
	else {
		[int]$ThresholdAlertEnabled = 0
		Write-Message -Message "Setting Threshold alert to $ThresholdAlertEnabled." -Level Verbose
	}

	# Checking the option to disconnect users
	if ($DisconnectUsers) {
		[int]$DisconnectUsers = 1
		Write-Message -Message "Setting disconnect users to $DisconnectUsers." -Level Verbose
	}
	else {
		[int]$DisconnectUsers = 0
		Write-Message -Message "Setting disconnect users to $DisconnectUsers." -Level Verbose
	}

	# Check hte combination of the restore mode with the option to disconnect users
	if ($RestoreMode -eq 0 -and $DisconnectUsers -ne 0) {
		if ($Force) {
			[int]$DisconnectUsers = 0
			Write-Message -Message "Illegal combination of database restore mode $RestoreMode and disconnect users $DisconnectUsers. Setting it to $DisconnectUsers." -Level Warning
		}
		else {
			Stop-Function -Message "Illegal combination of database restore mode $RestoreMode and disconnect users $DisconnectUsers." -Target $SqlInstance -Continue
		}
	}

	# Set up the query
	$Query = "EXEC sp_add_log_shipping_secondary_database  
        @secondary_database = '$SecondaryDatabase'
        ,@primary_server = '$PrimaryServer'
        ,@primary_database = '$PrimaryDatabase' 
        ,@restore_delay = $RestoreDelay
        ,@restore_all = $RestoreAll
        ,@restore_mode = $RestoreMode
        ,@disconnect_users = $DisconnectUsers
        ,@restore_threshold = $RestoreThreshold
        ,@threshold_alert = $ThresholdAlert
        ,@threshold_alert_enabled = $ThresholdAlertEnabled
        ,@history_retention_period = $HistoryRetention "
    
	# Addinf extra options to the query when needed
	if ($BlockSize -ne -1) {
		$Query += ",@block_size = $BlockSize"
	}

	if ($BufferCount -ne -1) {
		$Query += ",@buffer_count = $BufferCount"
	}

	if ($MaxTransferSize -ge 1) {
		$Query += ",@max_transfer_size = $MaxTransferSize"
	}

	$Query += ",@overwrite = 1;"
    
	# Execute the query to add the log shipping primary
	if ($PSCmdlet.ShouldProcess($SqlServer, ("Configuring logshipping for secondary database $SecondaryDatabase on $SqlInstance"))) {
		try {
			Write-Message -Message "Configuring logshipping for secondary database $SecondaryDatabase on $SqlInstance." -Level Output 
			Write-Message -Message "Executing query:`n$Query" -Level Verbose
			$ServerSecondary.Query($Query)
		}
		catch {
			Stop-Function -Message "Error executing the query.`n$($_.Exception.Message)`n$Query"  -InnerErrorRecord $_ -Target $SqlInstance -Continue
		}
	}

	Write-Message -Message "Finished adding the secondary database $SecondaryDatabase to log shipping." -Level Output 

}