// Harmless fixture. No Godot, network, registry, or real user-data access.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

public class ExportSmokeFixture {
    // Construct unexecuted PE-shaped arrays from scratch. These are format
    // fixtures, not altered engine, template, or game binaries.
    static void U16(byte[] data,int offset,ushort value) { BitConverter.GetBytes(value).CopyTo(data,offset); }
    static void U32(byte[] data,int offset,uint value) { BitConverter.GetBytes(value).CopyTo(data,offset); }
    static void Section(byte[] data,int index,string name,uint virtualSize,uint address,uint size,uint raw,uint flags) {
        int p=392+index*40; Encoding.ASCII.GetBytes(name).CopyTo(data,p);
        U32(data,p+8,virtualSize); U32(data,p+12,address); U32(data,p+16,size); U32(data,p+20,raw); U32(data,p+36,flags);
    }
    public static byte[] PeFixture(bool exported,bool differentCode,bool differentHeader) {
        var data=new byte[exported ? 1100 : 1024]; data[0]=77; data[1]=90;
        U32(data,60,128); U32(data,128,17744); U16(data,132,0x8664); U16(data,134,3); U16(data,148,240);
        U16(data,152,0x20b); U32(data,184,0x1000); U32(data,208,exported ? 0x5000u : 0x4000u);
        Section(data,0,".text",exported ? 0x1100u : 0x100u,0x1000,256,512,0x60000020);
        if(exported) {
            Section(data,1,".rdata",0x100,0x3000,256,768,0x40000040);
            Section(data,2,"pck",8,0x4000,76,1024,differentHeader ? 0x60000000u : 0x40000000u);
        } else {
            Section(data,1,"pck",1,0x2000,0,0,0x40000000);
            Section(data,2,".rdata",0x100,0x3000,256,768,0x40000040);
        }
        for(int i=512;i<1024;i++) data[i]=(byte)((i*13)%251);
        if(differentCode) data[600]=0;
        return data;
    }
    static int Main(string[] args) {
        string appdata=Environment.GetEnvironmentVariable("APPDATA");
        if(String.IsNullOrEmpty(appdata) || appdata.IndexOf("godot-export-smoke-",StringComparison.Ordinal)<0 ||
            !appdata.EndsWith("roaming",StringComparison.Ordinal)) return 79;
        string root=Path.GetDirectoryName(appdata);
        string mode=args.Length>0 ? args[0] : "echo";
        if(mode=="child") {
            File.WriteAllText(Path.Combine(root,"child-ready-"+Process.GetCurrentProcess().Id),"fixture only");
            Thread.Sleep(30000); return 0;
        }
        if(mode=="timeout" || mode=="orphan") {
            var psi=new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"child");
            psi.UseShellExecute=false; psi.CreateNoWindow=true;
            using(var child=Process.Start(psi)) {
                string ready=Path.Combine(root,"child-ready-"+child.Id);
                for(int i=0;i<150 && !File.Exists(ready);i++) Thread.Sleep(20);
                if(!File.Exists(ready)) return 80;
                File.WriteAllText(Path.Combine(root,"child-pid.txt"),child.Id.ToString());
                if(mode=="orphan") return 0;
                Thread.Sleep(30000); return 0;
            }
        }
        Directory.CreateDirectory(Path.Combine(appdata,"Godot","app_userdata","Fixture data"));
        File.WriteAllText(Path.Combine(appdata,"Godot","app_userdata","Fixture data","fixture.txt"),"synthetic data only");
        Console.WriteLine("FIXTURE_APPDATA:"+Convert.ToBase64String(Encoding.UTF8.GetBytes(appdata)));
        foreach(string arg in args) Console.WriteLine("FIXTURE_ARG:"+Convert.ToBase64String(Encoding.UTF8.GetBytes(arg)));
        Console.Error.WriteLine("FIXTURE_STDERR:kept raw");
        if(mode=="errors") {
            Console.Error.WriteLine("ERROR: Failed to read the root certificate store.");
            Console.Error.WriteLine("SCRIPT ERROR: fixture sentinel (expected only in this negative test)");
        }
        if(mode=="bulk") {
            string line=new string('x',8192);
            for(int i=0;i<32;i++) { Console.WriteLine(line); Console.Error.WriteLine(line); }
        }
        return mode=="exit7" ? 7 : 0;
    }
}
