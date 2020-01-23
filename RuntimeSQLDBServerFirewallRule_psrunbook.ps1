<#
- RuntimeSQLDBServerFirewallRule_psrunbook.ps1

This script will add a firewall rule that allows the Azure Public IP used by the PowerShell runbook at run time to access the specified SQL server, execute a Transact-SQL query in the specified database then it will remove the firewall rule previously created.
* Please review the contents of this file before execute the script in order to understand what the script is going to perform in your Azure environment. It's easy to understand and well commented.

You must deploy these required modules on the Azure Automation Account

Microsoft Azure PowerShell Az commands
https://www.powershellgallery.com/packages/Az/

SqlServer - Invoke-Sqlcmd command
https://www.powershellgallery.com/packages/Sqlserver/

WebRequest - Invoke-WebRequest command
https://www.powershellgallery.com/packages/WebRequest/

#>

# Run As account to authenticate runbooks using the service principal
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection"
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName -ErrorAction Stop

        "Logging in to Azure..."
        Add-AzAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint -ErrorAction Stop
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Get Azure SQL Database/Server and Runbook resources information
$AutomationAccountCredentials = Get-AutomationPSCredential -Name "TYPE_AUTOMATION_ACCOUNT_CREDENTIAL_NAME"
$ServerName = "TYPE_AZURESQL_SERVER_NAME"
$ServerFQDN = $ServerName + ".database.windows.net"
$DatabaseName = "TYPE_DATABASE_NAME"
$ResourceGroupName = "TYPE_RESOURCE_GROUP_NAME"
$FirewallRuleName = "TYPE_FIREWALL_RULE_NAME" # Specifies the name of the new firewall rule, for example "PS-Runbook-Automation-IP"
$SQLQuery = "Select @@VERSION"

try {
    Write-Output ""
    Write-Output "Looking for the runbook Azure Public IP, please wait..."
    $publicIp = (Invoke-WebRequest -TimeoutSec 1000 –ErrorAction Stop -UseBasicParsing -Uri http://myexternalip.com/raw).Content -replace "`n"

    Write-Output ""
    Write-Output "*********************************************************"
    Write-Output "SUCCESS: The runbook Azure Public IP has been retrived!"
    Write-Output "*********************************************************"
    Write-Output ""

    } catch {
    Write-Output ""
    Write-Error –Message "**********************************************************"
    Write-Error –Message "ERROR: Error while getting the runbook Azure Public IP!"
    Write-Error –Message "**********************************************************"
    Write-Output ""
    Break
    }

# Adding the firewall rule in the SQL server
Write-Output ""
Write-Output "Trying to add the firewall rule in the server $ServerName, please wait..."
$AddFWRule = New-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName `
    -ServerName $ServerName -FirewallRuleName $FirewallRuleName `
    -StartIpAddress $publicIp -EndIpAddress $publicIp
if ($null -ne $AddFWRule)
{
    Write-Output ""
    Write-Output "**********************************************************************"
    Write-Output "The firewall rule for the IP Address $($AddFWRule.StartIpAddress) has been added!"
    Write-Output "**********************************************************************"
    Write-Output ""
}
else
{
    Write-Output ""
    Write-Error –Message "********************************************************************"
    Write-Error –Message "Unable to add a firewall rule for the IP Address $($AddFWRule.StartIpAddress)"
    Write-Error –Message "********************************************************************"
    Write-Output ""
    Break
}

# Executing a Transact-SQL query using the Invoke-Sqlcmd command
try {
    Write-Output ""
    Write-Output "Trying to execute the Transact-SQL query on the database $DatabaseName, please wait..."
    Start-Sleep -s 10
    Invoke-Sqlcmd -ServerInstance $ServerFQDN -User $AutomationAccountCredentials.UserName -Password $AutomationAccountCredentials.GetNetworkCredential().Password -Database $DatabaseName -ConnectionTimeout 30 -OutputSqlErrors $true -AbortOnError -Query $SQLQuery -Verbose

} catch {
    Write-Output ""
    Write-Error –Message "*************************************************"
    Write-Error –Message "ERROR: Error while running Transact-SQL query!"
    Write-Error –Message "*************************************************"
    Write-Output ""
    Break
  }
    Write-Output ""
    Write-Output "*************************************************************"
    Write-Output "SUCCESS: The Transact-SQL query was successfully executed!"
    Write-Output "*************************************************************"
    Write-Output ""
  
# Deleting the firewall rule previously added in the SQL server
Write-Output ""
Write-Output "Trying to delete the firewall rule previously added in the server $ServerName, please wait..."
Start-Sleep -s 5
$RemoveFWRule = Remove-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName `
        -ServerName $ServerName -FirewallRuleName $FirewallRuleName
if ($null -ne $RemoveFWRule)
{
    Write-Output ""
    Write-Output "**********************************************************************************"
    Write-Output "SUCCESS: The firewall rule for the IP Address $($RemoveFWRule.StartIpAddress) has been removed!"
    Write-Output "**********************************************************************************"
    Write-Output ""
}
else
{
    Write-Output ""
    Write-Error –Message "*****************************************************************************************************************"
    Write-Error –Message "Unable to remove the firewall rule for IP Address $($RemoveFWRule.StartIpAddress), * PLEASE REMOVE THE FIREWALL RULE MANUALLY *"
    Write-Error –Message "*****************************************************************************************************************"
    Write-Output ""
    Break
}
