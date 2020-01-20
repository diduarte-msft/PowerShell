<#

- DataSyncMetadataCleanup.ps1

This script will install the required PowerShell modules, create a database copy, clean all Data Sync metadata objects from the copy, export the database from the copy as a .bacpac file to a storage account and then it will remove the database copy previously created.
* Please review the contents of this file before execute the script in order to understand what the script is going to perform in your Azure environment. It's easy to understand and well commented.

The script will perform the following steps:

1) Install the Azure PowerShell module version 3.3.0 and SQL Server PowerShell module version 21.1.18218

SqlServer - Invoke-Sqlcmd command
https://www.powershellgallery.com/packages/Sqlserver/

Microsoft Azure PowerShell Az commands
https://www.powershellgallery.com/packages/Az/

2) Create an Azure SQL Database copy.
3) Remove the Data Sync metadata objects from the copy. 
4) Export the database from the copy.
5) Delete the database copy.

#>

# 1) Install required PowerShell modules
Function Install-ModuleIfNotInstalled(
    [string] [Parameter(Mandatory = $true)] $moduleName,
    [string] $minimalVersion
) {
    $module = Get-Module -Name $moduleName -ListAvailable |`
        Where-Object { $null -eq $minimalVersion -or $minimalVersion -ge $_.Version } |`
        Select-Object -Last 1
    if ($null -ne $module) {
         Write-Verbose ('Module {0} (v{1}) is available.' -f $moduleName, $module.Version)
    }
    else {
        Import-Module -Name 'PowershellGet'
        $installedModule = Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue
        if ($null -ne $installedModule) {
            Write-Verbose ('Module [{0}] (v {1}) is installed.' -f $moduleName, $installedModule.Version)
        }
        if ($null -eq $installedModule -or ($null -ne $minimalVersion -and $installedModule.Version -lt $minimalVersion)) {
            Write-Verbose ('Module {0} min.vers {1}: not installed; check if nuget v2.8.5.201 or later is installed.' -f $moduleName, $minimalVersion)
            #First check if package provider NuGet is installed. Incase an older version is installed the required version is installed explicitly
            if ((Get-PackageProvider -Name NuGet -Force).Version -lt '2.8.5.201') {
                Write-Warning ('Module {0} min.vers {1}: Install nuget!' -f $moduleName, $minimalVersion)
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force
            }        
            $optionalArgs = New-Object -TypeName Hashtable
            if ($null -ne $minimalVersion) {
                $optionalArgs['RequiredVersion'] = $minimalVersion
            }  
            Write-Warning ('Install module {0} (version [{1}]) within scope of the current user.' -f $moduleName, $minimalVersion)
            Install-Module -Name $moduleName @optionalArgs -Scope CurrentUser -AllowClobber -Force -Verbose
        } 
    }
}

Install-ModuleIfNotInstalled 'SqlServer' '21.1.18218'
Install-ModuleIfNotInstalled 'Az' '3.3.0'

# Login to Azure
Connect-AzAccount | Out-Null # Hide the output of the login which normally gives a list of environments

# Get Azure SQL Database/Server resources information
$SubscriptionId = "TYPE_SUBSCRIPTION_ID"
$ResourceGroupName = "TYPE_RESOURCE_GROUP_NAME"

$sourceSqlServerName = "TYPE_SOURCE_SERVER_NAME"
$sourceDatabaseName = "TYPE_SOURCE_DATABASE_NAME"

$targetSqlServerName = "TYPE_TARGET_SERVER_NAME"
$targetSqlServerFQDN = $targetSqlServerName + ".database.windows.net"
$targetDatabaseName = "TYPE_TARGET_DATABASE_NAME_COPY"

$serverAdmin = 'TYPE_TARGET_SERVER_USERNAME'
$serverPassword = 'TYPE_TARGET_SERVER_PASSWORD'

# Convert the password to a secure string
$securePassword = ConvertTo-SecureString -String $serverPassword -AsPlainText -Force
$SqlAdministratorCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $serverAdmin, $securePassword

# Storage account information for the BACPAC
$BaseStorageUri = "https://TYPE_STORAGE_ACCOUNT_NAME.blob.core.windows.net/TYPE_CONTAINER_NAME/"
$BacpacUri = $BaseStorageUri + $bacpacFilename
$StorageKeytype = "StorageAccessKey"
$StorageKey = 'TYPE_STORAGE_ACCESS_KEY'

# Select Azure Subscription
Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null # Hide the output of the subscription selection which normally gives a list subscription name, Tenant ID, etc...

# 2) Create a database copy.
# The way to ensure that the backup file is consistent is to export a database that has no write activity during the export or create a copy of the database and do the export based on that copy.
$newDatabase = Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $targetSqlServerName `
    -DatabaseName $targetDatabaseName -ErrorAction Ignore

if ($null -ne $newDatabase -and $newDatabase.DatabaseName -eq $targetDatabaseName)
{
    Write-Host "**********************************************************************************************************************************" -ForegroundColor Red
    Write-Host "ERROR: The target database with the same name already exists! Please delete the target database database before run this script." -ForegroundColor Red
    Write-Host "**********************************************************************************************************************************" -ForegroundColor Red
    Break

} else {
    try {
    Write-Host "***********************************************************************************************************************************" -ForegroundColor Yellow
    Write-Host "INFO: The database copy is a asynchronous operation but the target database is created immediately after the request is accepted." -ForegroundColor Yellow
    Write-Host "               If you need to cancel the copy operation while still in progress, drop the the TARGET database." -ForegroundColor Yellow
    Write-Host "***********************************************************************************************************************************" -ForegroundColor Yellow
    
    Write-Host "Starting copy of database '$sourceDatabaseName' to '$targetDatabaseName', please wait..." -ForegroundColor Cyan
    $newDatabase = New-AzSqlDatabaseCopy -ResourceGroupName $ResourceGroupName -ServerName $sourceSqlServerName -DatabaseName $sourceDatabaseName `
        -CopyResourceGroupName $ResourceGroupName -CopyServerName $targetSqlServerName -CopyDatabaseName $targetDatabaseName -ErrorAction Stop
    Write-Host "********************************************************" -ForegroundColor Green
    Write-Host "SUCCESS: The SQL database from copy has been created!" -ForegroundColor Green
    Write-Host "********************************************************" -ForegroundColor Green

    } catch {
    Write-Host "************************************************************" -ForegroundColor Red
    Write-Host "ERROR: Error while copying database to the target server!" -ForegroundColor Red
    Write-Host "************************************************************" -ForegroundColor Red
    Break
    }
}

