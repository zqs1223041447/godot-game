#requires -Version 7.0
<#
.SYNOPSIS
Runs the actual Windows export only after proving its user:// isolation offline.
.DESCRIPTION
No downloads, source-project fallback, environment mutation, or security bypass.
The official 4.6.3 archive and the supplied artifact SHA256 are mandatory gates.
Dot-sourcing defines helpers for the harmless fixture tests; it never runs a game.
#>
[CmdletBinding()]
param(
    [string]$Executable,
    [string]$ExpectedSha256,
    [string]$ArtifactUrl,
    [string]$OfficialTemplatesArchive,
    [string]$SandboxParent = [IO.Path]::GetTempPath(),
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 30,
    [ValidateRange(1, 10000)][int]$QuitAfter = 120,
    [ValidateSet('Headless', 'Windowed')][string]$DisplayMode = 'Headless',
    [switch]$PreflightOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SmokeUtf8 = [Text.UTF8Encoding]::new($false, $true)
$script:OfficialArchiveSha256 = '3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8'
$script:OfficialArchiveUrl = 'https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz'

function Assert-SmokeLocalPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'A literal local path is required.' }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\') -or $full.Substring(2).Contains(':')) {
        throw 'UNC, device paths, and alternate-stream paths are not accepted.'
    }
    $current = $full
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if (((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse point in QA path: $current"
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $full
}

function Assert-SmokeInside([string]$Path, [string]$Root) {
    $full = Assert-SmokeLocalPath $Path
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd([char]92, [char]47) + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "QA path escaped its root: $full"
    }
    return $full
}

function Assert-SmokeSecurityMark([string]$Path) {
    # CreateProcess does not provide Explorer's SmartScreen review. Fail closed if
    # Mark-of-the-Web exists; do not erase it or silently copy to an unmarked EXE.
    $streams = @(Get-Item -LiteralPath $Path -Stream * -ErrorAction Stop)
    if (@($streams | Where-Object Stream -EQ 'Zone.Identifier').Count -ne 0) {
        throw 'Security review required: Zone.Identifier is present. No launch or Unblock-File was attempted.'
    }
}

function New-SmokeSandbox([string]$Parent) {
    $parentFull = Assert-SmokeLocalPath $Parent
    if (-not (Test-Path -LiteralPath $parentFull -PathType Container)) { throw 'SandboxParent must already exist.' }
    $root = Join-Path $parentFull ('godot-export-smoke-' + [Guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $root) { throw 'Refusing to reuse a sandbox.' }
    [void][IO.Directory]::CreateDirectory($root)
    foreach ($name in @('product', 'roaming', 'local', 'temp', 'logs')) {
        [void][IO.Directory]::CreateDirectory((Assert-SmokeInside (Join-Path $root $name) $root))
    }
    return $root
}

function Get-SmokeChildEnvironment([string]$Root) {
    # This dictionary belongs only to CreateProcessW's environment block.
    # HOME / USERPROFILE and the parent or persistent environment are untouched.
    $result = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
        if (-not ([string]$item.Key).StartsWith('=')) { $result[[string]$item.Key] = [string]$item.Value }
    }
    $result['APPDATA'] = Assert-SmokeInside (Join-Path $Root 'roaming') $Root
    $result['LOCALAPPDATA'] = Assert-SmokeInside (Join-Path $Root 'local') $Root
    $result['TEMP'] = Assert-SmokeInside (Join-Path $Root 'temp') $Root
    $result['TMP'] = $result['TEMP']
    return ,$result
}

function Initialize-SmokeNative {
    if ('ExportSmoke.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace ExportSmoke {
    public sealed class RunResult {
        public uint RootPid, ExitCode, ImmediateActiveAfterRootExit, ActiveAfterRootExit, ActiveAfterCleanup, TotalJobProcesses;
        public uint[] PidsBeforeCleanup = new uint[0];
        public bool Resumed, TimedOut, TerminatedJob;
        public long DurationMs;
        public string Error, CleanupError;
        public bool Created;
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] struct SA { public int Length; public IntPtr Descriptor; public int Inherit; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SI {
            public int Size; public string Reserved, Desktop, Title;
            public uint X,Y,XSize,YSize,XChars,YChars,Fill,Flags; public ushort Show,Reserved2;
            public IntPtr ReservedPtr,Input,Output,Error;
        }
        [StructLayout(LayoutKind.Sequential)] struct SIX { public SI Startup; public IntPtr Attributes; }
        [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr Process,Thread; public uint Pid,Tid; }
        [StructLayout(LayoutKind.Sequential)] struct BASIC_LIMIT {
            public long ProcessTime,JobTime; public uint Flags; public UIntPtr Min,Max;
            public uint ActiveLimit; public UIntPtr Affinity; public uint Priority,Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS { public ulong A,B,C,D,E,F; }
        [StructLayout(LayoutKind.Sequential)] struct EXT_LIMIT {
            public BASIC_LIMIT Basic; public IO_COUNTERS IO;
            public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob;
        }
        [StructLayout(LayoutKind.Sequential)] struct ACCOUNTING {
            public long User,Kernel,PeriodUser,PeriodKernel;
            public uint Faults,Total,Active,Terminated;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObjectW(IntPtr sa,string name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,ref EXT_LIMIT info,int size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int kind,out ACCOUNTING info,int size,IntPtr returned);
        [DllImport("kernel32.dll", SetLastError=true, EntryPoint="QueryInformationJobObject")] static extern bool QueryJobPids(IntPtr job,int kind,IntPtr info,int size,IntPtr returned);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint code);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr process,uint code);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint millis);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateFileW(string path,uint access,uint share,ref SA sa,uint create,uint flags,IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,uint flags,ref UIntPtr size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,UIntPtr attribute,IntPtr value,UIntPtr size,IntPtr previous,IntPtr returned);
        [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcessW(string app,StringBuilder cmd,IntPtr psa,IntPtr tsa,bool inherit,uint flags,IntPtr environment,string cwd,ref SIX startup,out PI process);

        static void Check(bool ok,string action) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error(), action); }
        static void Close(ref IntPtr handle) { if (handle!=IntPtr.Zero && handle!=new IntPtr(-1)) CloseHandle(handle); handle=IntPtr.Zero; }
        static ACCOUNTING Accounting(IntPtr job) {
            ACCOUNTING a; Check(QueryInformationJobObject(job,1,out a,Marshal.SizeOf<ACCOUNTING>(),IntPtr.Zero),"Query owned job"); return a;
        }
        static uint[] JobPids(IntPtr job) {
            int size=8+IntPtr.Size*2048; IntPtr buffer=Marshal.AllocHGlobal(size);
            try {
                Check(QueryJobPids(job,3,buffer,size,IntPtr.Zero),"Query owned job process IDs");
                int count=Marshal.ReadInt32(buffer,4); if(count<0 || count>2048) throw new InvalidOperationException("Job process list limit");
                var pids=new uint[count];
                for(int i=0;i<count;i++) pids[i]=checked((uint)Marshal.ReadIntPtr(buffer,8+i*IntPtr.Size).ToInt64());
                return pids;
            } finally { Marshal.FreeHGlobal(buffer); }
        }
        // Windows CRT argument quoting; no cmd.exe / PowerShell parser is involved.
        public static string Quote(string value) {
            if (value==null || value.IndexOf('\0')>=0) throw new ArgumentException("NUL/null argument");
            var s=new StringBuilder("\""); int slashes=0;
            foreach(char c in value) {
                if(c=='\\') { slashes++; continue; }
                if(c=='\"') s.Append('\\',slashes*2+1); else s.Append('\\',slashes);
                s.Append(c); slashes=0;
            }
            s.Append('\\',slashes*2); return s.Append('"').ToString();
        }
        public static RunResult Run(string exe,string[] arguments,string cwd,
            Dictionary<string,string> environment,string stdout,string stderr,int timeoutMs) {
            var watch=Stopwatch.StartNew(); var result=new RunResult();
            IntPtr job=IntPtr.Zero,output=IntPtr.Zero,error=IntPtr.Zero,input=IntPtr.Zero;
            IntPtr attrs=IntPtr.Zero,handles=IntPtr.Zero,env=IntPtr.Zero; PI pi=new PI(); bool assigned=false,attrsReady=false;
            try {
                job=CreateJobObjectW(IntPtr.Zero,null); Check(job!=IntPtr.Zero,"Create owned job");
                var limit=new EXT_LIMIT(); limit.Basic.Flags=0x2000; // KILL_ON_JOB_CLOSE; no breakaway permission.
                Check(SetInformationJobObject(job,9,ref limit,Marshal.SizeOf<EXT_LIMIT>()),"Protect owned job");
                var sa=new SA { Length=Marshal.SizeOf<SA>(), Inherit=1 };
                output=CreateFileW(stdout,0x40000000,1,ref sa,1,0x80,IntPtr.Zero);
                Check(output!=new IntPtr(-1),"Create stdout log");
                error=CreateFileW(stderr,0x40000000,1,ref sa,1,0x80,IntPtr.Zero);
                Check(error!=new IntPtr(-1),"Create stderr log");
                input=CreateFileW("NUL",0x80000000,3,ref sa,3,0x80,IntPtr.Zero);
                Check(input!=new IntPtr(-1),"Open null stdin");
                UIntPtr size=UIntPtr.Zero; InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref size);
                attrs=Marshal.AllocHGlobal(checked((int)size.ToUInt64()));
                Check(InitializeProcThreadAttributeList(attrs,1,0,ref size),"Initialize handle allowlist"); attrsReady=true;
                handles=Marshal.AllocHGlobal(IntPtr.Size*3);
                Marshal.WriteIntPtr(handles,0,input); Marshal.WriteIntPtr(handles,IntPtr.Size,output); Marshal.WriteIntPtr(handles,IntPtr.Size*2,error);
                Check(UpdateProcThreadAttribute(attrs,0,new UIntPtr(0x20002),handles,new UIntPtr((uint)(IntPtr.Size*3)),IntPtr.Zero,IntPtr.Zero),"Allow only log/stdin handles");
                var names=new List<string>(environment.Keys); names.Sort(StringComparer.OrdinalIgnoreCase);
                var block=new StringBuilder();
                foreach(string name in names) {
                    string value=environment[name];
                    if(name.Length==0 || name.IndexOfAny(new[]{'\0','='})>=0 || value==null || value.IndexOf('\0')>=0) throw new ArgumentException("Invalid child environment");
                    block.Append(name).Append('=').Append(value).Append('\0');
                }
                block.Append('\0'); env=Marshal.StringToHGlobalUni(block.ToString());
                var command=new StringBuilder(Quote(exe)); foreach(string arg in arguments) command.Append(' ').Append(Quote(arg));
                if(command.Length>=32767) throw new ArgumentException("Windows command line too long");
                var si=new SIX(); si.Startup.Size=Marshal.SizeOf<SIX>(); si.Startup.Flags=0x101;
                si.Startup.Show=0; si.Startup.Input=input; si.Startup.Output=output; si.Startup.Error=error; si.Attributes=attrs;
                Check(CreateProcessW(exe,command,IntPtr.Zero,IntPtr.Zero,true,0x08080404,env,cwd,ref si,out pi),"Create suspended smoke process");
                result.RootPid=pi.Pid; result.Created=true;
                // No target code runs before assignment succeeds. Assignment failure kills
                // only this still-suspended process, using the handle returned above.
                Check(AssignProcessToJobObject(job,pi.Process),"Assign suspended process to owned job"); assigned=true;
                Check(ResumeThread(pi.Thread)!=UInt32.MaxValue,"Resume owned process"); result.Resumed=true;
                Close(ref pi.Thread); Close(ref output); Close(ref error); Close(ref input);
                uint wait=WaitForSingleObject(pi.Process,(uint)timeoutMs);
                if(wait==258) {
                    result.PidsBeforeCleanup=JobPids(job);
                    result.TimedOut=true; Check(TerminateJobObject(job,124),"Terminate timed-out owned job"); result.TerminatedJob=true;
                } else Check(wait==0,"Wait for owned process");
                Check(WaitForSingleObject(pi.Process,5000)==0,"Wait for root shutdown");
                uint code; Check(GetExitCodeProcess(pi.Process,out code),"Read root exit code"); result.ExitCode=code;
                result.ImmediateActiveAfterRootExit=Accounting(job).Active;
                // Windows may briefly retain a console host after the root exits.
                // Give owned helpers 500 ms to finish before classifying leftovers.
                var settle=Stopwatch.StartNew();
                while(Accounting(job).Active>0 && settle.ElapsedMilliseconds<500) System.Threading.Thread.Sleep(20);
                result.ActiveAfterRootExit=Accounting(job).Active;
                if(result.ActiveAfterRootExit>0) {
                    if(!result.TimedOut) result.PidsBeforeCleanup=JobPids(job);
                    Check(TerminateJobObject(job,1),"Terminate remaining owned children"); result.TerminatedJob=true;
                }
                var cleanup=Stopwatch.StartNew(); ACCOUNTING counts;
                do { counts=Accounting(job); if(counts.Active==0) break; System.Threading.Thread.Sleep(20); } while(cleanup.ElapsedMilliseconds<5000);
                result.ActiveAfterCleanup=counts.Active; result.TotalJobProcesses=counts.Total;
                if(counts.Active!=0) throw new InvalidOperationException("Owned job did not reach zero active processes");
                return result;
            } catch (Exception ex) {
                result.Error=ex.Message;
                return result;
            } finally {
                try {
                    if(pi.Process!=IntPtr.Zero) {
                        if(assigned) {
                            if(Accounting(job).Active>0) { Check(TerminateJobObject(job,70),"Finally terminate owned job"); result.TerminatedJob=true; }
                        } else Check(TerminateProcess(pi.Process,70),"Terminate own suspended process");
                        Check(WaitForSingleObject(pi.Process,5000)==0,"Finally wait for root");
                    }
                    if(job!=IntPtr.Zero) {
                        var cleanup=Stopwatch.StartNew(); ACCOUNTING a;
                        do { a=Accounting(job); if(a.Active==0) break; System.Threading.Thread.Sleep(20); } while(cleanup.ElapsedMilliseconds<5000);
                        result.ActiveAfterCleanup=a.Active; result.TotalJobProcesses=a.Total;
                        if(a.Active!=0) result.CleanupError="Owned job remained active before handle close";
                    }
                } catch(Exception ex) { result.CleanupError=ex.Message; }
                Close(ref job); Close(ref pi.Thread); Close(ref pi.Process); Close(ref output); Close(ref error); Close(ref input);
                if(attrsReady) DeleteProcThreadAttributeList(attrs);
                if(attrs!=IntPtr.Zero) Marshal.FreeHGlobal(attrs);
                if(handles!=IntPtr.Zero) Marshal.FreeHGlobal(handles);
                if(env!=IntPtr.Zero) Marshal.FreeHGlobal(env);
                result.DurationMs=watch.ElapsedMilliseconds;
            }
        }
    }
}
'@
}

function Read-SmokeU32([byte[]]$Bytes, [int]$Offset) {
    if ($Offset -lt 0 -or $Offset -gt $Bytes.Length - 4) { throw 'Truncated binary field.' }
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Read-SmokeU64([byte[]]$Bytes, [int]$Offset) {
    if ($Offset -lt 0 -or $Offset -gt $Bytes.Length - 8) { throw 'Truncated binary field.' }
    $value = [BitConverter]::ToUInt64($Bytes, $Offset)
    if ($value -gt [int]::MaxValue) { throw 'Export smoke supports binaries smaller than 2 GiB.' }
    return [int]$value
}

function Get-SmokePe([byte[]]$Bytes) {
    if ($Bytes.Length -lt 256 -or $Bytes[0] -ne 77 -or $Bytes[1] -ne 90) { throw 'Not a Windows PE executable.' }
    $pe = [int](Read-SmokeU32 $Bytes 60)
    if ((Read-SmokeU32 $Bytes $pe) -ne 17744 -or [BitConverter]::ToUInt16($Bytes, $pe + 4) -ne 0x8664) { throw 'Expected AMD64 PE.' }
    $count = [BitConverter]::ToUInt16($Bytes, $pe + 6)
    $optional = $pe + 24
    if ($count -lt 2 -or $count -gt 96 -or [BitConverter]::ToUInt16($Bytes, $optional) -ne 0x20b) { throw 'Unsupported PE layout.' }
    $table = $optional + [BitConverter]::ToUInt16($Bytes, $pe + 20)
    if ($table + $count * 40 -gt $Bytes.Length) { throw 'Truncated PE sections.' }
    $sections = @()
    for ($i = 0; $i -lt $count; $i++) {
        $pos = $table + $i * 40
        $name = [Text.Encoding]::ASCII.GetString($Bytes, $pos, 8).TrimEnd([char]0)
        $sections += @{ Name = $name; Offset = $pos; Index = $i }
    }
    return @{ Pe = $pe; Optional = $optional; Table = $table; Count = $count; Sections = $sections }
}

function Assert-SmokeRangeEqual([byte[]]$Left, [int]$LeftStart, [byte[]]$Right, [int]$RightStart, [int]$Count) {
    if ($Count -lt 0 -or $LeftStart -lt 0 -or $RightStart -lt 0 -or $LeftStart + [long]$Count -gt $Left.Length -or $RightStart + [long]$Count -gt $Right.Length) { throw 'Invalid comparison range.' }
    # Compare hashes of slices to keep the large template comparison in native .NET.
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $a = $algorithm.ComputeHash($Left, $LeftStart, $Count)
        $b = $algorithm.ComputeHash($Right, $RightStart, $Count)
    } finally { $algorithm.Dispose() }
    if ([Convert]::ToHexString($a) -cne [Convert]::ToHexString($b)) { throw "Engine template differs in range $LeftStart/$Count. Isolation unproven." }
}

function Assert-SmokeTemplate([byte[]]$Export, [byte[]]$Template) {
    # Read-only comparison, including all code/data/imports/resources. Validate
    # exactly the header changes made by Godot's fixup_embedded_pck exporter.
    # Neither input file nor any binary byte array is patched.
    $t = Get-SmokePe $Template
    $e = Get-SmokePe $Export
    if ($Export.Length -le $Template.Length -or $t.Table -ne $e.Table -or $t.Count -ne $e.Count) { throw 'Template/export PE layouts differ.' }
    $pcks = @($t.Sections | Where-Object Name -CEQ 'pck')
    if ($pcks.Count -ne 1 -or $pcks[0].Index -lt 1) { throw 'Official template pck placeholder missing.' }
    $pckIndex = $pcks[0].Index
    $alignment = Read-SmokeU32 $Template ($t.Optional + 32)
    $imageSize = Read-SmokeU32 $Template ($t.Optional + 56)
    if ((Read-SmokeU32 $Export ($e.Optional + 56)) -ne $imageSize + $alignment) { throw 'Unexpected export image size.' }
    Assert-SmokeRangeEqual $Template 0 $Export 0 ($t.Optional + 56)
    Assert-SmokeRangeEqual $Template ($t.Optional + 60) $Export ($e.Optional + 60) ($t.Table - $t.Optional - 60)
    for ($i = 0; $i -lt $t.Count - 1; $i++) {
        $old = if ($i -lt $pckIndex) { $i } else { $i + 1 }
        $to = $e.Table + $i * 40
        $from = $t.Table + $old * 40
        if ($old -eq $pckIndex - 1) {
            Assert-SmokeRangeEqual $Template $from $Export $to 8
            if ((Read-SmokeU32 $Export ($to + 8)) -ne (Read-SmokeU32 $Template ($from + 8)) + $alignment) { throw 'Unexpected section virtual size.' }
            Assert-SmokeRangeEqual $Template ($from + 12) $Export ($to + 12) 28
        } else { Assert-SmokeRangeEqual $Template $from $Export $to 40 }
    }
    $p = $e.Table + ($e.Count - 1) * 40
    if ($e.Sections[-1].Name -cne 'pck' -or (Read-SmokeU32 $Export ($p + 8)) -ne 8 -or (Read-SmokeU32 $Export ($p + 12)) -ne $imageSize -or
        (Read-SmokeU32 $Export ($p + 16)) -ne $Export.Length - $Template.Length -or (Read-SmokeU32 $Export ($p + 20)) -ne $Template.Length -or
        (Read-SmokeU32 $Export ($p + 24)) -ne 0 -or (Read-SmokeU32 $Export ($p + 28)) -ne 0 -or (Read-SmokeU32 $Export ($p + 32)) -ne 0 -or
        (Read-SmokeU32 $Export ($p + 36)) -ne 0x40000000) { throw 'Unexpected embedded PCK section.' }
    $body = $t.Table + $t.Count * 40
    Assert-SmokeRangeEqual $Template $body $Export $body ($Template.Length - $body)
    return @{ template_bytes = $Template.Length; full_engine_bytes_verified = $true; header_changes = 'Godot 4.6.3 fixup_embedded_pck only' }
}

