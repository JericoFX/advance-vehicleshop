# Changelog

## Unreleased
- Improve warehouse client validation for shop selection and empty stock messaging.
- Harden warehouse server purchase validation and refresh timer handling.
- Update English locale strings for warehouse messaging.
- Fix server test drive tracking to avoid Lua syntax errors and capture vehicle metadata in logs.
- Create persistent tables for missed finance payments and archived sales to prevent cron crashes.
- Guard cron maintenance tasks with table checks and align cleanup with existing schemas.
- Improve transport scheduling to store valid timestamps, keep trailer jobs active through restarts, and harden stock handling.
