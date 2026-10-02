# Windows ������Ʒ��ȫ��������

������ֱ�Ӽ�顢�������� `GodotGame.exe`����Դ���� headless �ع顢�浵ר�֤����Ϻ��Ƶ�������ֱ��¼�������������ذ����������յ� v0.14 ˽�� draft �ʲ���Ϣ������Զ��Ԫ���ݣ���δȡ�ñ�����Ʒ�ֽڣ�û�������κ���Ϸ��Ʒ��Ҳû�����ػ����о� v0.13��

## ��ǰ����뽻��

- ����������`tools/windows/smoke_export.ps1`��
- �޺��оߣ�`tests/windows/export_smoke_fixture.cs`��`tests/windows/export_smoke_test.ps1`��
- 2026-10-02 17:07:24 UTC������ PowerShell 7.6.5��**76 ���飬0 ʧ��**��
- ԭʼ֤�ݣ�`C:\Users\ZQS\AppData\Local\Temp\godot-export-smoke-6222646071ee475fa5acf88ed0a137c4\fixture-report.json`��ÿ����Ŀ¼���� `owned-process.json`��stdout��stderr����ʱ·�������������ˣ����ǲֿ���Դ��
- ���� `product_executed=false`��`godot_isolation_runtime_proved=false`���оߵĻ������ݺͽ�������ͨ�������ܾݴ��������� Godot ��Ʒ��ͨ����
- ��ͨ����Ȩ GitHub���Ӷ��� release **402009592**��`draft=true`��tag `v0.14.0`��ָ������ȷ�ϵ� commit `2b8604c740495a810ddcec2431dbb0717427da2c`���ʲ� **606091690**Ϊ `GodotGame-v0.14.0-windows-x86_64.zip`����С **58,691,372�ֽ�**��API digestΪ `sha256:b15cd9a12e6e5a9f6d700ed16efd48e4b0b0b57e8afd4454e0a80b821063b500`�����븸��������һ�£�**����Զ��Ԫ���ݺ��飬���������ֽڹ�ϣ����**��
- ֹͣ��1�������ٷ� `gh api repos/zqs1223041447/godot-game`�����ʲ���ȡ������ HTTP 404����ǰ `gh auth status`�����䱾��Ĭ���˺�ƾ�ݲ����á�GitHub�����ܶ�Ԫ���ݡ��ύ��֧�����������ӵ�ͨ�� fetch��֧�ֶ��������ء�δ��ȡ/Ǩ�� token���޸ĵ�¼���ر� TLS��֤��α���������ض˵㡣
- ֹͣ��2��û���ṩԭʼ�ٷ� 4.6.3ģ�� TPZ�Ŀɶ�·��������鱾�� TEMPֱ���ļ��ͳ��� Godotģ��λ�ã�δ���ֿ������롣û������1.25GBģ��鵵��ֻ�н�ѹ���ģ�� EXE�����԰󶨹鵵���ݡ�
- ����������ͨ������������Ȩ�Ĺٷ� `gh`���� [asset 606091690](https://api.github.com/repos/zqs1223041447/godot-game/releases/assets/606091690)���Ⱥ˶� ZIP�ֽڹ�ϣ���ڶ�����ʱĿ¼��ȫ�����ȡ��׼ȷ EXE SHA256�ͱ���·�����ṩԭʼ�ٷ�ģ�� TPZ·���������������Ԥ��/��Ʒ�����ǰû�� EXE��ϣ�����ܰ� ZIP��ϣ���� `ExpectedSha256`�������������˵��ȱʧ��ܾ���������ʹ��Դ���������

δǿ������״̬�µ��˹� GUI ������Ĭ�� headless ����ʵ�ʵ��� EXE��ͨ�������뵥����¼�ɽ������ڡ����ơ���������Ϸ�������ա�

## Ϊʲô�ܹ����� Godot �� user://

[Godot ����·���ĵ�](https://docs.godotengine.org/en/4.6/tutorials/io/data_paths.html)���� Windows Ĭ�� `user://` λ��Ӧ������Ŀ¼�¡����ı乤��Ŀ¼��ʹ�� `--log-file` ������ı�����`--quit-after` Ҳ������ֹ��ʼ��ʱ��д�浵��[4.6 �������ĵ�](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html)��˵��δ֪�������ܱ���Ĭ���ԣ���˱���������ʹ���ܲ�� `--user-data-dir`��

�������ݰ󶨵� **4.6.3 ԭ���׼ release x86_64 ģ��**�����Ǵ���Ŀ������ `config/features` �²⣺

1. [4.6.3 Windows Դ��](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/windows/os_windows.cpp#L2252-L2261)�� `get_config_path()` ��ȡ��ǰ���� `APPDATA`��`get_data_path()` ���ظ�·����[get_user_data_dir(p_user_dir)](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/windows/os_windows.cpp#L2338-L2340)��������ƴ����ĿĿ¼�������� `get_system_dir()` ��ʹ�õ� Known Folder API��ͬ��
2. [OS::get_user_data_dir()](https://github.com/godotengine/godot/blob/4.6.3-stable/core/os/os.cpp#L317-L332)���ݴ����Ӧ�������Զ���Ŀ¼����ѡ�����Ŀ¼��������ֻ������**ʵ�� EXE ��** PCK v3�� `project.binary` / ECFG��������� MD5�����ӱ��� `project.godot` �ƶ���Ʒ���á�
3. ��������ʽУ��ԭʼ�ٷ� TPZ�Ĺ̶� SHA256��Ȼ��ӹ鵵ֱ�Ӷ�ȡ `templates/windows_release_x86_64.exe`���Գ�Ʒ��ģ��ȫ�������ֽ���ֻ���Ƚϣ��������롢���ݡ��������Դ��ֻ���� [�ٷ� fixup_embedded_pck](https://github.com/godotengine/godot/blob/4.6.3-stable/platform/windows/export/export_plugin.cpp)����� PEͷ�ֶβ��졣�����ƶ���ǰһ�� virtual size��image size��ĩβ pck�ڵľ���ֵ���������������� PEͷ��**���޸ġ�patch ����д��һ��Ʒ/ģ������ơ�**
4. ��������������� EXE SHA256������ȫƥ�䡣�����ļ���鵵����ֻ���������������ٴκ˶Թ�ϣ������ֻ������ֱ�����̽�����
5. `CreateProcessW` ���ն��������飬ֻ���������� `APPDATA`��`LOCALAPPDATA`��`TEMP`��`TMP` ��Ψһ�½�ɳ�䡣���������޸ĸ����̻�ϵͳ/�û��־û��������޸� `HOME`��`USERPROFILE`�����鿴������ʵ�浵���ӽ��̼̳���Щ��ʱֵ����������֤�����̻���δ�ı䡣

��ǰ v0.14 ��Ŀ��Ϊ `godot��Ϸ��`��δ�����Զ��� userdataĿ¼��������������ʱ��Ԥ��Ŀ¼Ϊ��

```text
<Ψһɳ��>\roaming\Godot\app_userdata\godot��Ϸ��
```

����ʵ�ʰ���ȡ��һ���ƣ������øı䡢������·������������ feature tag���ǡ�����·��/�������Զ������桢�ⲿ���û�ԭ����չ��δ�������Σ��������ܾ�������PCK���ܡ������汾��ȱ�� ECFG���Ǳ�׼Ƕ�벼�֡�ģ��鵵���ɶ������ݲ���Ҳ��ܾ���

���ǶԱ���Ʒ Godot `user://` �ľ�̬����֤�������̻������룬���� AppContainer�������������ȫ�ļ�ϵͳȨ��ɳ�䡣���к󻹼��������Ԥ����ʱ userdataĿ¼�Ĵ�����Ԥ�ڰ汾 banner��ָ����־�������е� `isolation_verified` ָ����ǰ��������̬֤����`product_smoke_passed` ֻ���������гɹ��������ż�ͨ����Ϊ true��δͨ��֤��ʱ�� `--help` / `--version` ����ִ�С�

## �ٷ��鵵����

�̶���Դ��[Godot 4.6.3 ��׼ģ��](https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz)��2026-10-02ͨ��[�ٷ� release API](https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.6.3-stable)��ȡ asset 425482597�� SHA256 digest���̶�Ϊ��

```text
3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8
```

�鵵ԭʼ��С 1,255,918,323�ֽڡ��������������ظù鵵����� TLS����֤�����ã���ʹ��������������ȡ��ԭʼ�鵵��ȱʧʱ��ȷ����78���������ģ��汾�������²�֤�ٷ�Դ��/�鵵���ݲ����������������ܽ����İ汾�ַ������С�

## ���з�ʽ

�������޺��оߣ�����Ҫ Godot���κ���Ϸ����

```powershell
pwsh -NoProfile -NonInteractive -File .\tests\windows\export_smoke_test.ps1
```

����ʹ�ñ��� .NET Framework C#������������ʱ�о� EXE���������װ��������������/�ո�/������·����˫���š�β��б�ߡ��ղ��������к� shellԪ�ַ�ԭ�����ݣ���/�����˳����������� stdout/stderr��ԭ��֤����ű�����ANSI��ɫ���󡢳�ʱ�����������˳����ӽ����������޹ؼоߴ������������������䡢PCK/ECFG·���ܾ�����ʽ�Ƚϡ�PE�ֽڶԱȵ����������Ǵ��㹹���δִ�и�ʽ���飬�����޸ĺ�� Godot�����ơ�

�õ����հ������������ EXE��ϣ����ֻ������Ԥ�졣�����Ǵ�ռλ���Ľ��������������ִ�еľɺ�ѡ��ַ��

```powershell
$params = @{
    Executable = 'C:\QA\final v0.14\GodotGame.exe'
    ExpectedSha256 = '<���������������EXE��64λʮ������SHA256>'
    ArtifactUrl = '<���������������HTTPS artifact URL>'
    OfficialTemplatesArchive = 'C:\QA\Godot_v4.6.3-stable_export_templates.tpz'
    TimeoutSeconds = 30
    QuitAfter = 120
}
& .\tools\windows\smoke_export.ps1 @params -PreflightOnly
```

`preflight_ready` / �˳�0ֻ��ʾ����Ԥ����ͨ����**����ʾ��Ʒ����ͨ��**����ʽ��Ʒ����ʹ��ͬһ�����ȥ�� `-PreflightOnly`��

```powershell
& .\tools\windows\smoke_export.ps1 @params
```

Ĭ�ϲ����� `--verbose --quit-after 120 --log-file <ɳ����־> --headless`��exe·����ÿ�������� Windows CRT����ֱ����ã�ֱ�ӵ��� Win32 API������ shell���͡�120�������������30���Ƕ���ǽ�ӳ�ʱ�����ܰ�120��������Ϊ120֡�������ա�

�������������ʽ����ȫ�ż�������ʱ���ɼ� `-DisplayMode Windowed`������������ `--windowed --audio-driver Dummy`�������Զ��˳���ֻ�ṩ��Ʒ����/��־/�ر�֤�ݣ����Զ������˹� UI������ɡ�

ÿ���½� `%TEMP%\godot-export-smoke-<GUID>`������������ɳ�䡣�����ƾ�ȷԭ�ֽڵ� EXE���� `product` Ŀ¼��������Դ���̡��ⲿ override����� PCK������ DLL������֤�ݼ���ʱ userdata���������Զ��ݹ�ɾ����

## �����밲ȫ�ż�

[Windows �ӽ����ĵ�](https://learn.microsoft.com/en-us/windows/win32/procthread/child-processes)˵�������½����ṩר�û����顣[Job Object�ĵ�](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)˵���ӽ��̹�����ر��������ơ����������ã�

- �Ƚ����Լ������� Job������ `KILL_ON_JOB_CLOSE`�������� breakaway��
- �� suspended״̬����Ŀ�꣬�ɹ����䵽 Job��� resume������ʧ��ֻ�ر��Լ������� suspended���̡�
- `STARTUPINFOEX`ֻ���� stdin��stdout��stderr������ȷ����̳У�Job����������ӽ��̡�
- ��¼�� PID����ȷ�˳��롢��ʱ��Job����ǰ PID�б��������� active������Windows�����Զ����� console host���ʲ��ٶ�����+�ӡ�ǡ���������̡�
- �����˳��� Job�� helper���500ms�˳����ޡ��Դ����������̻ᱻ������ʹ��������ʧ�ܣ���ʱ����ֹ�������� Job���ȴ� active=0��û�а����Ʋ�ɱ��ȫ�� Godotö�١�`Stop-Process` �� `taskkill`��
- CreateProcess/Job���ƻ�ϵͳ��ȫ�ܾ�ԭ�����뱨�棬����Ȩ���������ƹ������� `Zone.Identifier`ֱ�Ӿܾ������Ƴ� Mark-of-the-Web����ʹ�� `Unblock-File`������ֱ�� Win32�����ƹ� Explorer�� SmartScreen�����˹�����/��ȫ���治��������������

## ��־���˳�������շ�Χ

`logs/stdout.log`��`logs/stderr.log`��`logs/godot.log`����ԭʼ���ݣ�`report.json`��¼��Ӧ�����С�stdout/stderrֱ�����ļ������� pipe�������������ANSI�Ƴ������ڴ���ʶ�𣬱����ԭʼ��־�Ա���ԭ�ġ�

| runner�˳��� | ״̬ | ���� |
| --- | --- | --- |
| 0 | `passed` | ��������ʵ��Ʒ����̬���롢�˳�0���汾banner����־����ʱuserdata��ȫ�����̹ر�ͨ�������޴��� |
| 0 | `preflight_ready` | ֻ�������Ԥ�죬`product_smoke_passed=false` |
| 78 | `refused` | ��ϣ/��Դ/ģ��/·��/�������/��ȫ��ǵ��ż�δͨ������������Ʒ |
| 124 | `timeout` | ʵ��������ʱ������ Job������������ͨ������ |
| 1 | `failed` | �����Ʒ�˳��������ӽ��̡�������־��ȱʧ����֤�� |
| 70 | `runner_error` | ��������Win32�򻷾�/����һ���Լ��ʧ�� |

`ERROR`��`SCRIPT ERROR`��fatal��crash����֤��ʧ�������ϵͳ�������ͨ����û�а������򽵼����ء�����������ϵ��ĸ�֤����󲻱�����������Ҳ�����˳�0��������ܿ��ö��ſ��ż���

������ʵ�������׷���� URL��SHA256������ reportλ�á��˳��롢`isolation_verified`��`product_smoke_passed`����־����δ��ɵ� GUI��Ŀ��Ŀǰ��Щ��Ʒ����֤���Դ����������ñ���76��о߼�������
