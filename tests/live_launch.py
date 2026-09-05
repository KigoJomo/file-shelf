"""Opt-in live desktop check. Opens and closes only temporary test windows.

Run from the repository root in an idle Hyprland session. Uses the installed
Nautilus service and an isolated File Shelf state directory under /tmp.
"""
import json, os, subprocess, tempfile, time
from pathlib import Path
helper=str(Path(__file__).resolve().parents[1] / 'bin/file-shelf-nautilus')
def run(*args):return subprocess.check_output(args,text=True).strip()
def clients():return json.loads(run('hyprctl','clients','-j'))
def locations():return json.loads(run('busctl','--user','--json=short','get-property','org.gnome.Nautilus','/org/freedesktop/FileManager1','org.freedesktop.FileManager1','OpenWindowsWithLocations'))['data']
def close(a):
    run('hyprctl','dispatch',f'hl.dsp.window.close({{ window = "address:{a}" }})')
    for _ in range(40):
        if not any(c['address']==a for c in clients()):return
        time.sleep(.05)
    raise AssertionError('test window did not close')
original_active=json.loads(run('hyprctl','activewindow','-j')).get('address')
root=Path(tempfile.mkdtemp(prefix='file-shelf-race-'))
for iteration, delay in enumerate([-.15,0,.15]):
    before={c['address']:{k:c[k] for k in ('pid','workspace','floating','tags')} for c in clients()}
    env=dict(os.environ,XDG_STATE_HOME=str(root/f'state-{iteration}'))
    folder=root/f'Ordinary-files-{iteration}';folder.mkdir()
    if delay<0:
        normal=subprocess.Popen(['nautilus','--new-window',str(folder)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        time.sleep(-delay)
    started=time.monotonic()
    shelf=subprocess.Popen([helper,'show','right'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    if delay>=0:
        time.sleep(delay)
        normal=subprocess.Popen(['nautilus','--new-window',str(folder)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    out,err=shelf.communicate(timeout=20)
    assert shelf.returncode==0,(out,err)
    elapsed=time.monotonic()-started
    identity=json.loads((root/f'state-{iteration}/omarchy/file-shelf.window').read_text())
    address=identity['address']
    snapshot=clients()
    managed=next(c for c in snapshot if c['address']==address)
    ordinary=next(c for c in snapshot if c['class']=='org.gnome.Nautilus' and c['title']==folder.name)
    assert ordinary['address']!=address
    assert 'kigojomo-file-shelf' not in ordinary['tags']
    assert ordinary['workspace']['name']!='special:file-shelf'
    assert managed['title']=='Home'
    assert 'kigojomo-file-shelf' in managed['tags']
    assert any(v==[folder.as_uri()] for v in locations().values())
    for c in snapshot:
        if c['address'] in before:
            assert {k:c[k] for k in before[c['address']]}==before[c['address']],('existing window changed',c['address'])
    print(f'PASS competing launch offset {delay:+.2f}s, shared Nautilus PID {managed["pid"]}, shelf ready in {elapsed:.2f}s',flush=True)
    subprocess.run([helper,'hide'],env=env,check=True,capture_output=True)
    close(address);close(ordinary['address'])
    normal.wait(timeout=5)
if original_active and any(c['address']==original_active for c in clients()):
    run('hyprctl','dispatch',f'hl.dsp.focus({{ window = "address:{original_active}" }})')
print('PASS all existing windows preserved',flush=True)
