<#
- PITRDatabaseRetentionPolicyList.ps1

This script will gets the short term retention policy in days registered to the database(s) on the server and save the information on a CSV file.
* Please review the contents of this file before execute the script in order to understand what the script is going to perform in your Azure environment. It's easy to understand and well commented.

#>

# Login to Azure
Connect-AzAccount | Out-Null # Hide the output of the login which normally gives a list of environments

# Get Azure SQL Database/Server resources information
$SubscriptionId = "TYPE_SUBSCRIPTION_ID"
$ResourceGroup = "TYPE_RESOURCE_GROUP_NAME"

$ServerName = "TYPE_AZURESQL_SERVER_NAME"
$CSVFilePath = "C:\Users\TYPE_YOUR_WINDOWS_USER_NAME\Desktop\PITR_Database_Retention_Policy_List.csv" # This is just a example, could be configured to any local path on your computer, the same applies to the file name

# Select Azure Subscription
Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null # Hide the output of the subscription selection which normally gives a list subscription name, Tenant ID, etc...

# Check if file already exists since the Append parameter is used to add the data to the CSV file a new one must be created
if (Test-Path $CSVFilePath) {
    Write-Host "ERROR: The file $($CSVFilePath) already exists, please remove/delete the file before running the script..." -ForegroundColor Red
    Break
} else {
    Write-Host "The following file $($CSVFilePath) will be created..." -ForegroundColor Green
}

# Gets the short term retention policy
try {

Write-Host "Starting listing the point-in-time restore (PITR) retention period for the database(s) on the server $servername, please wait..." -ForegroundColor Cyan
$AzureSQLServerDataBases = Get-AzSqlDatabase -ServerName $ServerName -ResourceGroupName $ResourceGroup | Where-Object DatabaseName -NE "master" | Get-AzSqlDatabaseBackupShortTermRetentionPolicy

Write-Host "**********************************************************************************************" -ForegroundColor Green
Write-Host "SUCCESS: The list of database(s) point-in-time restore retention period has been acquired!" -ForegroundColor Green
Write-Host "**********************************************************************************************" -ForegroundColor Green

} catch {
  Write-Host "********************************************************************************************" -ForegroundColor Red
  Write-Host "ERROR: Error while getting the point-in-time restore retention period of the database(s)!" -ForegroundColor Red
  Write-Host "********************************************************************************************" -ForegroundColor Red
  Break
}

foreach ($AzureSQLServerDataBase in $AzureSQLServerDataBases) {

    try {
    $AzureSQLServerDataBase | Export-CSV -Path $CSVFilePath -Encoding UTF8 -NoTypeInformation -Append
    Write-Host "The point-in-time restore (PITR) retention period of the database $($AzureSQLServerDataBase.DatabaseName) has been added to the CSV file, please wait..." -ForegroundColor Cyan

    } catch {
    Write-Host "ERROR: Error while adding the point-in-time restore retention period of the database $($AzureSQLServerDataBase.DatabaseName) to the CSV file!" -ForegroundColor Red
    Break
    }
}

Write-Host "*******************************************************************************************************" -ForegroundColor Green
Write-Host "SUCCESS: The point-in-time restore retention period of all database(s) has been saved to a CSV file!" -ForegroundColor Green
Write-Host "*******************************************************************************************************" -ForegroundColor Green