function Get-SmokePackedSettings([byte[]]$Bytes) {
    if ((Read-SmokeU32 $Bytes ($Bytes.Length - 4)) -ne 0x43504447) { throw 'Embedded PCK footer missing.' }
    $packSize = Read-SmokeU64 $Bytes ($Bytes.Length - 12)
    $start = $Bytes.Length - 12 - $packSize
    if ((Read-SmokeU32 $Bytes $start) -ne 0x43504447 -or (Read-SmokeU32 $Bytes ($start + 4)) -ne 3) { throw 'Only embedded PCK v3 is supported.' }
    if ((Read-SmokeU32 $Bytes ($start + 8)) -ne 4 -or (Read-SmokeU32 $Bytes ($start + 12)) -ne 6 -or (Read-SmokeU32 $Bytes ($start + 16)) -ne 3) { throw 'PCK engine version must be 4.6.3.' }
    if ((Read-SmokeU32 $Bytes ($start + 20)) -ne 2) { throw 'Only ordinary unencrypted PCK with relative file base is supported.' }
    $base = Read-SmokeU64 $Bytes ($start + 24)
    $pos = $start + (Read-SmokeU64 $Bytes ($start + 32))
    $count = Read-SmokeU32 $Bytes $pos
    $pos += 4
    if ($count -lt 1 -or $count -gt 10000) { throw 'Invalid PCK directory count.' }
    $settingsBytes = $null
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt $count; $i++) {
        $length = [int](Read-SmokeU32 $Bytes $pos)
        $pos += 4
        if ($length -lt 1 -or $length -gt 65536 -or $pos + $length -gt $Bytes.Length) { throw 'Invalid PCK path length.' }
        $name = $script:SmokeUtf8.GetString($Bytes, $pos, $length).TrimEnd([char]0)
        $pos += $length
        $name = $name -creplace '^res://', ''
        if (-not $names.Add($name)) { throw 'Duplicate/case-alias PCK entries are unsupported.' }
        if ($name.Contains('\') -or $name.Contains(':') -or $name -match '(^|/)\.\.?(/|$)' -or $name.StartsWith('/')) { throw 'Noncanonical PCK path.' }
        if ($name -match '(?i)(^|/)(override\.cfg|project\.godot)$|\.gdextension$|(^|/)extension_list\.cfg$') { throw "Settings/native extension outside the proved isolation contract: $name" }
        $offset = Read-SmokeU64 $Bytes $pos
        $size = Read-SmokeU64 $Bytes ($pos + 8)
        $digestPos = $pos + 16
        $flags = Read-SmokeU32 $Bytes ($pos + 32)
        $pos += 36
        $fileStart = [long]$start + $base + $offset
        if ($flags -ne 0 -or $fileStart -lt $start -or $fileStart + $size -gt $Bytes.Length - 12) { throw 'Unsupported PCK entry flags/bounds.' }
        if ($name -ceq 'project.binary') {
            if ($size -gt 1048576) { throw 'Oversized project settings.' }
            $settingsBytes = [byte[]]::new($size)
            [Array]::Copy($Bytes, $fileStart, $settingsBytes, 0, $size)
            $md5 = [Security.Cryptography.MD5]::HashData($settingsBytes)
            for ($j = 0; $j -lt 16; $j++) { if ($Bytes[$digestPos + $j] -ne $md5[$j]) { throw 'Packed project.binary MD5 mismatch.' } }
        }
    }
    if ($null -eq $settingsBytes -or (Read-SmokeU32 $settingsBytes 0) -ne 0x47464345) { throw 'ECFG project.binary required inside the actual EXE.' }
    $settings = @{}
    $propCount = Read-SmokeU32 $settingsBytes 4
    if ($propCount -gt 10000) { throw 'Invalid ECFG property count.' }
    $pos = 8
    for ($i = 0; $i -lt $propCount; $i++) {
        $length = [int](Read-SmokeU32 $settingsBytes $pos)
        $pos += 4
        if ($length -lt 1 -or $length -gt 65536 -or $pos + $length -gt $settingsBytes.Length) { throw 'Invalid ECFG key.' }
        $key = $script:SmokeUtf8.GetString($settingsBytes, $pos, $length)
        $pos += $length
        $length = [int](Read-SmokeU32 $settingsBytes $pos)
        $pos += 4
        if ($length -lt 4 -or $pos + $length -gt $settingsBytes.Length -or $settings.ContainsKey($key)) { throw 'Invalid/duplicate ECFG property.' }
        $value = [byte[]]::new($length)
        [Array]::Copy($settingsBytes, $pos, $value, 0, $length)
        $settings[$key] = $value
        $pos += $length
    }
    if ($pos -ne $settingsBytes.Length) { throw 'Trailing ECFG bytes.' }
    return @{ settings = $settings; pack_start = $start; file_count = $count; project_binary_sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($settingsBytes)).ToLowerInvariant() }
}

