import '../models/wstg_test.dart';

/// The OWASP Web Security Testing Guide (WSTG) test catalog — the offline,
/// always-on standard test list for the Informatieveiligheid module's
/// `checklist` slide ("Uitvoering testen conform standaard", PENTEST_MIAUW
/// §3.2). Like [CweCatalog], this is a **curated, bundled, in-repo dataset** —
/// no asset wiring, no network — so a tester can populate a checklist with the
/// full standard in one click.
///
/// The pinned [version] is the **stable released** WSTG version (v4.2, 2020),
/// so a report cites a fixed, citeable standard rather than a moving branch.
/// The ids and titles are the canonical WSTG identifiers; every entry maps back
/// to owasp.org's guide.
///
/// **Third-party content under CC-BY-SA-4.0.** The ids, titles and categories are
/// the OWASP Web Security Testing Guide v4.2 checklist index, © the OWASP
/// Foundation and its contributors, reproduced here with attribution and
/// share-alike; the guide's substance (how to test) is deliberately not bundled.
/// The terms travel with this dataset — `docs/LICENSE_COMPLIANCE.md` is the
/// authority (PENTEST_MIAUW §15 is a design-time note). Bundling another
/// standard's content means adding it to that table in the same commit.
class WstgCatalog {
  WstgCatalog._();

  static final WstgCatalog instance = WstgCatalog._();

  /// The released standard version this catalog reflects (e.g. `4.2`).
  String get version => wstgVersion;

  /// The label written as the checklist's standard heading, e.g.
  /// `OWASP WSTG v4.2` — carries the [version] so it shows in the slide.
  String get standardLabel => wstgStandardLabel;

  /// All tests, in canonical WSTG order (category, then number).
  List<WstgTest> get tests => _tests;
}

/// The stable released WSTG version bundled here.
const wstgVersion = '4.2';

/// The versioned standard label used as the checklist heading default.
const wstgStandardLabel = 'OWASP WSTG v$wstgVersion';

