<#
- AddFirewallRuleOnMultipleMySqlServers.ps1

This script will add a single firewall rule on multiple Azure Database for MySQL servers in specified Resource Group.
* Please review the contents of this file before execute the script in order to understand what the script is going to perform in your Azure environment. It's easy to understand and well commented.

You must install Azure PowerShell and Az.MySql cmdlet module. I'm using the following versions (Az 5.1.0 / Az.MySql 0.2.0) at the moment of writing this script.

Microsoft Azure PowerShell
https://docs.microsoft.com/en-us/powershell/azure/

Microsoft Azure PowerShell: MySql cmdlets
https://docs.microsoft.com/en-us/powershell/module/az.mysql/

#>

# Get Azure resources information
$SubscriptionId = "TYPE_SUBSCRIPTION_ID"
$ResourceGroup = "TYPE_RESOURCE_GROUP_NAME"

# MySQL server firewall rule information
$FirewallRuleName = "TYPE_FIREWALL_RULE_NAME" # The name of the server firewall rule. If not specified, the default is undefined. If AllowAll is present, the default name is AllowAll_yyyy-MM-dd_HH-mm-ss.
$StartIPAddress = "0.0.0.0" # The start IP address of the server firewall rule. Must be IPv4 format.
$EndIPAddress = "0.0.0.0" # The end IP address of the server firewall rule. Must be IPv4 format.

# Login to Azure
Connect-AzAccount -SubscriptionId $SubscriptionId | Out-Null # Hide the output of the login which normally gives a list of environments

# Lists all the MySQL servers in specified resource group
try {

Write-Host "Starting listing MySQL servers for the Resource Group $ResourceGroup, please wait..." -ForegroundColor Cyan
$AzureMySQLServers = Get-AzMySqlServer -ResourceGroupName $ResourceGroup

Write-Host "*****************************************************************************" -ForegroundColor Green
Write-Host "SUCCESS: The list of Azure Database for MySQL server(s) has been acquired!" -ForegroundColor Green
Write-Host "*****************************************************************************" -ForegroundColor Green

} catch {
  Write-Host "*****************************************************************************" -ForegroundColor Red
  Write-Host "ERROR: Error while getting the list of Azure Database for MySQL server(s)!" -ForegroundColor Red
  Write-Host "*****************************************************************************" -ForegroundColor Red
  Break
}

ForEach ($AzureMySQLServer in $AzureMySQLServers) {

    try {
    # Creates a new firewall rule or updates an existing firewall rule
    New-AzMySqlFirewallRule -Name $FirewallRuleName -ResourceGroupName $ResourceGroup -ServerName $AzureMySQLServer.Name -EndIPAddress $StartIPAddress -StartIPAddress $EndIPAddress | Out-Null 
    Write-Host "The firewall rule $FirewallRuleName has been added to the server $($AzureMySQLServer.Name), please wait..." -ForegroundColor Cyan

    } catch {
    Write-Host "ERROR: Error while adding the firewall rule $FirewallRuleName into the server $($AzureMySQLServer.Name)!" -ForegroundColor Red
    Break
    }
}

Write-Host "*********************************************************************************************************************" -ForegroundColor Green
Write-Host "SUCCESS: The firewall rule $FirewallRuleName has been added to all server(s) in the Resource Group $ResourceGroup!" -ForegroundColor Green
Write-Host "*********************************************************************************************************************" -ForegroundColor Green