function Read-SmokeSetting($Settings, [string]$Key, $Default, [string]$Kind) {
    if (-not $Settings.ContainsKey($Key)) { return $Default }
    [byte[]]$bytes = $Settings[$Key]
    $type = Read-SmokeU32 $bytes 0
    if ($Kind -eq 'bool') {
        if ($type -ne 1 -or $bytes.Length -ne 8 -or (Read-SmokeU32 $bytes 4) -gt 1) { throw "Invalid packed bool: $Key" }
        return [bool](Read-SmokeU32 $bytes 4)
    }
    if ($type -ne 4) { throw "Invalid packed string: $Key" }
    $length = [int](Read-SmokeU32 $bytes 4)
    if ($length -gt $bytes.Length - 8 -or $bytes.Length - 8 - $length -gt 3) { throw "Invalid string bounds: $Key" }
    return $script:SmokeUtf8.GetString($bytes, 8, $length)
}

function Get-SmokeUserDataRelative($Settings) {
    $sensitive = @('application/config/name', 'application/config/use_custom_user_dir', 'application/config/custom_user_dir_name', 'application/config/project_settings_override')
    foreach ($key in $Settings.Keys) {
        foreach ($prefix in $sensitive) { if ($key.StartsWith($prefix + '.', [StringComparison]::Ordinal)) { throw "Feature-specific data path is unsupported: $key" } }
    }
    if ((Read-SmokeSetting $Settings 'application/config/version' '' 'string') -cne '0.14.0') { throw 'Expected the final v0.14.0 artifact; old exports are refused.' }
    if ((Read-SmokeSetting $Settings 'application/config/project_settings_override' '' 'string')) { throw 'External settings override is unsupported.' }
    $name = Read-SmokeSetting $Settings 'application/config/name' '' 'string'
    if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/:*?"<>|\x00-\x1f]' -or $name.Trim() -cne $name -or $name.EndsWith('.') -or $name -in @('.', '..')) { throw 'Project name requires unsupported Godot sanitization.' }
    $relative = Join-Path 'Godot\app_userdata' $name
    if (Read-SmokeSetting $Settings 'application/config/use_custom_user_dir' $false 'bool') {
        $custom = Read-SmokeSetting $Settings 'application/config/custom_user_dir_name' '' 'string'
        if (-not $custom) { $custom = $name }
        if ($custom -match '[:*?"<>|\x00-\x1f]' -or $custom.StartsWith('/') -or $custom.StartsWith('\')) { throw 'Custom userdata path cannot be proved relative.' }
        foreach ($part in ($custom -split '[\\/]')) {
            if (-not $part -or $part -in @('.', '..') -or $part.Contains('..') -or $part.Trim() -cne $part -or $part.EndsWith('.')) { throw 'Custom userdata path requires unsupported sanitization.' }
        }
        $relative = $custom.Replace('/', '\')
    }
    return $relative
}

function Get-SmokeLogErrors([string[]]$Paths) {
    $errors = [Collections.Generic.List[object]]::new()
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $index = 0
        foreach ($line in [IO.File]::ReadLines($path)) {
            $index++
            $scan = $line -replace '\x1b\[[0-9;]*[A-Za-z]', ''
            if ($scan -match '(?i)(^|\s)(SCRIPT ERROR|ERROR|FATAL)(:|\s)|Unhandled exception|crash|Failed to (?:read|load).*(?:certificate|root)|CERT_E_|SEC_E_') {
                $errors.Add(@{ log = [IO.Path]::GetFileName($path); line = $index; text = $line })
            }
        }
    }
    return $errors.ToArray()
}

if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $IsWindows) { throw 'Windows is required.' }

$before = @{}
foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'HOME', 'USERPROFILE', 'TEMP', 'TMP')) { $before[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$root = New-SmokeSandbox $SandboxParent
$reportPath = Join-Path $root 'report.json'
$report = [ordered]@{
    schema = 1; status = 'preflight'; started_at_utc = [DateTime]::UtcNow.ToString('o')
    artifact_url = $ArtifactUrl; expected_sha256 = $ExpectedSha256; actual_sha256 = $null
    artifact_version = '0.14.0'; sandbox = $root; executable = $Executable
    official_archive_url = $script:OfficialArchiveUrl; official_archive_sha256 = $script:OfficialArchiveSha256
    isolation_verified = $false; isolation_kind = 'offline official-template identity and packed settings plus child-only APPDATA'
    user_data_dir = $null; process_started = $false; process = $null; strict_log_clean = $false
    parent_environment_unchanged = $false; input_unchanged = $false; errors = @(); refusal_reason = $null
    display_mode = $DisplayMode; visual_qa = 'not performed'; product_smoke_passed = $false
}
$exit = 78
$inputStream = $null
$archiveStream = $null
$stagedLock = $null
$archive = $null
try {
    if (-not $Executable -or $ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$' -or $ArtifactUrl -notmatch '^https://') { throw 'Exact final v0.14 EXE path, SHA256 and HTTPS artifact URL are required. Nothing was launched.' }
    $resolved = Assert-SmokeLocalPath $Executable
    $report['resolved_input'] = $resolved
    if ([IO.Path]::GetExtension($resolved) -ine '.exe') { throw 'Executable must be a literal .exe file path.' }
    Assert-SmokeSecurityMark $resolved
    # Keep the input locked against replacement/write/delete until shutdown.
    $inputStream = [IO.File]::Open($resolved, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $report.actual_sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($inputStream)).ToLowerInvariant()
    if ($report.actual_sha256 -ine $ExpectedSha256) { throw 'Artifact SHA256 mismatch. Nothing was launched.' }
    if (-not $OfficialTemplatesArchive) { throw 'Isolation unproven: the original official 4.6.3 templates TPZ is required for offline binary identity. Extracted templates or a claimed engine version alone are insufficient.' }
    $archivePath = Assert-SmokeLocalPath $OfficialTemplatesArchive
    $archiveStream = [IO.File]::Open($archivePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($archiveStream)).ToLowerInvariant()
    if ($digest -cne $script:OfficialArchiveSha256) { throw 'Official templates archive SHA256 mismatch. Isolation unproven; no launch.' }
    $archiveStream.Position = 0
    $archive = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Read, $true)
    $entries = @($archive.Entries | Where-Object FullName -CEQ 'templates/windows_release_x86_64.exe')
    if ($entries.Count -ne 1 -or $entries[0].Length -gt 268435456) { throw 'Official Windows release x86_64 template missing/oversized.' }
    $memory = [IO.MemoryStream]::new()
    $entryStream = $entries[0].Open()
    try { $entryStream.CopyTo($memory); $template = $memory.ToArray() } finally { $entryStream.Dispose(); $memory.Dispose() }
    $inputStream.Position = 0
    if ($inputStream.Length -gt 1073741824) { throw 'Artifact exceeds the 1 GiB smoke limit.' }
    $memory = [IO.MemoryStream]::new()
    try { $inputStream.CopyTo($memory); $bytes = $memory.ToArray() } finally { $memory.Dispose() }
    $report['template_verification'] = Assert-SmokeTemplate $bytes $template
    $packed = Get-SmokePackedSettings $bytes
    if ($packed.pack_start -lt $template.Length -or $packed.pack_start -gt $template.Length + 7) { throw 'Unexpected PCK placement.' }
    for ($i = $template.Length; $i -lt $packed.pack_start; $i++) { if ($bytes[$i] -ne 0) { throw 'Nonzero executable/PCK padding.' } }
    $report['project_binary_sha256'] = $packed.project_binary_sha256
    $report['pck_file_count'] = $packed.file_count
    $relative = Get-SmokeUserDataRelative $packed.settings
    $childEnvironment = Get-SmokeChildEnvironment $root
    $report.user_data_dir = Assert-SmokeInside (Join-Path $childEnvironment['APPDATA'] $relative) $root
    $report.isolation_verified = $true
    $report['isolation_sources'] = @(
        'https://github.com/godotengine/godot/blob/4.6.3-stable/platform/windows/os_windows.cpp#L2252-L2261',
        'https://github.com/godotengine/godot/blob/4.6.3-stable/core/os/os.cpp#L317-L332'
    )
    $report['child_environment_overrides'] = @{ APPDATA = $childEnvironment['APPDATA']; LOCALAPPDATA = $childEnvironment['LOCALAPPDATA']; TEMP = $childEnvironment['TEMP']; TMP = $childEnvironment['TMP'] }
    if ($PreflightOnly) { $report.status = 'preflight_ready'; $exit = 0 }
    else {
        $stage = Assert-SmokeInside (Join-Path $root 'product\GodotGame.exe') $root
        # CopyFile preserves Windows alternate streams; both input and copy are checked.
        [IO.File]::Copy($resolved, $stage, $false)
        Assert-SmokeSecurityMark $stage
        $stagedLock = [IO.File]::Open($stage, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stagedLock)) -ine $ExpectedSha256) { throw 'Staged artifact SHA256 mismatch; no launch.' }
        $stdout = Join-Path $root 'logs\stdout.log'
        $stderr = Join-Path $root 'logs\stderr.log'
        $engineLog = Join-Path $root 'logs\godot.log'
        $arguments = @('--verbose', '--quit-after', [string]$QuitAfter, '--log-file', $engineLog)
        if ($DisplayMode -eq 'Headless') { $arguments += '--headless' } else { $arguments += @('--windowed', '--audio-driver', 'Dummy') }
        $report['arguments'] = $arguments
        $report.status = 'running'
        [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 12), $script:SmokeUtf8)
        Initialize-SmokeNative
        $exit = 70
        $run = [ExportSmoke.Native]::Run($stage, [string[]]$arguments, (Join-Path $root 'product'), $childEnvironment, $stdout, $stderr, $TimeoutSeconds * 1000)
        $report.process = $run
        $report.process_started = $run.Resumed
        if ($run.Error -or $run.CleanupError) { throw "Owned process runner failed: $($run.Error) $($run.CleanupError)" }
        $report.errors = @(Get-SmokeLogErrors @($stdout, $stderr, $engineLog))
        $report.strict_log_clean = $report.errors.Count -eq 0
        $report['userdata_created_in_sandbox'] = Test-Path -LiteralPath $report.user_data_dir -PathType Container
        $report['engine_log_created'] = Test-Path -LiteralPath $engineLog -PathType Leaf
        $banner = [IO.File]::ReadAllText($stdout) + [IO.File]::ReadAllText($stderr)
        if (Test-Path -LiteralPath $engineLog) { $banner += [IO.File]::ReadAllText($engineLog) }
        $report['expected_engine_banner'] = $banner -match 'Godot Engine v4\.6\.3\.stable\.official'
        if ($run.TimedOut) { $report.status = 'timeout'; $exit = 124 }
        elseif ($run.ExitCode -ne 0 -or $run.ActiveAfterRootExit -ne 0 -or $run.ActiveAfterCleanup -ne 0 -or -not $report.strict_log_clean -or
            -not $report.userdata_created_in_sandbox -or -not $report.engine_log_created -or -not $report.expected_engine_banner) { $report.status = 'failed'; $exit = 1 }
        else { $report.status = 'passed'; $report.product_smoke_passed = $true; $exit = 0 }
    }
} catch {
    $report.refusal_reason = $_.Exception.Message
    $report.status = if ($exit -eq 78) { 'refused' } else { 'runner_error' }
} finally {
    if ($inputStream) {
        $inputStream.Position = 0
        $report.input_unchanged = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($inputStream)) -ieq $report.actual_sha256
    }
    $report.parent_environment_unchanged = $true
    foreach ($name in $before.Keys) { if ($before[$name] -cne [Environment]::GetEnvironmentVariable($name, 'Process')) { $report.parent_environment_unchanged = $false } }
    if (-not $report.parent_environment_unchanged -or ($inputStream -and -not $report.input_unchanged)) { $report.status = 'runner_error'; $report.product_smoke_passed = $false; $exit = 70 }
    if ($stagedLock) { $stagedLock.Dispose() }
    if ($archive) { $archive.Dispose() }
    if ($archiveStream) { $archiveStream.Dispose() }
    if ($inputStream) { $inputStream.Dispose() }
    $report['finished_at_utc'] = [DateTime]::UtcNow.ToString('o')
    $report['runner_exit_code'] = $exit
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 12), $script:SmokeUtf8)
}
Write-Output ($report | ConvertTo-Json -Depth 12 -Compress)
Write-Output "Report: $reportPath"
exit $exit
