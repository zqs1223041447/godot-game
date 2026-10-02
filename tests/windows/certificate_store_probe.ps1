#requires -Version 7.0
<# Read-only Windows ROOT-store audit. No certificate contents are exported.
   CertOpenSystemStoreA has no read-only flag, so this independent audit uses
   CertOpenStore with READONLY | OPEN_EXISTING rather than calling that API. #>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This probe requires Windows.' }

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class CertificateReadOnlyNative {
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CertOpenStore(IntPtr provider, uint encoding,
        IntPtr cryptoProvider, uint flags, string store);
    [DllImport("crypt32.dll", SetLastError = true)]
    private static extern IntPtr CertEnumCertificatesInStore(IntPtr store, IntPtr previous);
    [DllImport("crypt32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CertCloseStore(IntPtr store, uint flags);
    [DllImport("crypt32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CertFreeCertificateContext(IntPtr context);
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(IntPtr token, int informationClass,
        out int value, int length, out int required);

    public sealed class StoreResult {
        public string Scope { get; set; }
        public string Flags { get; set; }
        public bool Opened { get; set; }
        public int OpenError { get; set; }
        public string OpenErrorMessage { get; set; }
        public int CertificateCount { get; set; }
        public int EnumerationError { get; set; }
        public string EnumerationErrorHex { get; set; }
        public bool EnumerationComplete { get; set; }
        public bool Closed { get; set; }
    }
    public static StoreResult ReadRoot(bool machine) {
        // CERT_STORE_PROV_SYSTEM_W = 10. Never create a store or request write access.
        uint flags = (machine ? 0x00020000u : 0x00010000u) | 0x00008000u | 0x00004000u;
        var result = new StoreResult {
            Scope = machine ? "LocalMachine" : "CurrentUser", Flags = "0x" + flags.ToString("X8")
        };
        IntPtr store = CertOpenStore(new IntPtr(10), 0, IntPtr.Zero, flags, "ROOT");
        result.Opened = store != IntPtr.Zero;
        if (!result.Opened) {
            result.OpenError = Marshal.GetLastWin32Error();
            result.OpenErrorMessage = new Win32Exception(result.OpenError).Message;
            return result;
        }
        IntPtr context = IntPtr.Zero;
        try {
            while (true) {
                context = CertEnumCertificatesInStore(store, context);
                if (context == IntPtr.Zero) {
                    result.EnumerationError = Marshal.GetLastWin32Error();
                    result.EnumerationErrorHex = "0x" + unchecked((uint)result.EnumerationError).ToString("X8");
                    result.EnumerationComplete = result.EnumerationError == unchecked((int)0x80092004u)
                        || result.EnumerationError == 18; // CRYPT_E_NOT_FOUND / ERROR_NO_MORE_FILES
                    break;
                }
                result.CertificateCount++;
            }
        } finally {
            if (context != IntPtr.Zero) CertFreeCertificateContext(context);
            result.Closed = CertCloseStore(store, 0);
        }
        return result;
    }
    public static object TokenFlag(IntPtr token, int informationClass) {
        int value, required;
        if (!GetTokenInformation(token, informationClass, out value, 4, out required))
            return new { available = false, error = Marshal.GetLastWin32Error() };
        return new { available = true, value = value != 0 };
    }
}
'@

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try {
    $result = [ordered]@{
        identity = $identity.Name
        sid = $identity.User.Value
        elevated = [CertificateReadOnlyNative]::TokenFlag($identity.Token, 20)
        has_restrictions = [CertificateReadOnlyNative]::TokenFlag($identity.Token, 21)
        app_container = [CertificateReadOnlyNative]::TokenFlag($identity.Token, 29)
        stores = @([CertificateReadOnlyNative]::ReadRoot($false), [CertificateReadOnlyNative]::ReadRoot($true))
        registry_read = @()
        certificate_contents_exported = $false
        write_apis_called = $false
    }
    foreach ($scope in @('CurrentUser', 'LocalMachine')) {
        $entry = [ordered]@{ scope = $scope; opened = $false; subkey_count = $null; error = $null }
        $rootKey = if ($scope -eq 'CurrentUser') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
        $key = $null
        try {
            $key = $rootKey.OpenSubKey('SOFTWARE\Microsoft\SystemCertificates\ROOT\Certificates', $false)
            $entry.opened = $null -ne $key
            if ($entry.opened) { $entry.subkey_count = $key.SubKeyCount }
        } catch { $entry.error = $_.Exception.Message }
        finally { if ($null -ne $key) { $key.Dispose() } }
        $result.registry_read += $entry
    }
    Write-Output ('CERTIFICATE_STORE ' + ($result | ConvertTo-Json -Depth 8 -Compress))
} finally { $identity.Dispose() }
