# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-08-20

### Added

- Added dropdown to select from available Exchange mail domains via new datasource `Get-All-MailDomains`
- Added ability to select users and grant permissions (Full Access, Send As, Send on Behalf) to the shared mailbox via new datasource `Get-All-Users`
- Split validation into separate, specific checks:
  - `Check-DisplayName-Unique`: Validates display name uniqueness in Exchange
  - `Check-Alias-Unique`: Validates alias uniqueness in Exchange
  - `Check-EmailAddress-Unique`: Validates email address uniqueness in Exchange
- Enabled TLS 1.2 for secure connections
- Added selective property selection in datasources to limit memory usage and speed up processing
- Added option to automatically include Send As permission when granting Full Access
- Added github workflows

### Changed

- Refactored from single combined datasource to five specialized datasources for better maintainability and clarity
- Changed from Active Directory-based validation to Exchange-based validation using `Get-Recipient` cmdlet
- Improved error handling with detailed try-catch blocks and better error messages
- Enhanced audit logging with more detailed information and consistent formatting
- Improved Exchange session management with explicit command imports
- Standardized file naming with consistent prefix `exchange-on-premises-sharedmailbox-create`
- Changed from "Exchange on-premise" to "Exchange On-Premises" for consistency

### Fixed

- Corrected session option parameters for Exchange connection (SkipCACheck, SkipCNCheck, SkipRevocationCheck)
- Maintained strong password generation with improved code structure

## [1.0.2] - 2022-08-22

### Added

- Added version number and updated code for SA-agent and auditlogging

## [1.0.1] - 2021-11-16

### Added

- Added version number and updated all-in-one script

## [1.0.0] - 2021-04-29

Initial release of HelloID-Conn-SA-Full-Exchange-On-Premises-SharedMailbox-Create.

### Added

- Initial release for creating Exchange On-Premises Shared Mailboxes
