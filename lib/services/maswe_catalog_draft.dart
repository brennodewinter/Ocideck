// GEGENEREERD door tool/build_maswe_catalog.dart — niet met de
// hand bijwerken. Zie dat bestand voor de bron en de regels.
//
// OWASP MASWE, © de OWASP Foundation, CC-BY-SA-4.0.
part of 'maswe_catalog.dart';

/// De MASWE-zwakheden die nog niet uitgeschreven zijn (89).
const List<MasweWeakness> _draftWeaknesses = [
  MasweWeakness(
    id: 'MASWE-0002',
    title:
        'Sensitive Data Stored With Insufficient Access Restrictions in Internal Locations',
    category: 'MASVS-STORAGE',
    platforms: ['android'],
    cweIds: [200, 284, 732, 922],
    isPlaceholder: true,
    description:
        'Sensitive data may be stored in internal locations without ensuring exclusive app access (e.g. by using the wrong file permissions) and may be accessible to other apps.',
  ),
  MasweWeakness(
    id: 'MASWE-0003',
    title: 'Backup Unencrypted',
    category: 'MASVS-STORAGE',
    platforms: ['android'],
    cweIds: [313],
    isPlaceholder: true,
    description:
        'The app may not encrypt sensitive data in backups, which may compromise data confidentiality.',
  ),
  MasweWeakness(
    id: 'MASWE-0008',
    title: 'Missing Device Secure Lock Verification Implementation',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [],
    isPlaceholder: true,
    description:
        'The app may not check for a secure device lock (e.g. device passcode) and may allow for unauthorized access to sensitive data. On iOS enforcing device lock security (i.e., ensuring a passcode is set) has an additional benefit which is that it is tightly coupled with data encryption, assuming the app leverages the correct data protection APIs.',
  ),
  MasweWeakness(
    id: 'MASWE-0010',
    title: 'Improper Cryptographic Key Derivation',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [326, 327],
    isPlaceholder: true,
    description: 'e.g. PBKDF2 with insufficient iterations, lack of salt, etc.',
  ),
  MasweWeakness(
    id: 'MASWE-0011',
    title: 'Cryptographic Key Rotation Not Implemented',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [262, 324],
    isPlaceholder: true,
    description:
        'Key rotation is a best practice to limit the impact of a key compromise. It is especially important for long-lived keys such as asymmetric keys.',
  ),
  MasweWeakness(
    id: 'MASWE-0012',
    title: 'Insecure or Wrong Usage of Cryptographic Key',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [323],
    isPlaceholder: true,
    description:
        'According to NIST.SP.800-57pt1r5, in general, a single key shall be used for only one purpose (e.g., encryption, integrity, authentication, key wrapping, random bit generation, or digital signatures)',
  ),
  MasweWeakness(
    id: 'MASWE-0015',
    title: 'Deprecated Android KeyStore Implementations',
    category: 'MASVS-CRYPTO',
    platforms: ['android'],
    cweIds: [327, 477, 522],
    isPlaceholder: true,
    description: 'Avoid deprecated implementations such as BKS',
  ),
  MasweWeakness(
    id: 'MASWE-0016',
    title: 'Unsafe Handling of Imported Cryptographic Keys',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [322],
    isPlaceholder: true,
    description:
        'Importing keys without validating their origin or integrity, or using insecure custom key exchange protocols, can inadvertently introduce malicious or compromised keys into the app environment.',
  ),
  MasweWeakness(
    id: 'MASWE-0017',
    title: 'Cryptographic Keys Not Properly Protected on Export',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [522],
    isPlaceholder: true,
    description:
        'Before exporting, keys should be "wrapped" or encrypted with another key. This process ensures that the cryptographic key is protected during and after export. This is true even if the key is sent over a secure channel.',
  ),
  MasweWeakness(
    id: 'MASWE-0018',
    title: 'Cryptographic Keys Access Not Restricted',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [284],
    isPlaceholder: true,
    description:
        'Ensuring that cryptographic keys are accessible only under strict conditions, such as when the device is unlocked by an authenticated user, within secure application contexts, bound to the current device, or for limited periods of time, is critical to maintaining the confidentiality and integrity of encrypted data.',
  ),
  MasweWeakness(
    id: 'MASWE-0021',
    title: 'Improper Hashing',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [328],
    isPlaceholder: true,
    description:
        'Utilizing broken hashing algorithms such as MD5 and SHA1 in a security sensitive context may compromise data integrity and authenticity.',
  ),
  MasweWeakness(
    id: 'MASWE-0022',
    title: 'Predictable Initialization Vectors (IVs)',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [329],
    isPlaceholder: true,
    description:
        'The use of predictable IVs (hardcoded, null, reused) in a security sensitive context can weaken data encryption strength and potentially compromise confidentiality.',
  ),
  MasweWeakness(
    id: 'MASWE-0024',
    title: 'Improper Use of Message Authentication Code (MAC)',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [327, 807, 915],
    isPlaceholder: true,
    description:
        'Improper use of MACs in security sensitive contexts affecting data integrity.',
  ),
  MasweWeakness(
    id: 'MASWE-0025',
    title: 'Improper Generation of Cryptographic Signatures',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [327],
    isPlaceholder: true,
    description:
        'The use of algorithms with insufficient strength for signatures such as SHA1withRSA, etc. in a security-sensitive context should be avoided to ensure the integrity and authenticity of the data.',
  ),
  MasweWeakness(
    id: 'MASWE-0026',
    title: 'Improper Verification of Cryptographic Signature',
    category: 'MASVS-CRYPTO',
    platforms: ['android', 'ios'],
    cweIds: [347],
    isPlaceholder: true,
    description:
        'Cryptographic signature verification should be performed properly to ensure the integrity and authenticity of the data.',
  ),
  MasweWeakness(
    id: 'MASWE-0028',
    title: 'MFA Implementation Best Practices Not Followed',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [287],
    isPlaceholder: true,
    description: 'e.g. not using auto-fill',
  ),
  MasweWeakness(
    id: 'MASWE-0029',
    title: 'Step-Up Authentication Not Implemented After Login',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [306],
    isPlaceholder: true,
    description:
        'An example of step-up authentication is when a user is logged into their bank account (with or without MFA) and requests an action that is considered sensitive, such as the transfer of a large sum of money. In such cases, the user will be required to provide additional information to authenticate their identity (e.g. using MFA) and ensure only the legitimate user is requesting the action.',
  ),
  MasweWeakness(
    id: 'MASWE-0030',
    title: 'Re-Authenticates Not Triggered On Contextual State Changes',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [285, 287],
    isPlaceholder: true,
    description:
        'Re-authentication means forcing a new login after e.g. timeout, changing state from running in the background to running in the foreground, remarkable changes in a user\'s location, profile, etc.',
  ),
  MasweWeakness(
    id: 'MASWE-0031',
    title: 'Insecure use of Android Protected Confirmation',
    category: 'MASVS-AUTH',
    platforms: ['android'],
    cweIds: [287],
    isPlaceholder: true,
    description:
        'Android Protected Confirmation doesn\'t provide a secure information channel for the user. Don\'t use it to display sensitive information that you wouldn\'t ordinarily show on the user\'s device.',
  ),
  MasweWeakness(
    id: 'MASWE-0032',
    title: 'Platform-provided Authentication APIs Not Used',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [287],
    isPlaceholder: true,
    description:
        'AKA don\'t roll your own authentication security. Platform-provided APIs are designed and implemented by experts who have deep knowledge of the platform\'s security features and considerations. These APIs often incorporate security best practices and are regularly updated to address new threats and vulnerabilities. Not using platform-provided authentication APIs in mobile apps can result in security vulnerabilities, inconsistent user experience, missed integration opportunities, and increased development and maintenance efforts.',
  ),
  MasweWeakness(
    id: 'MASWE-0033',
    title:
        'Authentication or Authorization Protocol Security Best Practices Not Followed',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [285, 287],
    isPlaceholder: true,
    description:
        'For example, when using oauth2, the app does not use PKCE, etc. See RFC-8252. Focus on client-side best practices.',
  ),
  MasweWeakness(
    id: 'MASWE-0035',
    title: 'Passwordless Authentication Not Implemented',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [287],
    isPlaceholder: true,
    description:
        'there\'s no use of passwordless authentication mechanisms e.g. passkeys',
  ),
  MasweWeakness(
    id: 'MASWE-0036',
    title: 'Authentication Material Stored Unencrypted on the Device',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [312],
    isPlaceholder: true,
    description:
        'General authentication material management best practices. Note that API keys are covered separately.',
  ),
  MasweWeakness(
    id: 'MASWE-0037',
    title: 'Authentication Material Sent over Insecure Connections',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [319],
    isPlaceholder: true,
    description: 'General authentication best practice.',
  ),
  MasweWeakness(
    id: 'MASWE-0038',
    title: 'Authentication Tokens Not Validated',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [287],
    isPlaceholder: true,
    description: 'e.g. oauth2/jwt client-side checks',
  ),
  MasweWeakness(
    id: 'MASWE-0039',
    title: 'Shared Web Credentials and Website-association Not Implemented',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [287],
    isPlaceholder: true,
    description:
        'Best practice for sharing credentials between apps and their website counterparts.',
  ),
  MasweWeakness(
    id: 'MASWE-0040',
    title: 'Insecure Authentication in WebViews',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [287],
    isPlaceholder: true,
    description:
        'e.g. via WebView.getHttpAuthUsernamePassword / WebViewClient.onReceivedHttpAuthRequest',
  ),
  MasweWeakness(
    id: 'MASWE-0041',
    title: 'Authentication Enforced Only Locally Instead of on the Server-side',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [603, 287],
    isPlaceholder: true,
    description:
        'General authentication best practice. Only for apps with connection. The app performs local authentication involving the remote endpoint and according to the platform best practices.',
  ),
  MasweWeakness(
    id: 'MASWE-0042',
    title: 'Authorization Enforced Only Locally Instead of on the Server-side',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [285, 602, 863],
    isPlaceholder: true,
    description:
        'General authentication best practice. Only for apps with connection.',
  ),
  MasweWeakness(
    id: 'MASWE-0043',
    title: 'App Custom PIN Not Bound to Platform KeyStore',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [922, 326, 312],
    isPlaceholder: true,
    description:
        'It\'s better to use the OS Local Auth / bind to a key stored in the platform KeyStore. Consider new title App Custom Password Not Bound to Platform KeyStore where password could be password or PIN.',
  ),
  MasweWeakness(
    id: 'MASWE-0044',
    title: 'Biometric Authentication Can Be Bypassed',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [287],
    isPlaceholder: true,
    description:
        'It should be based on unlock platform KeyStore / crypto, use CryptoObject',
  ),
  MasweWeakness(
    id: 'MASWE-0045',
    title:
        'Fallback to Non-biometric Credentials Allowed for Sensitive Transactions',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [288, 287],
    isPlaceholder: true,
    description:
        'e.g. via DEVICE_CREDENTIAL on Android and LAPolicy.deviceOwnerAuthentication on iOS',
  ),
  MasweWeakness(
    id: 'MASWE-0046',
    title: 'Crypto Keys Not Invalidated on New Biometric Enrollment',
    category: 'MASVS-AUTH',
    platforms: ['android', 'ios'],
    cweIds: [287, 522],
    isPlaceholder: true,
    description:
        'Biometric related crypto keys should be is invalidated by default whenever new biometric enrollments are added.',
  ),
  MasweWeakness(
    id: 'MASWE-0048',
    title: 'Insecure Machine-to-Machine Communication',
    category: 'MASVS-NETWORK',
    platforms: ['android', 'ios'],
    cweIds: [311, 319],
    isPlaceholder: true,
    description:
        'Android applications often use technologies like Bluetooth, NFC, and USB for data transfer and device interaction. Developers must use these APIs carefully to prevent data exposure and remote device takeover by attackers.',
  ),
  MasweWeakness(
    id: 'MASWE-0053',
    title: 'Sensitive Data Leaked via the User Interface',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [200, 359],
    isPlaceholder: true,
    description: 'e.g. leaking passwords, PINs via the UI',
  ),
  MasweWeakness(
    id: 'MASWE-0054',
    title: 'Sensitive Data Leaked via Notifications',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [200, 359],
    isPlaceholder: true,
    description:
        'e.g. stealing pending intents from notifications via notificationlistenerservice or tapjacking wire transfer UI.',
  ),
  MasweWeakness(
    id: 'MASWE-0056',
    title: 'Tapjacking Attacks',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [1021],
    isPlaceholder: true,
    description:
        'not using View.setFilterTouchesWhenObscured(true) or android:filterTouchesWhenObscured="true" in the AndroidManifest.xml or not ignoring touch events that have FLAG_WINDOW_IS_PARTIALLY_OBSCURED flag',
  ),
  MasweWeakness(
    id: 'MASWE-0057',
    title: 'StrandHogg Attack / Task Affinity Vulnerability',
    category: 'MASVS-PLATFORM',
    platforms: ['android'],
    cweIds: [451, 1104],
    isPlaceholder: true,
    description:
        'This vulnerability is exploited by manipulating the allowTaskReparenting and taskAffinity settings.',
  ),
  MasweWeakness(
    id: 'MASWE-0058',
    title: 'Insecure Deep Links',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [939, 917],
    isPlaceholder: true,
    description:
        'e.g. use of URL Custom Schemes, unverified AppLinks/Universal Links, not validating URLs. Deep Link parameters offers a wide range of possibilities. A malformed URI or parameter value, if not sanitized, may trigger an injection in different points of the application. For example, CWE-939 prevents the exploit of the URI checking the source and CWE-917 prevents the exploit of the URI checking the content.',
  ),
  MasweWeakness(
    id: 'MASWE-0059',
    title: 'Use Of Unauthenticated Platform IPC',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [287, 668, 200],
    isPlaceholder: true,
    description:
        'e.g. (ab)using the clipboard or using localhost server for IPC',
  ),
  MasweWeakness(
    id: 'MASWE-0060',
    title: 'Insecure Use of UIActivity',
    category: 'MASVS-PLATFORM',
    platforms: ['ios'],
    cweIds: [200, 285, 358],
    isPlaceholder: true,
    description:
        'e.g. data (items) being shared, custom activities, excluded activity types. More examples include CWE-285 and CWE-200 for exposing UIActivity information to untrusted apps or actors. CWE-358 for possible bad activityViewController implemented in the UIActivity.',
  ),
  MasweWeakness(
    id: 'MASWE-0061',
    title: 'Insecure Use of App Extensions',
    category: 'MASVS-PLATFORM',
    platforms: ['ios'],
    cweIds: [200],
    isPlaceholder: true,
    description: 'restricting use of certain extensions',
  ),
  MasweWeakness(
    id: 'MASWE-0062',
    title: 'Insecure Services',
    category: 'MASVS-PLATFORM',
    platforms: ['android'],
    cweIds: [926],
    isPlaceholder: true,
    description:
        'Unintentionally exported services, unrestricted permissions. Exposed binders e.g not using checkCallingPermission() to verify whether the caller has a required permission.',
  ),
  MasweWeakness(
    id: 'MASWE-0063',
    title: 'Insecure Broadcast Receivers',
    category: 'MASVS-PLATFORM',
    platforms: ['android'],
    cweIds: [925, 926],
    isPlaceholder: true,
    description:
        'Unintentionally exported broadcast receivers, unrestricted permissions, sticky broadcasts.',
  ),
  MasweWeakness(
    id: 'MASWE-0064',
    title: 'Insecure Content Providers',
    category: 'MASVS-PLATFORM',
    platforms: ['android'],
    cweIds: [926],
    isPlaceholder: true,
    description:
        'Unintentionally exported content providers, unprotected content providers, permission tags, protection level',
  ),
  MasweWeakness(
    id: 'MASWE-0065',
    title: 'Sensitive Data Permanently Shared with Other Apps',
    category: 'MASVS-PLATFORM',
    platforms: ['android'],
    cweIds: [200, 276, 732],
    isPlaceholder: true,
    description:
        'Provide clients one-time access to data. For example using URI permission grant flags and content provider permissions to display an app\'s PDF file in a separate PDF Viewer app.',
  ),
  MasweWeakness(
    id: 'MASWE-0066',
    title: 'Insecure Intents',
    category: 'MASVS-PLATFORM',
    platforms: ['android'],
    cweIds: [927, 940],
    isPlaceholder: true,
    description:
        'e.g. calling startActivity, startService, sendBroadcast, or setResult on untrusted Intents without validating or sanitizing these Intents. Using an implicit intent to start a service is a security hazard, because you can\'t be certain what service will respond to the intent and the user can\'t see which service starts. e.g. mutable pending intents (not using FLAG_IMMUTABLE), replaying pending intents (not using FLAG_ONE_SHOT)',
  ),
  MasweWeakness(
    id: 'MASWE-0068',
    title: 'JavaScript Bridges in WebViews',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [749, 94],
    isPlaceholder: true,
    description: 'via addJavascriptInterface',
  ),
  MasweWeakness(
    id: 'MASWE-0069',
    title: 'WebViews Allows Access to Local Resources',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [200, 22],
    isPlaceholder: true,
    description:
        'use of setAllowFileAccessFromFileURLs. Mitigations include setAllowFileAccess(false), setAllowContentAccess(false)',
  ),
  MasweWeakness(
    id: 'MASWE-0070',
    title: 'JavaScript Loaded from Untrusted Sources',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [79, 829],
    isPlaceholder: true,
    description: 'e.g. not validating the source of the JavaScript code',
  ),
  MasweWeakness(
    id: 'MASWE-0071',
    title: 'WebViews Loading Content from Untrusted Sources',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [601],
    isPlaceholder: true,
    description:
        'WebView objects shouldn\'t load URLs from untrusted sources. Also, your app shouldn\'t let users navigate to sites that are outside of your control. Whenever possible, use an allowlist to restrict the content loaded by your app\'s WebView objects e.g. via WebViewClient.shouldOverrideUrlLoading',
  ),
  MasweWeakness(
    id: 'MASWE-0072',
    title: 'Universal XSS',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [79],
    isPlaceholder: true,
    description:
        'Successful exploitation of this vulnerability may allow a remote attacker to steal potentially sensitive information, change appearance of a web page, perform phishing and drive-by-download attacks.',
  ),
  MasweWeakness(
    id: 'MASWE-0073',
    title: 'Insecure WebResourceResponse Implementations',
    category: 'MASVS-PLATFORM',
    platforms: ['android'],
    cweIds: [79, 200, 669],
    isPlaceholder: true,
    description: 'Using WebResourceResponse instead of WebViewAssetLoader',
  ),
  MasweWeakness(
    id: 'MASWE-0074',
    title: 'Web Content Debugging Enabled',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [489],
    isPlaceholder: true,
    description:
        'using setWebContentsDebuggingEnabled in Android or WKWebView.isInspectable on iOS',
  ),
  MasweWeakness(
    id: 'MASWE-0075',
    title: 'Enforced Updating Not Implemented',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [602, 693],
    isPlaceholder: true,
    description:
        'Check if the app enforces updates e.g. via AppUpdateManager on Android or itunes check on app version on iOS. However, the backend would be enforcing this and not only the app locally.',
  ),
  MasweWeakness(
    id: 'MASWE-0077',
    title: 'Running on a recent Platform Version Not Ensured',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [693, 1357],
    isPlaceholder: true,
    description:
        'e.g. via minSdkVersion on Android and MinimumOSVersion on iOS. with this we Ensure services/components availability (MASVS-STORAGE-1), also the NSC/ATS availability - Android > 7.0 / iOS > 9.0 (MASVS-NETWORK-1) and WebView secure config (MASVS-PLATFORM-2).',
  ),
  MasweWeakness(
    id: 'MASWE-0078',
    title: 'Latest Platform Version Not Targeted',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [693, 1357],
    isPlaceholder: true,
    description:
        'The app does not target the latest platform version (e.g., via targetSdkVersion on Android or by using an older Xcode/toolchain), and as a result, misses out on the most recent platform-enforced security protections (e.g., scoped storage, permission auto-reset, modern TLS handling) (CWE-693 and CWE-1357).',
  ),
  MasweWeakness(
    id: 'MASWE-0079',
    title: 'Unsafe Handling of Data from the Network',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [924],
    isPlaceholder: true,
    description:
        'Data received from the network should be treated as untrusted even if it is received over a secure channel.',
  ),
  MasweWeakness(
    id: 'MASWE-0080',
    title: 'Unsafe Handling of Data from Backups',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [349],
    isPlaceholder: true,
    description:
        'The app does not validate restored backup data, potentially accepting untrusted modifications alongside trusted data (CWE-349).',
  ),
  MasweWeakness(
    id: 'MASWE-0081',
    title: 'Unsafe Handling Of Data From External Interfaces',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [924],
    isPlaceholder: true,
    description:
        'When data is received from external interfaces (e.g. Bluetooth, NFC, etc.), it should be treated as untrusted.',
  ),
  MasweWeakness(
    id: 'MASWE-0082',
    title: 'Unsafe Handling of Data From Local Storage',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [20, 22, 73, 349],
    isPlaceholder: true,
    description:
        'When data is read from local storage, it should be treated as untrusted.',
  ),
  MasweWeakness(
    id: 'MASWE-0083',
    title: 'Unsafe Handling of Data From The User Interface',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [345, 348],
    isPlaceholder: true,
    description: 'e.g. text fields, QR codes, URLs, pasteboard, etc.',
  ),
  MasweWeakness(
    id: 'MASWE-0084',
    title: 'Unsafe Handling of Data from IPC',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [20, 345, 349],
    isPlaceholder: true,
    description:
        'e.g. received intents, broadcast receivers, URL validation, URL schemes, etc.',
  ),
  MasweWeakness(
    id: 'MASWE-0085',
    title: 'Unsafe Dynamic Code Loading',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [494],
    isPlaceholder: true,
    description: 'e.g. when using dlopen, DexClassLoader, etc.',
  ),
  MasweWeakness(
    id: 'MASWE-0086',
    title: 'SQL Injection',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [89],
    isPlaceholder: true,
    description:
        'e.g. prepared statements with variable binding (i.e. parameterized queries)',
  ),
  MasweWeakness(
    id: 'MASWE-0087',
    title: 'Insecure Parsing and Escaping',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [116, 611],
    isPlaceholder: true,
    description:
        'e.g. XML External Entity (XXE) attacks, X509 certificate parsing, character escaping.',
  ),
  MasweWeakness(
    id: 'MASWE-0088',
    title: 'Insecure Object Deserialization',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [502],
    isPlaceholder: true,
    description:
        'e.g. XML, JSON, java.io.Serializable, Parcelable on Android or NSCoding on iOS.',
  ),
  MasweWeakness(
    id: 'MASWE-0089',
    title: 'Code Obfuscation Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective obfuscation techniques to protect against reverse engineering (CWE-693), e.g. polymorphic obfuscation, method-inlining, insertion of opaque predicates, instruction substitution, and instruction block chopping.',
  ),
  MasweWeakness(
    id: 'MASWE-0090',
    title: 'Resource Obfuscation Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description: 'e.g. resource obfuscation, binary encryption/packing',
  ),
  MasweWeakness(
    id: 'MASWE-0091',
    title: 'Anti-Deobfuscation Techniques Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective anti-deobfuscation techniques to protect against reverse engineering (CWE-693)',
  ),
  MasweWeakness(
    id: 'MASWE-0092',
    title: 'Static Analysis Tools Not Prevented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'AKA static damage control. The app\'s code doesn’t implement effective techniques to prevent static analysis tools from decompiling the app (CWE-693).',
  ),
  MasweWeakness(
    id: 'MASWE-0093',
    title: 'Debugging Symbols Not Removed',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [497, 540],
    isPlaceholder: true,
    description:
        'The app contains debugging symbols, which can be exploited by attackers to understand the app\'s behavior (CWE-497). The app\'s debugging symbols are considered sensitive information (CWE-540) and should not be present in production builds.',
  ),
  MasweWeakness(
    id: 'MASWE-0094',
    title: 'Non-Production Resources Not Removed',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [497, 540, 1295],
    isPlaceholder: true,
    description:
        'The app contains non-production resources that should not be present in production builds, such as non-production URLs, code flows, or verbose logging. These resources help adversaries understand the app\'s behavior and potentially exploit it (CWE-497), may include sensitive information (CWE-540) or implementation details (CWE-1295).',
  ),
  MasweWeakness(
    id: 'MASWE-0095',
    title: 'Code That Disables Security Controls Not Removed',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [489, 912],
    isPlaceholder: true,
    description:
        'The app contains leftover debugging logic or test code (CWE-489) that was not removed before release, which can disable critical protections like TLS certificate validation. It may also include hidden settings or functions that allow bypassing security controls (CWE-912), making the app vulnerable to manipulation.',
  ),
  MasweWeakness(
    id: 'MASWE-0096',
    title: 'Data Sent Unencrypted Over Encrypted Connections',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [319],
    isPlaceholder: true,
    description:
        'Use payload/End-2-End Encryption. Even if the connection is encrypted (e.g. HTTPS), performing a MITM attack should not reveal any sensitive information (e.g. about the inner workings of the app and its operations. This is not necessarily related to privacy).',
  ),
  MasweWeakness(
    id: 'MASWE-0097',
    title: 'Root/Jailbreak Detection Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'no root/jailbreak detection implemented e.g. check for Cydia, SuperSU, Magisk, Xposed, etc. The app does not implement effective techniques to detect if the device is rooted or jailbroken (CWE-693).',
  ),
  MasweWeakness(
    id: 'MASWE-0098',
    title: 'App Virtualization Environment Detection Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective techniques to detect if it is running in a virtualized environment (CWE-693), e.g. checking for known virtualization software or anomalies in the environment.',
  ),
  MasweWeakness(
    id: 'MASWE-0099',
    title: 'Emulator Detection Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective techniques to detect if it is running in an emulator (CWE-693), e.g. identifying features and limitations available for commonly used emulation solutions',
  ),
  MasweWeakness(
    id: 'MASWE-0100',
    title: 'Device Attestation Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app doesn\'t use App Attestation APIs, such as Google Play Integrity API, iOS DeviceCheck API,so the backend cannot ensure requests originate from a genuine app binary (CWE-693). This exposes the app to tampering, fraud, replay attacks, and unauthorized use of premium features.',
  ),
  MasweWeakness(
    id: 'MASWE-0101',
    title: 'Debugger Detection Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective techniques to detect if it is being debugged (CWE-693), e.g. checking for debugger presence.',
  ),
  MasweWeakness(
    id: 'MASWE-0102',
    title: 'Dynamic Analysis Tools Detection Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective techniques to detect if it is being analyzed by dynamic analysis tools (CWE-693), e.g. Frida, Xposed, Ellekit, etc.',
  ),
  MasweWeakness(
    id: 'MASWE-0103',
    title: 'RASP Techniques Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective RASP techniques to detect if it is running in a compromised environment (CWE-693), e.g. Runtime Application Self-Protection, detection triggering different responses.',
  ),
  MasweWeakness(
    id: 'MASWE-0104',
    title: 'App Integrity Not Verified',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [347],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective techniques to verify the integrity of its own code (CWE-347), potentially relevant for apps in alternative app stores (not Google PlayStore or Apple AppStore). Also, e.g. Android V1 signing scheme only or iOS CodeDirectory v less than 20400. Also, e.g. App Signature or Binaries, native libraries including e.g. AppAttest.',
  ),
  MasweWeakness(
    id: 'MASWE-0105',
    title: 'Integrity of App Resources Not Verified',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective techniques to verify the integrity of its own resources (CWE-693).',
  ),
  MasweWeakness(
    id: 'MASWE-0106',
    title: 'Official Store Verification Not Implemented',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective techniques to verify if it is downloaded from an official store and therefore not relying on security and other assurances provided by the store (CWE-693).',
  ),
  MasweWeakness(
    id: 'MASWE-0107',
    title: 'Runtime Code Integrity Not Verified',
    category: 'MASVS-RESILIENCE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app\'s code doesn’t implement effective techniques to verify the integrity of its own code at runtime (CWE-693).',
  ),
  MasweWeakness(
    id: 'MASWE-0116',
    title: 'Compiler-Provided Security Features Not Used',
    category: 'MASVS-CODE',
    platforms: ['android', 'ios'],
    cweIds: [693],
    isPlaceholder: true,
    description:
        'The app is compiled without enabling memory protection mechanisms such as stack canaries, address space layout randomization (ASLR), non-executable memory, or position-independent executables (PIE), reducing resistance to memory corruption attacks (CWE-693).',
  ),
  MasweWeakness(
    id: 'MASWE-0118',
    title: 'Sensitive Data Not Removed After Use',
    category: 'MASVS-PLATFORM',
    platforms: ['android', 'ios'],
    cweIds: [],
    isPlaceholder: true,
    description:
        '| Applying data minimisation, including appropriate cleanup in the end of the lifecycle is important. 1. Clear web state or prefer non-persistent web stores',
  ),
  MasweWeakness(
    id: 'MASWE-0119',
    title: 'Insecure Activities',
    category: 'MASVS-PLATFORM',
    platforms: ['android'],
    cweIds: [926],
    isPlaceholder: true,
    description:
        'Unintentionally exported ativities, unrestricted permissions.',
  ),
];
