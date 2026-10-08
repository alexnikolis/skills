## Standards

<Project> is a **<scale>** app: <who uses it and how many of them>. Build to that scale. Choose the simplest thing that works and readable code over clever code. Add hardening, configuration or abstraction only when a real user needs it today.

<Two or three> risks get full care:

- **<Risk>**: <what must never go wrong, and why it matters here>.
- **<Risk>**: <...>.

Tests cover the following, and nothing more:

- one happy-path test per user-facing feature;
- one regression test per real bug fixed;
- the risks above.

Anything past that — validation edge-case tables, exact copy, styling, performance thresholds — is a cost that needs a reason. Review treats **over-building** as a defect alongside bugs: an unneeded test, validation rule, option or layer is a finding.
