# static variable
$AutoMapping = $True

# variables configured in form
$mailboxDisplayName = $form.displayName
$mailboxPrimarySmtpAddress = "$($form.mailPrefix)@$($form.mailDomain.id)"
$mailboxAlias = $form.alias

$permissions = @($form.permission)
$blnIncludeSendAs = [System.Convert]::ToBoolean($form.blnIncludeSendAs)
if($blnIncludeSendAs -eq $true) {
    $permissions += 'sendas'
}
$usersToAdd = $form.usersToAdd

# Global variables
# Outcommented as these are set from Global Variables
# $ExchangeConnectionUri = ""
# $ExchangeAdminUsername = ""
# $ExchangeAdminPassword = ""
# $ADsharedMailboxOU = ""

# Fixed values
$commands = @(
    "New-Mailbox",
    "Set-Mailbox",
    "Add-MailboxPermission",
    "Add-ADPermission",
    "Remove-ADPermission",
    "Remove-RecipientPermission"
)

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"


#region functions
function GenerateStrongPassword ([Parameter(Mandatory=$true)][int]$PasswordLenght)
{
    Add-Type -AssemblyName System.Web
    $PassComplexCheck = $false
    do 
    {
        $newPassword=[System.Web.Security.Membership]::GeneratePassword($PasswordLenght,1)
        If ( ($newPassword -cmatch "[A-Z\p{Lu}\s]") `
        -and ($newPassword -cmatch "[a-z\p{Ll}\s]") `
        -and ($newPassword -match "[\d]") `
        -and ($newPassword -match "[^\w]")
        )
        {
            $PassComplexCheck=$True
        }
    } While ($PassComplexCheck -eq $false)
    return $newPassword
}
#endregion functions

try{
    # Create credentials
    $actionMessage = "creating credentials object"
    
    $securePassword = ConvertTo-SecureString -String $ExchangeAdminPassword -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($ExchangeAdminUsername, $securePassword)
    
    Write-Verbose "Created credentials for user [$ExchangeAdminUsername]"

    # Connect to Exchange On-Premises
    # Docs: https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell
    $actionMessage = "connecting to Exchange On-Premises"

    $sessionOptionParams = @{
        SkipCACheck         = $false
        SkipCNCheck         = $false
        SkipRevocationCheck = $false
    }

    $sessionOption = New-PSSessionOption @sessionOptionParams

    $sessionParams = @{
        Authentication    = 'Default'
        ConfigurationName = 'Microsoft.Exchange'
        Credential        = $credential
        ConnectionUri     = $ExchangeConnectionUri
        SessionOption     = $sessionOption
        ErrorAction       = "Stop"
    }

    $exchangeSession = New-PSSession @sessionParams
    $null = Import-PSSession -Session $exchangeSession -DisableNameChecking -AllowClobber -CommandName $commands -ErrorAction Stop

    # Send initial audit log
    $Log = @{
        Action            = "CreateResource" # optional. ENUM (undefined = default) 
        System            = "Exchange On-Premises" # optional (free format text) 
        Message           = "Successfully connected to Exchange using URI [$ExchangeConnectionUri]" # required (free format text) 
        IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $ExchangeConnectionUri # optional (free format text) 
        TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) 
    }
    Write-Information -Tags "Audit" -MessageData $log

    $password = GenerateStrongPassword(22)
    
    $exchangeMailboxParams = @{        
        Shared = $true
        Name             = $mailboxDisplayName
        DisplayName      = $mailboxDisplayName
        PrimarySmtpAddress = $mailboxPrimarySmtpAddress
        Alias            = $mailboxAlias
        UserPrincipalName= $mailboxPrimarySmtpAddress
        OrganizationalUnit = $ADsharedMailboxOU        
        Password = (ConvertTo-SecureString -AsPlainText $password -Force)
        ErrorAction = "Stop"
    }
    
    $actionMessage = "creating Exchange On-Premises shared mailbox"
    $mailbox = New-Mailbox @exchangeMailboxParams
    Write-Information "Successfully created shared mailbox for $mailboxDisplayName." 
    
    $Log = @{
            Action            = "CreateResource" # optional. ENUM (undefined = default) 
            System            = "Exchange On-Premises" # optional (free format text) 
            Message           = "Successfully created shared mailbox for $mailboxDisplayName." # required (free format text) 
            IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
            TargetDisplayName = $mailboxDisplayName # optional (free format text) 
            TargetIdentifier  = $([string]$mailbox.Guid) # optional (free format text) 
        }
    #send result back  
    Write-Information -Tags "Audit" -MessageData $log    

    if([string]::IsNullOrEmpty($usersToAdd)){
        $usersToAdd = $null
    }

    if(-not [string]::IsNullOrEmpty($permissions) -and @($usersToAdd).Count -ge 1){        
        # Grant users permissions to shared mailbox
        $actionMessage = "granting permission [$($permissions -Join ';')] to shared mailbox to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for users"
        foreach ($userToAdd in $usersToAdd) {
            foreach($permission in $permissions) {
                switch ($permission) {
                    "fullaccess" {
                        # Grant Full Access to shared mailbox
                        try {
                            $actionMessage = "granting permission [FullAccess] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.id))]"

                            $FullAccessPermissionSplatParams = @{
                                Identity      = $mailboxPrimarySmtpAddress  # of $mailbox.UserPrincipalName
                                User          = $userToAdd.Guid
                                AccessRights  = "FullAccess"
                                AutoMapping   = $AutoMapping
                                ErrorAction   = "Stop"
                                WarningAction = "SilentlyContinue"
                            }
                            $addFullAccessPermission = Add-MailboxPermission @FullAccessPermissionSplatParams

                            # Send auditlog to HelloID
                            $Log = @{
                                Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                                System            = "Exchange On-Premises" # optional (free format text) 
                                Message           = "Successfully granted permission [FullAccess] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))]" # required (free format text) 
                                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                                TargetDisplayName = $mailboxDisplayName # optional (free format text)
                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text)
                            }
                            Write-Information -Tags "Audit" -MessageData $log
                        }
                        catch {
                            $ex = $PSItem
                            if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {
                                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)"
                                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)"
                            }
                            else {
                                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
                                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
                            }

                            $Log = @{
                                Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                                System            = "Exchange On-Premises" # optional (free format text) 
                                Message           = $auditMessage # required (free format text) 
                                IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                                TargetDisplayName = $mailboxDisplayName # optional (free format text) 
                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text) 
                            }
                            Write-Information -Tags "Audit" -MessageData $log
                            Write-Warning $warningMessage
                            Write-Error $auditMessage
                        }
                        break
                    }
                    
                    "sendas" {
                        # Grant Send As to shared mailbox
                        try {
                            $actionMessage = "granting permission [Send As] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))]"

                            $sendAsPermissionSplatParams = @{
                                Identity     = $mailbox.DistinguishedName
                                User      = $userToAdd.Guid
                                AccessRights = "ExtendedRight"
                                ExtendedRights = "Send As"
                                Confirm      = $false
                                ErrorAction  = "Stop"
                            } 
                            $addSendAsPermission = Add-ADPermission @sendAsPermissionSplatParams

                            # Send auditlog to HelloID
                            $Log = @{
                                Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                                System            = "Exchange On-Premises" # optional (free format text) 
                                Message           = "Successfully granted permission [Send As] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))" # required (free format text) 
                                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                                TargetDisplayName = $mailboxDisplayName # optional (free format text)
                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text)
                            }
                            Write-Information -Tags "Audit" -MessageData $log
                        }
                        catch {
                            $ex = $PSItem
                            if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {
                                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)"
                                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)"
                            }
                            else {
                                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
                                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
                            }

                            $Log = @{
                                Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                                System            = "Exchange On-Premises" # optional (free format text) 
                                Message           = $auditMessage # required (free format text) 
                                IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                                TargetDisplayName = $mailboxDisplayName # optional (free format text) 
                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text) 
                            }
                            Write-Information -Tags "Audit" -MessageData $log
                            Write-Warning $warningMessage
                            Write-Error $auditMessage
                        }
                        break
                    }

                    "sendonbehalf" {
                        # Grant Send on Behalf to shared mailbox
                        try {
                            $actionMessage = "granting permission [Send on Behalf] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))]"

                            $SendonBehalfPermissionSplatParams = @{
                                Identity            = $mailboxPrimarySmtpAddress
                                GrantSendOnBehalfTo = @{ add = "$($userToAdd.Guid)" }
                                Confirm             = $false
                                ErrorAction         = "Stop"
                            }
                            $addSendonBehalfPermission = Set-Mailbox @SendonBehalfPermissionSplatParams

                            # Send auditlog to HelloID
                            $Log = @{
                                Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                                System            = "Exchange On-Premises" # optional (free format text) 
                                Message           = "Successfully granted permission [Send on Behalf] to mailbox [$($mailboxDisplayName) ($($mailboxPrimarySmtpAddress))] for user [$($userToAdd.userPrincipalName) ($($userToAdd.Guid))]" # required (free format text) 
                                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                                TargetDisplayName = $mailboxDisplayName # optional (free format text)
                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text)
                            }
                            Write-Information -Tags "Audit" -MessageData $log
                        }
                        catch {
                            $ex = $PSItem
                            if (-not [string]::IsNullOrEmpty($ex.Exception.Data.RemoteException.Message)) {
                                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Data.RemoteException.Message)"
                                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Data.RemoteException.Message)"
                            }
                            else {
                                $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
                                $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
                            }

                            $Log = @{
                                Action            = "GrantMembership" # optional. ENUM (undefined = default) 
                                System            = "Exchange On-Premises" # optional (free format text) 
                                Message           = $auditMessage # required (free format text) 
                                IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                                TargetDisplayName = $mailboxDisplayName # optional (free format text)
                                TargetIdentifier  = $mailboxPrimarySmtpAddress # optional (free format text)
                            }
                            Write-Information -Tags "Audit" -MessageData $log
                            Write-Warning $warningMessage
                            Write-Error $auditMessage
                        }
                        break
                    }
                }
            }
        }
    }
    
}catch {
    $ex = $PSItem
    if (-not [string]::IsNullOrEmpty($ex.Exception.Message)) {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
    }
    else {
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception)"
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception)"
    }

    # Send error audit log to HelloID
    $Log = @{
        Action            = "CreateResource" # optional. ENUM (undefined = default) 
        System            = "Exchange On-Premises" # optional (free format text) 
        Message           = $auditMessage # required (free format text) 
        IsError           = $true # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
        TargetDisplayName = $mailbox.DisplayName # optional (free format text) 
        TargetIdentifier  = $mailbox.PrimarySmtpAddress # optional (free format text) 
    }
    
    Write-Information -Tags "Audit" -MessageData $log
    Write-Warning $warningMessage
    Write-Error $auditMessage
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

            # Send disconnect audit log
            $Log = @{
                Action            = "CreateResource" # optional. ENUM (undefined = default) 
                System            = "Exchange On-Premises" # optional (free format text) 
                Message           = "Successfully disconnected from Exchange using URI [$ExchangeConnectionUri]" # required (free format text) 
                IsError           = $false # optional. Elastic reporting purposes only. (default = $false. $true = Executed action returned an error) 
                TargetDisplayName = $ExchangeConnectionUri # optional (free format text) 
                TargetIdentifier  = $([string]$exchangeSession.InstanceId) # optional (free format text) 
            }
            Write-Information -Tags "Audit" -MessageData $log
        }
        catch {
            Write-Warning "Failed to disconnect from Exchange using URI [$ExchangeConnectionUri]. Error: $($_.Exception.Message)"
        }
    }
}


