# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#HelloID variables
#Note: when running this script inside HelloID; portalUrl and API credentials are provided automatically (generate and save API credentials first in your admin panel!)
$portalUrl = "https://CUSTOMER.helloid.com"
$apiKey = "API_KEY"
$apiSecret = "API_SECRET"
$delegatedFormAccessGroupNames = @("") #Only unique names are supported. Groups must exist!
$delegatedFormCategories = @("Exchange On-Premises") #Only unique names are supported. Categories will be created if not exists
$script:debugLogging = $false #Default value: $false. If $true, the HelloID resource GUIDs will be shown in the logging
$script:duplicateForm = $false #Default value: $false. If $true, the HelloID resource names will be changed to import a duplicate Form
$script:duplicateFormSuffix = "_tmp" #the suffix will be added to all HelloID resource names to generate a duplicate form with different resource names

#The following HelloID Global variables are used by this form. No existing HelloID global variables will be overriden only new ones are created.
#NOTE: You can also update the HelloID Global variable values afterwards in the HelloID Admin Portal: https://<CUSTOMER>.helloid.com/admin/variablelibrary
$globalHelloIDVariables = [System.Collections.Generic.List[object]]@();

#Global variable #1 >> ExchangeConnectionUri
$tmpName = @'
ExchangeConnectionUri
'@ 
$tmpValue = @'
http://servername/powershell
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });

#Global variable #2 >> ExchangeAdminPassword
$tmpName = @'
ExchangeAdminPassword
'@ 
$tmpValue = "" 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "True" });

#Global variable #3 >> ExchangeAdminUsername
$tmpName = @'
ExchangeAdminUsername
'@ 
$tmpValue = @'
t4e\svc_helloid
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });

#Global variable #4 >> ADsharedMailboxOU
$tmpName = @'
ADsharedMailboxOU
'@ 
$tmpValue = @'
OU=Shared Mailbox Users,OU=HelloID Mail,DC=T4E,DC=local
'@ 
$globalHelloIDVariables.Add([PSCustomObject]@{name = $tmpName; value = $tmpValue; secret = "False" });


#make sure write-information logging is visual
$InformationPreference = "continue"

# Check for prefilled API Authorization header
if (-not [string]::IsNullOrEmpty($portalApiBasic)) {
    $script:headers = @{"authorization" = $portalApiBasic }
    Write-Information "Using prefilled API credentials"
}
else {
    # Create authorization headers with HelloID API key
    $pair = "$apiKey" + ":" + "$apiSecret"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)
    $key = "Basic $base64"
    $script:headers = @{"authorization" = $Key }
    Write-Information "Using manual API credentials"
}

# Check for prefilled PortalBaseURL
if (-not [string]::IsNullOrEmpty($portalBaseUrl)) {
    $script:PortalBaseUrl = $portalBaseUrl
    Write-Information "Using prefilled PortalURL: $script:PortalBaseUrl"
}
else {
    $script:PortalBaseUrl = $portalUrl
    Write-Information "Using manual PortalURL: $script:PortalBaseUrl"
}

# Define specific endpoint URI
$script:PortalBaseUrl = $script:PortalBaseUrl.trim("/") + "/"  

# Make sure to reveive an empty array using PowerShell Core
function ConvertFrom-Json-WithEmptyArray([string]$jsonString) {
    # Running in PowerShell Core?
    if ($IsCoreCLR -eq $true) {
        $r = [Object[]]($jsonString | ConvertFrom-Json -NoEnumerate)
        return , $r  # Force return value to be an array using a comma
    }
    else {
        $r = [Object[]]($jsonString | ConvertFrom-Json)
        return , $r  # Force return value to be an array using a comma
    }
}

function Invoke-HelloIDGlobalVariable {
    param(
        [parameter(Mandatory)][String]$Name,
        [parameter(Mandatory)][String][AllowEmptyString()]$Value,
        [parameter(Mandatory)][String]$Secret
    )

    $Name = $Name + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automation/variables/named/$Name")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false

        if ([string]::IsNullOrEmpty($response.automationVariableGuid)) {
            #Create Variable
            $body = @{
                name     = $Name;
                value    = $Value;
                secret   = $Secret;
                ItemType = 0;
            }    
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automation/variable")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $variableGuid = $response.automationVariableGuid

            Write-Information "Variable '$Name' created$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
        else {
            $variableGuid = $response.automationVariableGuid
            Write-Warning "Variable '$Name' already exists$(if ($script:debugLogging -eq $true) { ": " + $variableGuid })"
        }
    }
    catch {
        Write-Error "Variable '$Name', message: $_"
    }
}