/// The WSTG v4.2 checklist (97 tests across 12 categories). Sub-tests (e.g. the
/// SQL-dialect pages under WSTG-INPV-05) and section intros are intentionally
/// folded into their parent test — this is the checklist granularity, matching
/// the official spreadsheet.
const List<WstgTest> _tests = [
  // Information Gathering (WSTG-INFO)
  WstgTest(
    id: 'WSTG-INFO-01',
    title:
        'Conduct Search Engine Discovery Reconnaissance for Information Leakage',
    category: 'Information Gathering',
  ),
  WstgTest(
    id: 'WSTG-INFO-02',
    title: 'Fingerprint Web Server',
    category: 'Information Gathering',
  ),
  WstgTest(
    id: 'WSTG-INFO-03',
    title: 'Review Webserver Metafiles for Information Leakage',
    category: 'Information Gathering',
  ),
  WstgTest(
    id: 'WSTG-INFO-04',
    title: 'Enumerate Applications on Webserver',
    category: 'Information Gathering',
  ),
  WstgTest(
    id: 'WSTG-INFO-05',
    title: 'Review Webpage Content for Information Leakage',
    category: 'Information Gathering',
  ),
  WstgTest(
    id: 'WSTG-INFO-06',
    title: 'Identify Application Entry Points',
    category: 'Information Gathering',
  ),
  WstgTest(
    id: 'WSTG-INFO-07',
    title: 'Map Execution Paths Through Application',
    category: 'Information Gathering',
  ),
  WstgTest(
    id: 'WSTG-INFO-08',
    title: 'Fingerprint Web Application Framework',
    category: 'Information Gathering',
  ),
  WstgTest(
    id: 'WSTG-INFO-09',
    title: 'Fingerprint Web Application',
    category: 'Information Gathering',
  ),
  WstgTest(
    id: 'WSTG-INFO-10',
    title: 'Map Application Architecture',
    category: 'Information Gathering',
  ),
  // Configuration and Deployment Management Testing (WSTG-CONF)
  WstgTest(
    id: 'WSTG-CONF-01',
    title: 'Test Network Infrastructure Configuration',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-02',
    title: 'Test Application Platform Configuration',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-03',
    title: 'Test File Extensions Handling for Sensitive Information',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-04',
    title: 'Review Old Backup and Unreferenced Files for Sensitive Information',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-05',
    title: 'Enumerate Infrastructure and Application Admin Interfaces',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-06',
    title: 'Test HTTP Methods',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-07',
    title: 'Test HTTP Strict Transport Security',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-08',
    title: 'Test RIA Cross Domain Policy',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-09',
    title: 'Test File Permission',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-10',
    title: 'Test for Subdomain Takeover',
    category: 'Configuration and Deployment Management Testing',
  ),
  WstgTest(
    id: 'WSTG-CONF-11',
    title: 'Test Cloud Storage',
    category: 'Configuration and Deployment Management Testing',
  ),
  // Identity Management Testing (WSTG-IDNT)
  WstgTest(
    id: 'WSTG-IDNT-01',
    title: 'Test Role Definitions',
    category: 'Identity Management Testing',
  ),
  WstgTest(
    id: 'WSTG-IDNT-02',
    title: 'Test User Registration Process',
    category: 'Identity Management Testing',
  ),
  WstgTest(
    id: 'WSTG-IDNT-03',
    title: 'Test Account Provisioning Process',
    category: 'Identity Management Testing',
  ),
  WstgTest(
    id: 'WSTG-IDNT-04',
    title: 'Testing for Account Enumeration and Guessable User Account',
    category: 'Identity Management Testing',
  ),
  WstgTest(
    id: 'WSTG-IDNT-05',
    title: 'Testing for Weak or Unenforced Username Policy',
    category: 'Identity Management Testing',
  ),
  // Authentication Testing (WSTG-ATHN)
  WstgTest(
    id: 'WSTG-ATHN-01',
    title: 'Testing for Credentials Transported over an Encrypted Channel',
    category: 'Authentication Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHN-02',
    title: 'Testing for Default Credentials',
    category: 'Authentication Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHN-03',
    title: 'Testing for Weak Lock Out Mechanism',
    category: 'Authentication Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHN-04',
    title: 'Testing for Bypassing Authentication Schema',
    category: 'Authentication Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHN-05',
    title: 'Testing for Vulnerable Remember Password',
    category: 'Authentication Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHN-06',
    title: 'Testing for Browser Cache Weaknesses',
    category: 'Authentication Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHN-07',
    title: 'Testing for Weak Password Policy',
    category: 'Authentication Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHN-08',
    title: 'Testing for Weak Security Question Answer',
    category: 'Authentication Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHN-09',
    title: 'Testing for Weak Password Change or Reset Functionalities',
    category: 'Authentication Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHN-10',
    title: 'Testing for Weaker Authentication in Alternative Channel',
    category: 'Authentication Testing',
  ),
  // Authorization Testing (WSTG-ATHZ)
  WstgTest(
    id: 'WSTG-ATHZ-01',
    title: 'Testing Directory Traversal File Include',
    category: 'Authorization Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHZ-02',
    title: 'Testing for Bypassing Authorization Schema',
    category: 'Authorization Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHZ-03',
    title: 'Testing for Privilege Escalation',
    category: 'Authorization Testing',
  ),
  WstgTest(
    id: 'WSTG-ATHZ-04',
    title: 'Testing for Insecure Direct Object References',
    category: 'Authorization Testing',
  ),
  // Session Management Testing (WSTG-SESS)
  WstgTest(
    id: 'WSTG-SESS-01',
    title: 'Testing for Session Management Schema',
    category: 'Session Management Testing',
  ),
  WstgTest(
    id: 'WSTG-SESS-02',
    title: 'Testing for Cookies Attributes',
    category: 'Session Management Testing',
  ),
  WstgTest(
    id: 'WSTG-SESS-03',
    title: 'Testing for Session Fixation',
    category: 'Session Management Testing',
  ),
  WstgTest(
    id: 'WSTG-SESS-04',
    title: 'Testing for Exposed Session Variables',
    category: 'Session Management Testing',
  ),
  WstgTest(
    id: 'WSTG-SESS-05',
    title: 'Testing for Cross Site Request Forgery',
    category: 'Session Management Testing',
  ),
  WstgTest(
    id: 'WSTG-SESS-06',
    title: 'Testing for Logout Functionality',
    category: 'Session Management Testing',
  ),
  WstgTest(
    id: 'WSTG-SESS-07',
    title: 'Testing Session Timeout',
    category: 'Session Management Testing',
  ),
  WstgTest(
    id: 'WSTG-SESS-08',
    title: 'Testing for Session Puzzling',
    category: 'Session Management Testing',
  ),
  WstgTest(
    id: 'WSTG-SESS-09',
    title: 'Testing for Session Hijacking',
    category: 'Session Management Testing',
  ),
  // Input Validation Testing (WSTG-INPV)
  WstgTest(
    id: 'WSTG-INPV-01',
    title: 'Testing for Reflected Cross Site Scripting',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-02',
    title: 'Testing for Stored Cross Site Scripting',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-03',
    title: 'Testing for HTTP Verb Tampering',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-04',
    title: 'Testing for HTTP Parameter Pollution',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-05',
    title: 'Testing for SQL Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-06',
    title: 'Testing for LDAP Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-07',
    title: 'Testing for XML Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-08',
    title: 'Testing for SSI Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-09',
    title: 'Testing for XPath Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-10',
    title: 'Testing for IMAP SMTP Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-11',
    title: 'Testing for Code Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-12',
    title: 'Testing for Command Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-13',
    title: 'Testing for Format String Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-14',
    title: 'Testing for Incubated Vulnerability',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-15',
    title: 'Testing for HTTP Splitting Smuggling',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-16',
    title: 'Testing for HTTP Incoming Requests',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-17',
    title: 'Testing for Host Header Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-18',
    title: 'Testing for Server-side Template Injection',
    category: 'Input Validation Testing',
  ),
  WstgTest(
    id: 'WSTG-INPV-19',
    title: 'Testing for Server-Side Request Forgery',
    category: 'Input Validation Testing',
  ),
  // Error Handling (WSTG-ERRH)
  WstgTest(
    id: 'WSTG-ERRH-01',
    title: 'Testing for Improper Error Handling',
    category: 'Error Handling',
  ),
  WstgTest(
    id: 'WSTG-ERRH-02',
    title: 'Testing for Stack Traces',
    category: 'Error Handling',
  ),
  // Weak Cryptography (WSTG-CRYP)
  WstgTest(
    id: 'WSTG-CRYP-01',
    title: 'Testing for Weak Transport Layer Security',
    category: 'Weak Cryptography',
  ),
  WstgTest(
    id: 'WSTG-CRYP-02',
    title: 'Testing for Padding Oracle',
    category: 'Weak Cryptography',
  ),
  WstgTest(
    id: 'WSTG-CRYP-03',
    title: 'Testing for Sensitive Information Sent via Unencrypted Channels',
    category: 'Weak Cryptography',
  ),
  WstgTest(
    id: 'WSTG-CRYP-04',
    title: 'Testing for Weak Encryption',
    category: 'Weak Cryptography',
  ),
  // Business Logic Testing (WSTG-BUSL)
  WstgTest(
    id: 'WSTG-BUSL-01',
    title: 'Test Business Logic Data Validation',
    category: 'Business Logic Testing',
  ),
  WstgTest(
    id: 'WSTG-BUSL-02',
    title: 'Test Ability to Forge Requests',
    category: 'Business Logic Testing',
  ),
  WstgTest(
    id: 'WSTG-BUSL-03',
    title: 'Test Integrity Checks',
    category: 'Business Logic Testing',
  ),
  WstgTest(
    id: 'WSTG-BUSL-04',
    title: 'Test for Process Timing',
    category: 'Business Logic Testing',
  ),
  WstgTest(
    id: 'WSTG-BUSL-05',
    title: 'Test Number of Times a Function Can Be Used Limits',
    category: 'Business Logic Testing',
  ),
  WstgTest(
    id: 'WSTG-BUSL-06',
    title: 'Testing for the Circumvention of Work Flows',
    category: 'Business Logic Testing',
  ),
  WstgTest(
    id: 'WSTG-BUSL-07',
    title: 'Test Defenses Against Application Misuse',
    category: 'Business Logic Testing',
  ),
  WstgTest(
    id: 'WSTG-BUSL-08',
    title: 'Test Upload of Unexpected File Types',
    category: 'Business Logic Testing',
  ),
  WstgTest(
    id: 'WSTG-BUSL-09',
    title: 'Test Upload of Malicious Files',
    category: 'Business Logic Testing',
  ),
  // Client-side Testing (WSTG-CLNT)
  WstgTest(
    id: 'WSTG-CLNT-01',
    title: 'Testing for DOM-based Cross Site Scripting',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-02',
    title: 'Testing for JavaScript Execution',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-03',
    title: 'Testing for HTML Injection',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-04',
    title: 'Testing for Client-side URL Redirect',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-05',
    title: 'Testing for CSS Injection',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-06',
    title: 'Testing for Client-side Resource Manipulation',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-07',
    title: 'Testing Cross Origin Resource Sharing',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-08',
    title: 'Testing for Cross Site Flashing',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-09',
    title: 'Testing for Clickjacking',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-10',
    title: 'Testing WebSockets',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-11',
    title: 'Testing Web Messaging',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-12',
    title: 'Testing Browser Storage',
    category: 'Client-side Testing',
  ),
  WstgTest(
    id: 'WSTG-CLNT-13',
    title: 'Testing for Cross Site Script Inclusion',
    category: 'Client-side Testing',
  ),
  // API Testing (WSTG-APIT)
  WstgTest(
    id: 'WSTG-APIT-01',
    title: 'Testing GraphQL',
    category: 'API Testing',
  ),
];
