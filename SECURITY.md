# Security policy

## Report a vulnerability privately

Do not post exploit details, credentials, private files, or a recovery journal in a public issue.

Open the repository's [Security page](https://github.com/digitalapplebee/eave/security) and choose **Report a vulnerability**. Private vulnerability reporting is enabled. GitHub sends the report privately to repository maintainers. Include the affected version, impact, minimal reproduction, and suggested mitigation. Share only the files needed to demonstrate the problem, with personal information removed.

No dedicated security email address has been designated. If the private form is unavailable, open an issue asking for a private reporting channel **without describing the vulnerability**. Wait for a maintainer to provide that channel before sharing details.

## Maintainer configuration

Keep private vulnerability reporting enabled and enable notifications for new reports. Creating this file alone does not enable GitHub's reporting form; the repository setting was configured separately. See [GitHub's setup instructions](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository).

The initial release is being prepared and no public release history is claimed. Security fixes will be assessed against the current source and latest published version once one exists. There is no guaranteed response or support schedule.

## Scope

Relevant issues include unsafe wallpaper writes/deletion, recovery-file handling, untrusted image processing, credential handling, and release integrity. Rendering limitations or unsupported wallpaper types without a security impact belong in ordinary bug reports.

Coordinate disclosure with maintainers while a fix is investigated. Do not include Apple signing certificates, passwords, API keys, or notarization profiles in reports.