function Invoke-HelloIDAutomationTask {
    param(
        [parameter(Mandatory)][String]$TaskName,
        [parameter(Mandatory)][String]$UseTemplate,
        [parameter(Mandatory)][String]$AutomationContainer,
        [parameter(Mandatory)][String][AllowEmptyString()]$Variables,
        [parameter(Mandatory)][String]$PowershellScript,
        [parameter()][String][AllowEmptyString()]$ObjectGuid,
        [parameter()][String][AllowEmptyString()]$ForceCreateTask,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $TaskName = $TaskName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/automationtasks?search=$TaskName&container=$AutomationContainer")
        $responseRaw = (Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false) 
        $response = $responseRaw | Where-Object -filter { $_.name -eq $TaskName }

        if ([string]::IsNullOrEmpty($response.automationTaskGuid) -or $ForceCreateTask -eq $true) {
            #Create Task

            $body = @{
                name                = $TaskName;
                useTemplate         = $UseTemplate;
                powerShellScript    = $PowershellScript;
                automationContainer = $AutomationContainer;
                objectGuid          = $ObjectGuid;
                variables           = (ConvertFrom-Json-WithEmptyArray($Variables));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/automationtasks/powershell")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            $taskGuid = $response.automationTaskGuid

            Write-Information "Powershell task '$TaskName' created$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
        else {
            #Get TaskGUID
            $taskGuid = $response.automationTaskGuid
            Write-Warning "Powershell task '$TaskName' already exists$(if ($script:debugLogging -eq $true) { ": " + $taskGuid })"
        }
    }
    catch {
        Write-Error "Powershell task '$TaskName', message: $_"
    }

    $returnObject.Value = $taskGuid
}

function Invoke-HelloIDDatasource {
    param(
        [parameter(Mandatory)][String]$DatasourceName,
        [parameter(Mandatory)][String]$DatasourceType,
        [parameter(Mandatory)][String][AllowEmptyString()]$DatasourceModel,
        [parameter()][String][AllowEmptyString()]$DatasourceStaticValue,
        [parameter()][String][AllowEmptyString()]$DatasourcePsScript,        
        [parameter()][String][AllowEmptyString()]$DatasourceInput,
        [parameter()][String][AllowEmptyString()]$AutomationTaskGuid,
        [parameter()][String][AllowEmptyString()]$DatasourceRunInCloud,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $DatasourceName = $DatasourceName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    $datasourceTypeName = switch ($DatasourceType) { 
        "1" { "Native data source"; break } 
        "2" { "Static data source"; break } 
        "3" { "Task data source"; break } 
        "4" { "Powershell data source"; break }
    }

    try {
        $uri = ($script:PortalBaseUrl + "api/v1/datasource/named/$DatasourceName")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
    
        if ([string]::IsNullOrEmpty($response.dataSourceGUID)) {
            #Create DataSource
            $body = @{
                name               = $DatasourceName;
                type               = $DatasourceType;
                model              = (ConvertFrom-Json-WithEmptyArray($DatasourceModel));
                automationTaskGUID = $AutomationTaskGuid;
                value              = (ConvertFrom-Json-WithEmptyArray($DatasourceStaticValue));
                script             = $DatasourcePsScript;
                input              = (ConvertFrom-Json-WithEmptyArray($DatasourceInput));
                runInCloud         = $DatasourceRunInCloud;
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100
    
            $uri = ($script:PortalBaseUrl + "api/v1/datasource")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
            
            $datasourceGuid = $response.dataSourceGUID
            Write-Information "$datasourceTypeName '$DatasourceName' created$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
        else {
            #Get DatasourceGUID
            $datasourceGuid = $response.dataSourceGUID
            Write-Warning "$datasourceTypeName '$DatasourceName' already exists$(if ($script:debugLogging -eq $true) { ": " + $datasourceGuid })"
        }
    }
    catch {
        Write-Error "$datasourceTypeName '$DatasourceName', message: $_"
    }

    $returnObject.Value = $datasourceGuid
}

function Invoke-HelloIDDynamicForm {
    param(
        [parameter(Mandatory)][String]$FormName,
        [parameter(Mandatory)][String]$FormSchema,
        [parameter(Mandatory)][Ref]$returnObject
    )

    $FormName = $FormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/forms/$FormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        }
        catch {
            $response = $null
        }

        if (([string]::IsNullOrEmpty($response.dynamicFormGUID)) -or ($response.isUpdated -eq $true)) {
            #Create Dynamic form
            $body = @{
                Name       = $FormName;
                FormSchema = (ConvertFrom-Json-WithEmptyArray($FormSchema));
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/forms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $formGuid = $response.dynamicFormGUID
            Write-Information "Dynamic form '$formName' created$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
        else {
            $formGuid = $response.dynamicFormGUID
            Write-Warning "Dynamic form '$FormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $formGuid })"
        }
    }
    catch {
        Write-Error "Dynamic form '$FormName', message: $_"
    }

    $returnObject.Value = $formGuid
}


function Invoke-HelloIDDelegatedForm {
    param(
        [parameter(Mandatory)][String]$DelegatedFormName,
        [parameter(Mandatory)][String]$DynamicFormGuid,
        [parameter()][Array][AllowEmptyString()]$AccessGroups,
        [parameter()][String][AllowEmptyString()]$Categories,
        [parameter(Mandatory)][String]$UseFaIcon,
        [parameter()][String][AllowEmptyString()]$FaIcon,
        [parameter()][String][AllowEmptyString()]$task,
        [parameter(Mandatory)][Ref]$returnObject
    )
    $delegatedFormCreated = $false
    $DelegatedFormName = $DelegatedFormName + $(if ($script:duplicateForm -eq $true) { $script:duplicateFormSuffix })

    try {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/delegatedforms/$DelegatedFormName")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        }
        catch {
            $response = $null
        }

        if ([string]::IsNullOrEmpty($response.delegatedFormGUID)) {
            #Create DelegatedForm
            $body = @{
                name            = $DelegatedFormName;
                dynamicFormGUID = $DynamicFormGuid;
                isEnabled       = "True";
                useFaIcon       = $UseFaIcon;
                faIcon          = $FaIcon;
                task            = ConvertFrom-Json -inputObject $task;
            }
            if (-not[String]::IsNullOrEmpty($AccessGroups)) { 
                $body += @{
                    accessGroups = (ConvertFrom-Json-WithEmptyArray($AccessGroups));
                }
            }
            $body = ConvertTo-Json -InputObject $body -Depth 100

            $uri = ($script:PortalBaseUrl + "api/v1/delegatedforms")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body

            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Information "Delegated form '$DelegatedFormName' created$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
            $delegatedFormCreated = $true

            $bodyCategories = $Categories
            $uri = ($script:PortalBaseUrl + "api/v1/delegatedforms/$delegatedFormGuid/categories")
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $bodyCategories
            Write-Information "Delegated form '$DelegatedFormName' updated with categories"
        }
        else {
            #Get delegatedFormGUID
            $delegatedFormGuid = $response.delegatedFormGUID
            Write-Warning "Delegated form '$DelegatedFormName' already exists$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormGuid })"
        }
    }
    catch {
        Write-Error "Delegated form '$DelegatedFormName', message: $_"
    }

    $returnObject.value.guid = $delegatedFormGuid
    $returnObject.value.created = $delegatedFormCreated
}

<# Begin: HelloID Global Variables #>
foreach ($item in $globalHelloIDVariables) {
    Invoke-HelloIDGlobalVariable -Name $item.name -Value $item.value -Secret $item.secret 
}
<# End: HelloID Global Variables #>


<# Begin: HelloID Data sources #>
<# Begin: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Check-Alias-Unique" #>
$tmpPsScript = @'
# variables configured in form
$alias = $datasource.alias
$mailDomain = $datasource.mailDomain.id
$PrimarySmtpAddress = "$alias@$mailDomain"

# Build filter
# Check for mailboxes matching the displayName, mailNickname (alias), primary email or proxy addresses
# This will check ALL users (enabled and disabled), including shared/room/equipment mailboxes
$filter = "Alias -eq '$alias' -or PrimarySmtpAddress -eq '$PrimarySmtpAddress' -or EmailAddresses -like '*$PrimarySmtpAddress*'"

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "Guid"
    , "DisplayName"
    , "Name"
    , "Alias"
    , "PrimarySmtpAddress"
    , "EmailAddresses"
    , "SamAccountName"
    , "RecipientTypeDetails"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions

try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-Recipient" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying shared mailboxes that match filter [$($filter)]"

    $getRecipientsSplatParams = @{
        Filter      = $filter
        ResultSize  = "Unlimited"
        ErrorAction = 'Stop'
    }

    $recipients = Get-Recipient @getRecipientsSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried aliases that match filter [$($filter)]. Result count: $(($recipients | Measure-Object).Count)"

    # Check if value is unique and free
    if (($recipients | Measure-Object).Count -gt 0) {
        Write-Warning "Alias is not unique. In use by object with displayName [$($recipients.displayName)], samAccountName [$($recipients.SamAccountName)] mail [$($recipients.PrimarySmtpAddress)] and alias [$($recipients.Alias)]."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Invalid: Alias is not unique. In use by object with displayName [$($recipients.displayName)], samAccountName [$($recipients.SamAccountName)] mail [$($recipients.PrimarySmtpAddress)] and alias [$($recipients.Alias)]"
    }
    else {
        Write-Information "Alias is unique and free to use."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Valid: Alias is unique and free to use." 
    }   
} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
}
finally {
    # Disconnect from Exchange
    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession
    if ($null -ne $exchangeSession) {
        try {
            $deleteExchangeSessionSplatParams = @{
                Session     = $exchangeSession
                Confirm     = $false
                ErrorAction = "Stop"
            }
            $null = Remove-PSSession @deleteExchangeSessionSplatParams
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"output","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"alias","type":0,"options":1},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"mailDomain","type":0,"options":1}]
'@ 
$dataSourceGuid_3 = [PSCustomObject]@{} 
$dataSourceGuid_3_Name = @'
exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Check-Alias-Unique
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_3_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_3) 
<# End: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Check-Alias-Unique" #>

<# Begin: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Get-All-MailDomains" #>
$tmpPsScript = @'
# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "id"
    , "IsValid"
    , "EmailOnly"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions


try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-AcceptedDomain" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying shared mailboxes that match filter [$($filter)]"

    $getMailboxesSplatParams = @{
        ErrorAction = 'Stop'
    }

    # Select only specified properties to limit memory usage
    $mailDomains = $null
    $mailDomains = Get-AcceptedDomain @getMailboxesSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried Exchange On-Premises Domains. Result count: $(@($mailDomains).Count)"

    # Filter for verified domains only and where Email is supported - not support by Graph API filter query
    $actionMessage = "filtering for verified domains only and where Email is supported"
    $mailDomains = $mailDomains | Where-Object { $_.IsValid -eq $true }
    Write-Information "Filter for verified domains only and where Email is supported. Result count: $(@($mailDomains).Count)"

    # Send results to HelloID
    $actionMessage = "sending results to HelloID"
    $mailDomains | Sort-Object -Property id | ForEach-Object {
        Write-Output $_
    }   
} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
}
finally {
    # Disconnect from Exchange
    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession
    if ($null -ne $exchangeSession) {
        try {
            $deleteExchangeSessionSplatParams = @{
                Session     = $exchangeSession
                Confirm     = $false
                ErrorAction = "Stop"
            }
            $null = Remove-PSSession @deleteExchangeSessionSplatParams
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"Id","type":0},{"key":"IsValid","type":0},{"key":"EmailOnly","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_1 = [PSCustomObject]@{} 
$dataSourceGuid_1_Name = @'
exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Get-All-MailDomains
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_1_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_1) 
<# End: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Get-All-MailDomains" #>

<# Begin: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Check-EmailAddress-Unique" #>
$tmpPsScript = @'
# variables configured in form
$mailPrefix = $datasource.mailPrefix
$mailDomain = $datasource.mailDomain.id
$PrimarySmtpAddress = "$mailPrefix@$mailDomain"

# Build filter
# Check for mailboxes matching the displayName, mailNickname (alias), primary email or proxy addresses
# This will check ALL users (enabled and disabled), including shared/room/equipment mailboxes
$filter = "Alias -eq '$mailPrefix' -or PrimarySmtpAddress -eq '$PrimarySmtpAddress' -or EmailAddresses -like '*$PrimarySmtpAddress*'"

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "Guid"
    , "DisplayName"
    , "Name"
    , "Alias"
    , "PrimarySmtpAddress"
    , "EmailAddresses"
    , "SamAccountName"
    , "RecipientTypeDetails"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions

try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-Recipient" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying all recipients that match filter [$($filter)]"

    $getRecipientsSplatParams = @{
        Filter      = $filter
        ResultSize  = "Unlimited"
        ErrorAction = 'Stop'
    }

    $recipients = Get-Recipient @getRecipientsSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried all recipients that match filter [$($filter)]. Result count: $(($recipients | Measure-Object).Count)"

    # Check if value is unique and free
    if (($recipients | Measure-Object).Count -gt 0) {
        Write-Warning "Email address is not unique. In use by object with displayName [$($recipients.displayName)], samAccountName [$($recipients.SamAccountName)] mail [$($recipients.PrimarySmtpAddress)] and alias [$($recipients.Alias)]."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Invalid: Email address is not unique. In use by object with displayName [$($recipients.displayName)], samAccountName [$($recipients.SamAccountName)] mail [$($recipients.PrimarySmtpAddress)] and alias [$($recipients.Alias)]"
    }
    else {
        Write-Information "Email address is unique and free to use."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Valid: Email address is unique and free to use." 
    }   
} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
}
finally {
    # Disconnect from Exchange
    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession
    if ($null -ne $exchangeSession) {
        try {
            $deleteExchangeSessionSplatParams = @{
                Session     = $exchangeSession
                Confirm     = $false
                ErrorAction = "Stop"
            }
            $null = Remove-PSSession @deleteExchangeSessionSplatParams
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"output","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"mailPrefix","type":0,"options":1},{"description":null,"translateDescription":false,"inputFieldType":1,"key":"mailDomain","type":0,"options":1}]
'@ 
$dataSourceGuid_2 = [PSCustomObject]@{} 
$dataSourceGuid_2_Name = @'
exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Check-EmailAddress-Unique
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_2_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_2) 
<# End: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Check-EmailAddress-Unique" #>

<# Begin: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Get-All-Users" #>
$tmpPsScript = @'
# Build filter
# Check for mailboxes matching the displayName, mailNickname (alias), primary email or proxy addresses
# This will check ALL users (enabled and disabled), including shared/room/equipment mailboxes
$filter = "RecipientType -eq 'UserMailbox'"

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "Guid"
    , "DisplayName"
    , "PrimarySmtpAddress"
    , "UserPrincipalName"    
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions

try {
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-Mailbox" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying shared mailboxes that match filter [$($filter)]"
    $getMailboxesSplatParams = @{
        Filter      = $filter
        ResultSize  = "Unlimited"
        ErrorAction = 'Stop'
    }

    $mailboxes = Get-Mailbox @getMailboxesSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried shared mailboxes that match filter [$($filter)]. Result count: $(($mailboxes | Measure-Object).Count)"

    # Sort and send results to HelloID
    $actionMessage = "sending results to HelloID"
    $mailboxes | Sort-Object -Property DisplayName | ForEach-Object {
        Write-Output $_
    }   
} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
}
finally {
    # Disconnect from Exchange
    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession
    if ($null -ne $exchangeSession) {
        try {
            $deleteExchangeSessionSplatParams = @{
                Session     = $exchangeSession
                Confirm     = $false
                ErrorAction = "Stop"
            }
            $null = Remove-PSSession @deleteExchangeSessionSplatParams
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"Guid","type":0},{"key":"DisplayName","type":0},{"key":"PrimarySmtpAddress","type":0},{"key":"UserPrincipalName","type":0}]
'@ 
$tmpInput = @'
[]
'@ 
$dataSourceGuid_4 = [PSCustomObject]@{} 
$dataSourceGuid_4_Name = @'
exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Get-All-Users
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_4_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_4) 
<# End: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Get-All-Users" #>

<# Begin: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Check-DisplayName-Unique" #>
$tmpPsScript = @'
# variables configured in form
$displayName = $datasource.displayName

# Build filter
# Check for mailboxes matching the displayName
# This will check ALL users (enabled and disabled), including shared/room/equipment mailboxes
$filter = "displayName -eq '$displayName'"

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""

# Fixed values
# Properties to select - Select only needed properties to limit memory usage and speed up processing
$propertiesToSelect = @(
    "Guid"
    , "DisplayName"
    , "Name"
    , "Alias"
    , "PrimarySmtpAddress"
    , "EmailAddresses"
    , "UserPrincipalName"
    , "RecipientTypeDetails"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
#endregion functions

try{
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises using URI [$ExchangeConnectionUri]"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $ExchangeConnectionUri
        Credential        = $credential
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName "Get-Mailbox" -ErrorAction Stop

     # Get Mailboxes
    # Docs: https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox
    $actionMessage = "querying shared mailboxes that match filter [$($filter)]"

    $getMailboxesSplatParams = @{
        Filter      = $filter
        ResultSize  = "Unlimited"
        ErrorAction = 'Stop'
    }

    $mailboxes = Get-Mailbox @getMailboxesSplatParams | Select-Object -Property $propertiesToSelect
    Write-Information "Queried Exchange On-Premises mailboxes matching filter [$filter]. Result count: $(@($mailboxes).Count)"

    # Check if value is unique and free
    if (($mailboxes | Measure-Object).Count -gt 0) {
        Write-Warning "Display name is not unique. In use by object with displayName [$($mailboxes.displayName)], userPrincipalName [$($mailboxes.userPrincipalName)] mail [$($mailboxes.mail)] and alias (mailNickName) [$($mailboxes.mailNickName)]."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Invalid: Display name is not unique. In use by object with displayName [$($mailboxes.displayName)], userPrincipalName [$($mailboxes.userPrincipalName)] mail [$($mailboxes.mail)] and alias (mailNickName) [$($mailboxes.mailNickName)]"
    }
    else {
        Write-Information "Display name is unique and free to use."

        # Send results to HelloID
        $actionMessage = "sending results to HelloID"
        Write-Output "Valid: Display name is unique and free to use." 
    }

} catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }
    Write-Warning $warningMessage
    Write-Error $auditMessage
    # exit # use when using multiple try/catch and the script must stop
}
finally {
    # Disconnect from Exchange
    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession
    if ($null -ne $exchangeSession) {
        try {
            $deleteExchangeSessionSplatParams = @{
                Session     = $exchangeSession
                Confirm     = $false
                ErrorAction = "Stop"
            }
            $null = Remove-PSSession @deleteExchangeSessionSplatParams
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}
'@ 
$tmpModel = @'
[{"key":"output","type":0}]
'@ 
$tmpInput = @'
[{"description":null,"translateDescription":false,"inputFieldType":1,"key":"displayName","type":0,"options":1}]
'@ 
$dataSourceGuid_0 = [PSCustomObject]@{} 
$dataSourceGuid_0_Name = @'
exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Check-DisplayName-Unique
'@ 
Invoke-HelloIDDatasource -DatasourceName $dataSourceGuid_0_Name -DatasourceType "4" -DatasourceInput $tmpInput -DatasourcePsScript $tmpPsScript -DatasourceModel $tmpModel -DataSourceRunInCloud "False" -returnObject ([Ref]$dataSourceGuid_0) 
<# End: DataSource "exchange-on-premises-sharedmailbox-create | Exchange-On-Premises-Check-DisplayName-Unique" #>
<# End: HelloID Data sources #>

<# Begin: Dynamic Form "Exchange On-Premises - Sharedmailbox - Create" #>
$tmpSchema = @"
[{"label":"Create mailbox","fields":[{"key":"displayname","templateOptions":{"label":"Displayname","placeholder":"Gedeelde Mailboxnaam","required":true,"minLength":2},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"nameValidation","templateOptions":{"label":"Display name validation","readonly":true,"placeholder":"Display name will be validated on uniqnueness in Exchange On-Premises","pattern":"^Valid.*","required":true,"useDependOn":false,"dependOn":"displayname","useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_0","input":{"propertyInputs":[{"propertyName":"displayName","otherFieldValue":{"otherFieldKey":"displayname"}}]}},"displayField":"output"},"hideExpression":"!model[\"displayname\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"templateOptions":{"title":"This address will be created as the primary SMTP address of the mailbox","titleField":"","bannerType":"Info","useBody":false},"type":"textbanner","summaryVisibility":"Show","body":"Text Banner Content","requiresTemplateOptions":false,"requiresKey":false,"requiresDataSource":false},{"key":"formRow","templateOptions":{},"fieldGroup":[{"key":"mailPrefix","templateOptions":{"label":"Email address","pattern":"^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$","minLength":1,"maxLength":200,"required":true},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"mailDomain","templateOptions":{"label":"Mail domain","required":true,"useObjects":false,"useDataSource":true,"useFilter":true,"options":["@domain.com","@domain2.com","@domain3.com"],"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_1","input":{"propertyInputs":[]}},"valueField":"Id","textField":"Id","useDefault":true,"defaultSelectorProperty":"Id"},"type":"dropdown","summaryVisibility":"Show","textOrLabel":"text","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}],"type":"formrow","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"mailValidation","templateOptions":{"label":"Email address validation","placeholder":"Email address will be validated on uniqnueness in Exchange On-Premises","pattern":"^Valid.*","required":true,"readonly":true,"useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_2","input":{"propertyInputs":[{"propertyName":"mailPrefix","otherFieldValue":{"otherFieldKey":"mailPrefix"}},{"propertyName":"mailDomain","otherFieldValue":{"otherFieldKey":"mailDomain"}}]}},"displayField":"output"},"hideExpression":"!model[\"mailPrefix\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"templateOptions":{"title":"The alias (mailNickname) is a short name used as an internal identifier for the group","titleField":"","bannerType":"Info","useBody":true},"type":"textbanner","summaryVisibility":"Hide element","body":"**The alias is a short name used as an internal identifier for the new group.**\r\n\r\nIt is not the same as the email address.  \r\nThe alias can only have **one** value, and it will be created exactly as entered.\r\n\r\nIf you do not provide an alias, the username portion of the email address will be used automatically.\r\n\r\nUse only letters, numbers, and periods (no spaces).  \r\nDo not include a domain (no \"@\").","requiresTemplateOptions":false,"requiresKey":false,"requiresDataSource":false},{"key":"alias","templateOptions":{"label":"Alias","placeholder":"it-dep","pattern":"^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$"},"type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"aliasValidation","templateOptions":{"label":"Alias validation","placeholder":"Alias will be validated on uniqnueness in Exchange On-Premises","pattern":"^Valid.*","readonly":true,"useDataSource":true,"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_3","input":{"propertyInputs":[{"propertyName":"alias","otherFieldValue":{"otherFieldKey":"alias"}},{"propertyName":"mailDomain","otherFieldValue":{"otherFieldKey":"mailDomain"}}]}},"displayField":"output"},"hideExpression":"!model[\"alias\"]","type":"input","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false}]},{"label":"Mailbox Permissions","fields":[{"key":"permission","templateOptions":{"label":"Permission","required":false,"useObjects":true,"useDataSource":false,"useFilter":false,"options":[{"value":"fullaccess","text":"Full Access"},{"value":"sendas","text":"Send As"},{"value":"sendonbehalf","text":"Send on Behalf"}]},"type":"dropdown","summaryVisibility":"Show","textOrLabel":"text","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"blnIncludeSendAs","templateOptions":{"label":"Include Send As with Full Access?","useSwitch":true,"checkboxLabel":"Include Send As with Full Access"},"hideExpression":"model[\"permission\"]!==\u0027fullaccess\u0027","type":"boolean","defaultValue":true,"summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":false},{"key":"usersToAdd","templateOptions":{"label":"User(s) to grant permission","required":false,"grid":{"columns":[{"headerName":"User Principal Name","field":"UserPrincipalName"},{"headerName":"Display Name","field":"DisplayName"},{"headerName":"Primary Smtp Address","field":"PrimarySmtpAddress"}],"height":300,"rowSelection":"multiple"},"dataSourceConfig":{"dataSourceGuid":"$dataSourceGuid_4","input":{"propertyInputs":[]}},"useFilter":true,"useDefault":false,"allowCsvDownload":false},"hideExpression":"!model[\"permission\"]","type":"multiselectgrid","summaryVisibility":"Show","requiresTemplateOptions":true,"requiresKey":true,"requiresDataSource":true}]}]
"@ 

$dynamicFormGuid = [PSCustomObject]@{} 
$dynamicFormName = @'
Exchange On-Premises - Sharedmailbox - Create
'@ 
Invoke-HelloIDDynamicForm -FormName $dynamicFormName -FormSchema $tmpSchema  -returnObject ([Ref]$dynamicFormGuid) 
<# END: Dynamic Form #>

<# Begin: Delegated Form Access Groups and Categories #>
$delegatedFormAccessGroupGuids = @()
if (-not[String]::IsNullOrEmpty($delegatedFormAccessGroupNames)) {
    foreach ($group in $delegatedFormAccessGroupNames) {
        try {
            $uri = ($script:PortalBaseUrl + "api/v1/groups/$group")
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
            $delegatedFormAccessGroupGuid = $response.groupGuid
            $delegatedFormAccessGroupGuids += $delegatedFormAccessGroupGuid
        
            Write-Information "HelloID (access)group '$group' successfully found$(if ($script:debugLogging -eq $true) { ": " + $delegatedFormAccessGroupGuid })"
        }
        catch {
            Write-Error "HelloID (access)group '$group', message: $_"
        }
    }
    if ($null -ne $delegatedFormAccessGroupGuids) {
        $delegatedFormAccessGroupGuids = ($delegatedFormAccessGroupGuids | Select-Object -Unique | ConvertTo-Json -Depth 100 -Compress)
    }
}

$delegatedFormCategoryGuids = @()
foreach ($category in $delegatedFormCategories) {
    try {
        $uri = ($script:PortalBaseUrl + "api/v1/delegatedformcategories/$category")
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false
        $response = $response | Where-Object { $_.name.en -eq $category }
    
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid
    
        Write-Information "HelloID Delegated Form category '$category' successfully found$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
    catch {
        Write-Warning "HelloID Delegated Form category '$category' not found"
        $body = @{
            name = @{"en" = $category };
        }
        $body = ConvertTo-Json -InputObject $body -Depth 100

        $uri = ($script:PortalBaseUrl + "api/v1/delegatedformcategories")
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $script:headers -ContentType "application/json" -Verbose:$false -Body $body
        $tmpGuid = $response.delegatedFormCategoryGuid
        $delegatedFormCategoryGuids += $tmpGuid

        Write-Information "HelloID Delegated Form category '$category' successfully created$(if ($script:debugLogging -eq $true) { ": " + $tmpGuid })"
    }
}
$delegatedFormCategoryGuids = (ConvertTo-Json -InputObject $delegatedFormCategoryGuids -Depth 100 -Compress)
<# End: Delegated Form Access Groups and Categories #>

<# Begin: Delegated Form #>
$delegatedFormRef = [PSCustomObject]@{guid = $null; created = $null } 
$delegatedFormName = @'
Exchange On-Premises - Sharedmailbox - Create
'@
$tmpTask = @'
{"name":"Exchange On-Premises - Sharedmailbox - Create","script":"# static variable\r\n$AutoMapping = $True\r\n\r\n# variables configured in form\r\n$mailboxDisplayName = $form.displayName\r\n$mailboxPrimarySmtpAddress = \"$($form.mailPrefix)@$($form.mailDomain.id)\"\r\n$mailboxAlias = $form.alias\r\n\r\n$permissions = @($form.permission)\r\n$blnIncludeSendAs = [System.Convert]::ToBoolean($form.blnIncludeSendAs)\r\nif($blnIncludeSendAs -eq $true) {\r\n    $permissions += \u0027sendas\u0027\r\n}\r\n$usersToAdd = $form.usersToAdd\r\n\r\n# Global variables\r\n# Outcommented as these are set from Global Variables\r\n# $ExchangeConnectionUri = \"\"\r\n# $ExchangeAdminUsername = \"\"\r\n# $ExchangeAdminPassword = \"\"\r\n# $ADsharedMailboxOU = \"\"\r\n\r\n# Fixed values\r\n$commands = @(\r\n    \"New-Mailbox\",\r\n    \"Set-Mailbox\",\r\n    \"Add-MailboxPermission\",\r\n    \"Add-ADPermission\",\r\n    \"Remove-ADPermission\",\r\n    \"Remove-RecipientPermission\"\r\n)\r\n\r\n# Enable TLS1.2\r\n[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12\r\n\r\n# Set debug logging\r\n$VerbosePreference = \"SilentlyContinue\"\r\n$InformationPreference = \"Continue\"\r\n$WarningPreference = \"Continue\"\r\n\r\n\r\n#region functions\r\nfunction GenerateStrongPassword ([Parameter(Mandatory=$true)][int]$PasswordLenght)\r\n{\r\n    Add-Type -AssemblyName System.Web\r\n    $PassComplexCheck = $false\r\n    do \r\n    {\r\n        $newPassword=[System.Web.Security.Membership]::GeneratePassword($PasswordLenght,1)\r\n        If ( ($newPassword -cmatch \"[A-Z\\p{Lu}\\s]\") `\r\n        -and ($newPassword -cmatch \"[a-z\\p{Ll}\\s]\") `\r\n        -and ($newPassword -match \"[\\d]\") `\r\n        -and ($newPassword -match \"[^\\w]\")\r\n        )\r\n        {\r\n            $PassComplexCheck=$True\r\n        }\r\n    } While ($PassComplexCheck -eq $false)\r\n    return $newPassword\r\n}\r\n#endregion functions\r\n\r\ntry{\r\n    # Create credentials\r\n    $actionMessage = \"creating credentials object\"\r\n    \r\n    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force\r\n    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)\r\n    \r\n    Write-Verbose \"Created credentials for user [$ExchangeAdminUsername]\"\r\n\r\n    # Connect to Exchange On-Premises\r\n    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell\r\n    $actionMessage = \"connecting to Exchange On-Premises\"\r\n\r\n    $sessionOptionParams = @{\r\n        SkipCACheck         = $false\r\n        SkipCNCheck         = $false\r\n        SkipRevocationCheck = $false\r\n    }\r\n\r\n    $sessionOption = New-PSSessionOption @sessionOptionParams\r\n\r\n    $sessionParams = @{\r\n        Authentication    = \u0027Default\u0027\r\n        ConfigurationName = \u0027Microsoft.Exchange\u0027\r\n        Credential        = $credential\r\n        ConnectionUri     = $ExchangeConnectionUri\r\n        SessionOption     = $sessionOption\r\n        ErrorAction       = \"Stop\"\r\n    }\r\n\r\n    $exchangeSession = New-PSSession @sessionParams\r\n    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName $commands -ErrorAction Stop\r\n\r\n    # Send initial audit log\r\n    $Log = @{\r\n        Action            = \"CreateResource\" # optional. ENUM (undefined = default) \r\n        System            = \"Exchange On-Premises\" # optional (free format text) \r\n        Message           = \"Successfully connected to Exchange using URI [$ExchangeConnectionUri]\" # required (free format text) \r\n        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $ExchangeConnectionUri # optional (free format text) \r\n        TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) \r\n    }\r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n\r\n    $password = GenerateStrongPassword(22)\r\n    \r\n    $exchangeMailboxParams = @{        \r\n        Shared = $true\r\n        Name             = $mailboxDisplayName\r\n        DisplayName      = $mailboxDisplayName\r\n        PrimarySmtpAddress = $mailboxPrimarySmtpAddress\r\n        Alias            = $mailboxAlias\r\n        UserPrincipalName= $mailboxPrimarySmtpAddress\r\n        OrganizationalUnit = $ADsharedMailboxOU        \r\n        Password = (ConvertTo-SecureString -AsPlainText $password -Force)\r\n        ErrorAction = \"Stop\"\r\n    }\r\n    \r\n    $actionMessage = \"creating Exchange On-Premises shared mailbox\"\r\n    $mailbox = New-Mailbox @exchangeMailboxParams\r\n    Write-Information \"Successfully created shared mailbox for $mailboxDisplayName.\" \r\n    \r\n    $Log = @{\r\n            Action            = \"CreateResource\" # optional. ENUM (undefined = default) \r\n            System            = \"Exchange On-Premises\" # optional (free format text) \r\n            Message           = \"Successfully created shared mailbox for $mailboxDisplayName.\" # required (free format text) \r\n            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n            TargetDisplayName = $mailboxDisplayName # optional (free format text) \r\n            TargetIdentifier  = $([string]$mailbox.Guid) # optional (free format text) \r\n        }\r\n    #send result back  \r\n    Write-Information -Tags \"Audit\" -MessageData $log    \r\n\r\n    if([string]::IsNullOrEmpty($usersToAdd)){\r\n        $usersToAdd = $null\r\n    }\r\n\r\n    if(-not [string]::IsNullOrEmpty($permissions) -and @($usersToAdd).Count -ge 1){        \r\n        # Grant users permissions to shared mailbox\r\n        $actionMessage = \"granting permission [$($permissions -Join \u0027;\u0027)] to shared mailbox to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for users\"\r\n        foreach ($userToAdd in $usersToAdd) {\r\n            foreach($permission in $permissions) {\r\n                switch ($permission) {\r\n                    \"fullaccess\" {\r\n                        # Grant Full Access to shared mailbox\r\n                        try {\r\n                            $actionMessage = \"granting permission [FullAccess] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.id))]\"\r\n\r\n                            $FullAccessPermissionSplatParams = @{\r\n                                Identity      = $mailboxPrimarySmtpAddress  # of $mailbox.UserPrincipalName\r\n                                User          = $userToAdd.Guid\r\n                                AccessRights  = \"FullAccess\"\r\n                                AutoMapping   = $AutoMapping\r\n                                ErrorAction   = \"Stop\"\r\n                                WarningAction = \"SilentlyContinue\"\r\n                            }\r\n                            $addFullAccessPermission = Add-MailboxPermission @FullAccessPermissionSplatParams\r\n\r\n                            # Send auditlog to HelloID\r\n                            $Log = @{\r\n                                Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                                System            = \"Exchange On-Premises\" # optional (free format text) \r\n                                Message           = \"Successfully granted permission [FullAccess] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))]\" # required (free format text) \r\n                                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                                TargetDisplayName = $mailboxDisplayName # optional (free format text)\r\n                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text)\r\n                            }\r\n                            Write-Information -Tags \"Audit\" -MessageData $log\r\n                        }\r\n                        catch {\r\n                            $ex = $PSItem\r\n                            if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {\r\n                                $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n                                $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n                            }\r\n                            else {\r\n                                $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n                                $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n                            }\r\n\r\n                            $Log = @{\r\n                                Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                                System            = \"Exchange On-Premises\" # optional (free format text) \r\n                                Message           = $auditMessage # required (free format text) \r\n                                IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                                TargetDisplayName = $mailboxDisplayName # optional (free format text) \r\n                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text) \r\n                            }\r\n                            Write-Information -Tags \"Audit\" -MessageData $log\r\n                            Write-Warning $warningMessage\r\n                            Write-Error $auditMessage\r\n                        }\r\n                        break\r\n                    }\r\n                    \r\n                    \"sendas\" {\r\n                        # Grant Send As to shared mailbox\r\n                        try {\r\n                            $actionMessage = \"granting permission [Send As] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))]\"\r\n\r\n                            $sendAsPermissionSplatParams = @{\r\n                                Identity     = $mailbox.DistinguishedName\r\n                                User      = $userToAdd.Guid\r\n                                AccessRights = \"ExtendedRight\"\r\n                                ExtendedRights = \"Send As\"\r\n                                Confirm      = $false\r\n                                ErrorAction  = \"Stop\"\r\n                            } \r\n                            $addSendAsPermission = Add-ADPermission @sendAsPermissionSplatParams\r\n\r\n                            # Send auditlog to HelloID\r\n                            $Log = @{\r\n                                Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                                System            = \"Exchange On-Premises\" # optional (free format text) \r\n                                Message           = \"Successfully granted permission [Send As] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))\" # required (free format text) \r\n                                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                                TargetDisplayName = $mailboxDisplayName # optional (free format text)\r\n                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text)\r\n                            }\r\n                            Write-Information -Tags \"Audit\" -MessageData $log\r\n                        }\r\n                        catch {\r\n                            $ex = $PSItem\r\n                            if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {\r\n                                $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n                                $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n                            }\r\n                            else {\r\n                                $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n                                $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n                            }\r\n\r\n                            $Log = @{\r\n                                Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                                System            = \"Exchange On-Premises\" # optional (free format text) \r\n                                Message           = $auditMessage # required (free format text) \r\n                                IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                                TargetDisplayName = $mailboxDisplayName # optional (free format text) \r\n                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text) \r\n                            }\r\n                            Write-Information -Tags \"Audit\" -MessageData $log\r\n                            Write-Warning $warningMessage\r\n                            Write-Error $auditMessage\r\n                        }\r\n                        break\r\n                    }\r\n\r\n                    \"sendonbehalf\" {\r\n                        # Grant Send on Behalf to shared mailbox\r\n                        try {\r\n                            $actionMessage = \"granting permission [Send on Behalf] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))]\"\r\n\r\n                            $SendonBehalfPermissionSplatParams = @{\r\n                                Identity            = $mailboxPrimarySmtpAddress\r\n                                GrantSendOnBehalfTo = @{ add = \"$($userToAdd.Guid)\" }\r\n                                Confirm             = $false\r\n                                ErrorAction         = \"Stop\"\r\n                            }\r\n                            $addSendonBehalfPermission = Set-Mailbox @SendonBehalfPermissionSplatParams\r\n\r\n                            # Send auditlog to HelloID\r\n                            $Log = @{\r\n                                Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                                System            = \"Exchange On-Premises\" # optional (free format text) \r\n                                Message           = \"Successfully granted permission [Send on Behalf] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))]\" # required (free format text) \r\n                                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                                TargetDisplayName = $mailboxDisplayName # optional (free format text)\r\n                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text)\r\n                            }\r\n                            Write-Information -Tags \"Audit\" -MessageData $log\r\n                        }\r\n                        catch {\r\n                            $ex = $PSItem\r\n                            if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {\r\n                                $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n                                $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)\"\r\n                            }\r\n                            else {\r\n                                $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n                                $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n                            }\r\n\r\n                            $Log = @{\r\n                                Action            = \"GrantMembership\" # optional. ENUM (undefined = default) \r\n                                System            = \"Exchange On-Premises\" # optional (free format text) \r\n                                Message           = $auditMessage # required (free format text) \r\n                                IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                                TargetDisplayName = $mailboxDisplayName # optional (free format text)\r\n                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text)\r\n                            }\r\n                            Write-Information -Tags \"Audit\" -MessageData $log\r\n                            Write-Warning $warningMessage\r\n                            Write-Error $auditMessage\r\n                        }\r\n                        break\r\n                    }\r\n                }\r\n            }\r\n        }\r\n    }\r\n    \r\n}catch {\r\n    $ex = $PSItem\r\n    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception.Message)\"\r\n    }\r\n    else {\r\n        $warningMessage = \"Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)\"\r\n        $auditMessage = \"Error $($actionMessage). Error: $($ex.Exception)\"\r\n    }\r\n\r\n    # Send error audit log to HelloID\r\n    $Log = @{\r\n        Action            = \"CreateResource\" # optional. ENUM (undefined = default) \r\n        System            = \"Exchange On-Premises\" # optional (free format text) \r\n        Message           = $auditMessage # required (free format text) \r\n        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n        TargetDisplayName = $mailbox.DisplayName # optional (free format text) \r\n        TargetIdentifier  = $mailbox.PrimarySmtpAddress # optional (free format text) \r\n    }\r\n    \r\n    Write-Information -Tags \"Audit\" -MessageData $log\r\n    Write-Warning $warningMessage\r\n    Write-Error $auditMessage\r\n}\r\nfinally {\r\n    # Disconnect from Exchange\r\n    # Docs: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/remove-pssession\r\n    if ($null -ne $exchangeSession) {\r\n        try {\r\n            $deleteExchangeSessionSplatParams = @{\r\n                Session     = $exchangeSession\r\n                Confirm     = $false\r\n                ErrorAction = \"Stop\"\r\n            }\r\n            $null = Remove-PSSession @deleteExchangeSessionSplatParams\r\n\r\n            # Send disconnect audit log\r\n            $Log = @{\r\n                Action            = \"CreateResource\" # optional. ENUM (undefined = default) \r\n                System            = \"Exchange On-Premises\" # optional (free format text) \r\n                Message           = \"Successfully disconnected from Exchange using URI [$ExchangeConnectionUri]\" # required (free format text) \r\n                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) \r\n                TargetDisplayName = $ExchangeConnectionUri # optional (free format text) \r\n                TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) \r\n            }\r\n            Write-Information -Tags \"Audit\" -MessageData $log\r\n        }\r\n        catch {\r\n            Write-Warning \"Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)\"\r\n        }\r\n    }\r\n}\r\n\r\n","runInCloud":false}
'@ 

Invoke-HelloIDDelegatedForm -DelegatedFormName $delegatedFormName -DynamicFormGuid $dynamicFormGuid -AccessGroups $delegatedFormAccessGroupGuids -Categories $delegatedFormCategoryGuids -UseFaIcon "True" -FaIcon "fa fa-envelope" -task $tmpTask -returnObject ([Ref]$delegatedFormRef) 
<# End: Delegated Form #>