# 3) Remove the Data Sync metadata objects from the copy. 
# The following T-SQL queries will immediately clean all objects related to Data Sync metadata db, hub or member of the copied database.
try {
# You can display SQL Server message output, such as those that result from the SQL PRINT statement, by specifying the -Verbose parameter.
Write-Host "Starting clean all objects related to Data Sync metadata db, hub or member of the copied database, please wait..." -ForegroundColor Cyan
Start-Sleep -s 60
Invoke-Sqlcmd -ServerInstance $targetSqlServerFQDN -User $serverAdmin -Password $serverPassword -Database $targetDatabaseName -ConnectionTimeout 30 -OutputSqlErrors $true -AbortOnError -Query "
declare @n char(1)
set @n = char(10)

declare @triggers nvarchar(max)
declare @procedures nvarchar(max)
declare @constraints nvarchar(max)
declare @FKs nvarchar(max)
declare @tables nvarchar(max)
declare @udt nvarchar(max)

-- triggers
select @triggers = isnull( @triggers + @n, '' ) + 'drop trigger [' + schema_name(schema_id) + '].[' + name + ']'
from sys.objects
where type in ( 'TR') and name like '%_dss_%'

-- procedures
select @procedures = isnull( @procedures + @n, '' ) + 'drop procedure [' + schema_name(schema_id) + '].[' + name + ']'
from sys.procedures
where schema_name(schema_id) = 'dss' or schema_name(schema_id) = 'TaskHosting' or schema_name(schema_id) = 'DataSync'

-- check constraints
select @constraints = isnull( @constraints + @n, '' ) + 'alter table [' + schema_name(schema_id) + '].[' + object_name( parent_object_id ) + ']    drop constraint [' + name + ']'
from sys.check_constraints
where schema_name(schema_id) = 'dss' or schema_name(schema_id) = 'TaskHosting' or schema_name(schema_id) = 'DataSync'

-- foreign keys
select @FKs = isnull( @FKs + @n, '' ) + 'alter table [' + schema_name(schema_id) + '].[' + object_name( parent_object_id ) + '] drop constraint [' + name + ']'
from sys.foreign_keys
where schema_name(schema_id) = 'dss' or schema_name(schema_id) = 'TaskHosting' or schema_name(schema_id) = 'DataSync'

-- tables
select @tables = isnull( @tables + @n, '' ) + 'drop table [' + schema_name(schema_id) + '].[' + name + ']'
from sys.tables
where schema_name(schema_id) = 'dss' or schema_name(schema_id) = 'TaskHosting' or schema_name(schema_id) = 'DataSync'

-- user defined types
select @udt = isnull( @udt + @n, '' ) + 'drop type [' + schema_name(schema_id) + '].[' + name + ']'
from sys.types
where is_user_defined = 1
and schema_name(schema_id) = 'dss' or schema_name(schema_id) = 'TaskHosting' or schema_name(schema_id) = 'DataSync'
order by system_type_id desc

print @triggers
print @procedures 
print @constraints 
print @FKs 
print @tables
print @udt 

exec sp_executesql @triggers
exec sp_executesql @procedures 
exec sp_executesql @constraints 
exec sp_executesql @FKs 
exec sp_executesql @tables
exec sp_executesql @udt

declare @functions nvarchar(max)

-- functions
select @functions = isnull( @functions + @n, '' ) + 'drop function [' + schema_name(schema_id) + '].[' + name + ']'
from sys.objects
where type in ( 'FN', 'IF', 'TF' )
and schema_name(schema_id) = 'dss' or schema_name(schema_id) = 'TaskHosting' or schema_name(schema_id) = 'DataSync'

print @functions 
exec sp_executesql @functions

DROP SCHEMA IF EXISTS [dss]
DROP SCHEMA IF EXISTS [TaskHosting]
DROP SCHEMA IF EXISTS [DataSync]
DROP USER IF EXISTS [##MS_SyncAccount##]
DROP USER IF EXISTS [##MS_SyncResourceManager##]
DROP ROLE IF EXISTS [DataSync_admin]
DROP ROLE IF EXISTS [DataSync_executor]
DROP ROLE IF EXISTS [DataSync_reader]

--symmetric_keys
declare @symmetric_keys nvarchar(max)
select @symmetric_keys = isnull( @symmetric_keys + @n, '' ) + 'drop symmetric key [' + name + ']'
from sys.symmetric_keys
where name like 'DataSyncEncryptionKey%'

print @symmetric_keys 
exec sp_executesql @symmetric_keys

-- certificates
declare @certificates nvarchar(max)
select @certificates = isnull( @certificates + @n, '' ) + 'drop certificate [' + name + ']'
from sys.certificates
where name like 'DataSyncEncryptionCertificate%'

print @certificates 
exec sp_executesql @certificates

print 'T-SQL Data Sync clean up finished'
GO
"

} catch {
  Write-Host "************************************************************" -ForegroundColor Red
  Write-Host "ERROR: Error while running Transact-SQL Data Sync script!" -ForegroundColor Red
  Write-Host "************************************************************" -ForegroundColor Red
  Break
}

Write-Host "*****************************************************************************************************" -ForegroundColor Green
Write-Host "SUCCESS: All objects related to Data Sync metadata db, hub or member was removed from the database!" -ForegroundColor Green
Write-Host "*****************************************************************************************************" -ForegroundColor Green

# 4) Export the database from the copy.
# Generate a unique filename for the BACPAC
$bacpacFilename = $targetDatabaseName + "-" + (Get-Date).ToString("yyyyMMddHHmm") + ".bacpac"

Write-Host "Starting export SQL database from copy as a .bacpac file to a storage account, please wait..." -ForegroundColor Cyan
Start-Sleep -s 15
try {
$exportRequest = New-AzSqlDatabaseExport -ResourceGroupName $ResourceGroupName -ServerName $targetSqlServerName `
  -DatabaseName $targetDatabaseName -StorageKeytype $StorageKeytype -StorageKey $StorageKey -StorageUri $BacpacUri `
  -AdministratorLogin $SqlAdministratorCredentials.UserName -AdministratorLoginPassword $SqlAdministratorCredentials.Password

# Check status of the export
$exportStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink
[Console]::Write("Exporting")
while ($exportStatus.Status -eq "InProgress")
{
    Start-Sleep -s 10
    $exportStatus = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink
    [Console]::Write(".")
}
[Console]::WriteLine("")

} catch {
  Write-Host "************************************************************" -ForegroundColor Red
  Write-Host "ERROR: Error while while exporting SQL database copy!" -ForegroundColor Red
  Write-Host "    Please REMOVE/DELETE database copy manually!" -ForegroundColor Red
  Write-Host "************************************************************" -ForegroundColor Red
  Break
  }

Write-Host "******************************************************************************" -ForegroundColor Green
Write-Host "SUCCESS: The database was exported as a .bacpac file to a storage account!" -ForegroundColor Green
Write-Host "******************************************************************************" -ForegroundColor Green

# 5) Delete the database copy in case of successfully completed export operation.
Write-Host "Starting remove SQL database copy, please wait..." -ForegroundColor Cyan
Start-Sleep -s 20
try {
Remove-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $targetSqlServerName -DatabaseName $targetDatabaseName | Out-Null

Write-Host "*********************************************************" -ForegroundColor Green
Write-Host "SUCCESS: The Azure SQL database copy has been removed!" -ForegroundColor Green
Write-Host "*********************************************************" -ForegroundColor Green

} catch {
  Write-Host "*******************************************************" -ForegroundColor Red
  Write-Host "ERROR: Error while removing Azure SQL database copy!" -ForegroundColor Red
  Write-Host "*******************************************************" -ForegroundColor Red
  Break
}
