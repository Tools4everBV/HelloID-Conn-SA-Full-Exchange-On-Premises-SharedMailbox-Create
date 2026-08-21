# HelloID-Conn-SA-Full-Exchange-On-Premises-SharedMailbox-Create

| :information_source: Information                                                                                                                                                                                                                                                                                                                                                          |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

## Description

_HelloID-Conn-SA-Full-Exchange-On-Premises-SharedMailbox-Create_ is a template designed for use with HelloID Service Automation (SA) Delegated Forms. It can be imported into HelloID and customized according to your requirements.

By using this delegated form, you can create Exchange On-Premises shared mailboxes with the following capabilities:

1.  Enter and validate the display name for uniqueness
2.  Select the mail domain from available Exchange domains
3.  Enter and validate the email address prefix for uniqueness
4.  Optionally specify a custom alias (or use email prefix automatically)
5.  Select users and assign permissions (Full Access, Send As, Send on Behalf)
6.  All values are validated in real-time against Exchange On-Premises
7.  Create the shared mailbox with all specified settings and permissions

## Getting started

### Requirements

- **Exchange On-Premises Server**:<br>
  Access to an Exchange On-Premises server with remote PowerShell enabled. The server must be accessible via the Exchange Management Shell remote PowerShell endpoint.
- **Service Account**:<br>
  A service account with sufficient permissions to:
  - Create shared mailboxes in Exchange
  - Query recipients and mailboxes
  - Grant mailbox permissions (Full Access, Send As, Send on Behalf)
  - Access the specified Organizational Unit in Active Directory
- **Network Access**:<br>
  Network connectivity between the HelloID agent and the Exchange On-Premises server on the configured PowerShell endpoint (typically HTTP or HTTPS).

- **Active Directory OU**:<br>
  A designated Organizational Unit (OU) in Active Directory where the shared mailbox user objects will be created.

### Connection settings

The following user-defined variables are used by the connector.

| Setting               | Description                                                                                                                         | Mandatory |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | --------- |
| ExchangeConnectionUri | The URI to the Exchange On-Premises PowerShell endpoint (e.g., http://exchangeserver/powershell)                                    | Yes       |
| ExchangeAdminUsername | The username of the service account with Exchange admin permissions                                                                 | Yes       |
| ExchangeAdminPassword | The password of the service account                                                                                                 | Yes       |
| ADsharedMailboxOU     | The Active Directory OU where shared mailbox user objects will be created (e.g., "OU=Shared Mailboxes,OU=Users,DC=domain,DC=local") | Yes       |

## Remarks

### Multiple Datasources for Enhanced Validation

- **Specialized Checks**: The connector uses five separate datasources, each with a specific purpose:
  - `Exchange-On-Premises-Check-DisplayName-Unique`: Validates display name uniqueness
  - `Exchange-On-Premises-Check-Alias-Unique`: Validates alias uniqueness
  - `Exchange-On-Premises-Check-EmailAddress-Unique`: Validates email address uniqueness
  - `Exchange-On-Premises-Get-All-MailDomains`: Retrieves available mail domains
  - `Exchange-On-Premises-Get-All-Users`: Retrieves users for permission assignment
- This architecture provides more granular validation and better user feedback during form completion.

### Alias Behavior

- **Automatic Alias**: If no alias is specified, the email address prefix (username portion before @) is automatically used as the alias.
- **Alias Format**: The alias can only contain letters, numbers, periods, hyphens, and underscores. It must not contain spaces or domain names.
- **Single Value**: Unlike email addresses which can have multiple proxy addresses, an alias has only one value.

### Permission Management

- **Full Access**: Grants the user complete access to the mailbox, including the ability to read, send, and delete emails.
- **Send As**: Allows the user to send emails that appear to come directly from the shared mailbox.
- **Send on Behalf**: Allows the user to send emails with "on behalf of" indication showing both the sender and the mailbox.
- **AutoMapping**: Full Access permissions are configured with AutoMapping enabled by default, automatically adding the shared mailbox to the user's Outlook profile.

### Session Management

- **Command Import**: The connector explicitly imports only the required Exchange cmdlets (`New-Mailbox`, `Set-Mailbox`, `Add-MailboxPermission`, `Add-ADPermission`, `Remove-ADPermission`, `Remove-RecipientPermission`) to optimize session performance.
- **TLS 1.2**: TLS 1.2 is explicitly enabled for secure connections to Exchange On-Premises.

### Password Generation

- **Strong Passwords**: A 22-character strong password is automatically generated for the shared mailbox user object, meeting complexity requirements (uppercase, lowercase, numbers, and special characters).
- **Disabled Account**: The user account associated with the shared mailbox is created but not intended for interactive login.

## Development resources

### PowerShell Datasources

| Datasource Name                                | Description                                                            |
| ---------------------------------------------- | ---------------------------------------------------------------------- |
| Exchange-On-Premises-Check-DisplayName-Unique  | Validates if the display name is unique in Exchange                    |
| Exchange-On-Premises-Check-Alias-Unique        | Validates if the alias is unique in Exchange                           |
| Exchange-On-Premises-Check-EmailAddress-Unique | Validates if the email address is unique in Exchange                   |
| Exchange-On-Premises-Get-All-MailDomains       | Retrieves all accepted mail domains from Exchange                      |
| Exchange-On-Premises-Get-All-Users             | Retrieves all users (UserMailbox recipients) for permission assignment |

### Delegated Form Task

| Task Name                                     | Description                                                                   |
| --------------------------------------------- | ----------------------------------------------------------------------------- |
| Exchange On-Premises - Sharedmailbox - Create | Creates the shared mailbox and grants specified permissions to selected users |

### API documentation

- **Exchange PowerShell**: [Connect to Exchange servers using remote PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-servers-using-remote-powershell)
- **New-Mailbox**: [New-Mailbox cmdlet documentation](https://learn.microsoft.com/en-us/powershell/module/exchange/new-mailbox)
- **Get-Recipient**: [Get-Recipient cmdlet documentation](https://learn.microsoft.com/en-us/powershell/module/exchange/get-recipient)
- **Add-MailboxPermission**: [Add-MailboxPermission cmdlet documentation](https://learn.microsoft.com/en-us/powershell/module/exchange/add-mailboxpermission)

## Getting help

> :bulb: **Tip:**  
> _For more information on Delegated Forms, please refer to our [documentation](https://docs.helloid.com/en/service-automation/delegated-forms.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
