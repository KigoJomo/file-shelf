"""Run the real helper against a stateful fake compositor. No desktop changes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'bin/file-shelf-nautilus'
MOCK = r'''#!/usr/bin/env python3
import json, os, re, sys
from pathlib import Path
p = Path(os.environ['MOCK_STATE'])
s = json.loads(p.read_text())
args = sys.argv[1:]
name = Path(sys.argv[0]).name
if name == 'busctl':
    args = [a for a in args if not a.startswith('--')]
    def emit(kind, data): print(json.dumps({'type': kind, 'data': data}))
    if 'StartServiceByName' in args:
        if s.get('fail_activation'): sys.exit(1)
        emit('u', [1])
    elif 'GetNameOwner' in args: emit('s', [':1.42'])
    elif 'GetConnectionUnixProcessID' in args: emit('u', [789])
    elif args[0] == 'get-property':
        if s.get('owner_gone'): sys.exit(1)
        emit('a{sas}', s.get('locations', {}))
    elif 'Open' in args:
        from urllib.parse import urlparse, unquote
        uri = args[-3]
        title = Path(unquote(urlparse(uri).path)).name
        s.setdefault('requests', []).append(args)
        c = {'address': '0xc', 'pid': 789, 'class': 'org.gnome.Nautilus',
             'title': title, 'initialTitle': 'Loading...', 'tags': [],
             'floating': False, 'workspace': {'name': '3'}}
        s['bootstrap'] = c
        s['bootstrap_uri'] = uri
        s['locations'] = {'/org/gnome/Nautilus/window/20': [uri]}
        s['clients'] += s.get('other_new_clients', [])
        if not s.get('delay_bootstrap'):
            s['clients'].append(s.pop('bootstrap'))
        if s.get('duplicate_token'):
            s['clients'].append(dict(c, address='0xd'))
            s['locations']['/org/gnome/Nautilus/window/21'] = [uri]
        if s.get('fail_open_after_delivery'):
            p.write_text(json.dumps(s)); sys.exit(1)
    elif 'List' in args:
        emit('as', [['go-home', 'new-tab', 'close-other-tabs'] if not s.get('missing_actions') else []])
    elif 'Activate' in args:
        action = args[-3]
        if s.get('fail_action') == action:
            sys.exit(1)
        path = args[2]
        s.setdefault('actions', []).append([args[1], path, action])
        if action == 'go-home':
            if s.get('preserve_bootstrap_file'):
                from urllib.parse import urlparse, unquote
                (Path(unquote(urlparse(s['bootstrap_uri']).path)) / 'user-note.txt').write_text('keep this')
            s['locations'][path] = [Path(os.environ['HOME']).as_uri()]
            for c in s['clients']:
                if c['address'] == '0xc': c['title'] = 'Home'
        elif action == 'new-tab':
            s['locations'][path] *= 2
        elif action == 'close-other-tabs':
            s['locations'][path] = s['locations'][path][-1:]
    else: sys.exit(1)
    p.write_text(json.dumps(s))
    sys.exit(0)
if args[0] == 'clients':
    if s.get('query_fail'): sys.exit(1)
    s['polls'] = s.get('polls', 0) + 1
    if s.get('bootstrap') and s['polls'] >= s.get('delay_bootstrap', 0):
        s['clients'].append(s.pop('bootstrap'))
    p.write_text(json.dumps(s))
    print(json.dumps(s['clients']))
elif args[0] == 'monitors': print(json.dumps(s['monitors']))
elif args[0] == 'activewindow': print(json.dumps(s.get('active', {})))
elif args[0] in ('dispatch', 'eval'):
    command = ' '.join(args[1:])
    s.setdefault('dispatches', []).append(command)
    p.write_text(json.dumps(s))
    if s.get('dispatch_fail') or (args[0] == 'eval' and s.get('recycled_before_tag')): sys.exit(1)
    address = re.search(r'address:(0x[0-9a-f]+)', command)[1]
    client = next(c for c in s['clients'] if c['address'] == address)
    if 'workspace = ' in command:
        workspace = re.search(r'workspace = "([^"]+)"', command)[1]
        client['workspace'] = {'name': workspace}
    if 'window.tag' in command or 'tagwindow' in command:
        client.setdefault('tags', []).append('kigojomo-file-shelf')
    if 'window.float' in command or 'togglefloating' in command:
        client['floating'] = True
    p.write_text(json.dumps(s))
    print('ok')
else: sys.exit(1)
'''

def client(address='0xa', pid=123, workspace='special:file-shelf', cls='org.gnome.Nautilus'):
    return dict(address=address, pid=pid, workspace={'name': workspace},
                floating=True, tags=['kigojomo-file-shelf'], **{'class': cls})

class HelperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.state = self.root / 'mock.json'
        self.identity = self.root / 'omarchy/file-shelf.window'
        self.identity.parent.mkdir()
        self.env = dict(os.environ, PATH=f'{self.root}:' + os.environ['PATH'],
                        XDG_STATE_HOME=str(self.root), HYPRLAND_INSTANCE_SIGNATURE='test-session',
                        MOCK_STATE=str(self.state))
        for name in ('hyprctl', 'busctl'):
            (self.root / name).write_text(MOCK)
            (self.root / name).chmod(0o755)
        # Polling delays protect the real desktop, but add no value with the
        # deterministic fake compositor and D-Bus service.
        (self.root / 'sleep').write_text('#!/bin/sh\nexit 0\n')
        (self.root / 'sleep').chmod(0o755)
        self.data = dict(clients=[client()], monitors=[dict(name='TEST', disabled=False,
            focused=True, x=0, y=0, width=1920, height=1080, scale=1, transform=0,
            reserved=[0,20,0,0], activeWorkspace={'id': 3}, specialWorkspace={'name': ''})])
        self.identity.write_text(json.dumps(dict(address='0xa', pid=123, instance='test-session')))

    def run_helper(self, *args):
        self.state.write_text(json.dumps(self.data))
        result = subprocess.run([str(HELPER), *args], env=self.env, text=True,
                                capture_output=True, timeout=15)
        self.data = json.loads(self.state.read_text())
        return result

    def test_reuses_only_owned_window_and_respects_reserved_bar(self):
        self.data['clients'].append(client('0xb', 456, '3'))
        r = self.run_helper('show', 'right', 'TEST')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), 'open')
        commands = self.data['dispatches']
        self.assertTrue(any('exact 844 1028,address:0xa' in c for c in commands))
        self.assertTrue(any('exact 1060 36,address:0xa' in c for c in commands))
        self.assertTrue(all('0xb' not in c for c in commands))

    def test_hide_parks_without_closing(self):
        r = self.run_helper('hide')
        self.assertEqual(r.stdout.strip(), 'hidden')
        self.assertEqual(len(self.data['clients']), 1)
        self.assertIn('special:file-shelf', self.data['dispatches'][0])

    def test_wrong_pid_session_class_and_legacy_state_are_not_owned(self):
        for identity, cls in [
            (dict(address='0xa', pid=456, instance='test-session'), 'org.gnome.Nautilus'),
            (dict(address='0xa', pid=123, instance='old-session'), 'org.gnome.Nautilus'),
            (dict(address='0xa', pid=123, instance='test-session'), 'other.app'),
            ('0xa', 'org.gnome.Nautilus'),
            (dict(address='0xa;echo pwned', pid=123, instance='test-session'), 'org.gnome.Nautilus')]:
            with self.subTest(identity=identity):
                self.identity.write_text(json.dumps(identity))
                self.data['clients'][0]['class'] = cls
                self.assertEqual(self.run_helper('hide').stdout.strip(), 'closed')
                self.assertFalse(self.data.get('dispatches'))

    def test_recycled_address_and_pid_without_window_tag_are_not_owned(self):
        self.data['clients'][0]['tags'] = []
        self.assertEqual(self.run_helper('hide').stdout.strip(), 'closed')
        self.assertFalse(self.data.get('dispatches'))

    def test_native_dialog_keeps_shelf_open(self):
        self.data['active'] = dict(address='0xb', pid=123)
        self.assertEqual(self.run_helper('focused').stdout.strip(), 'focused')
        self.data['active']['pid'] = 456
        self.assertEqual(self.run_helper('focused').stdout.strip(), 'unfocused')

    def test_scratchpad_is_selected_on_target_monitor(self):
        self.data['monitors'][0]['focused'] = False
        self.data['monitors'][0]['specialWorkspace']['name'] = 'special:scratchpad'
        self.data['monitors'].append(dict(self.data['monitors'][0], name='OTHER',
                                         focused=True, specialWorkspace={'name': ''}))
        self.assertEqual(self.run_helper('show', 'left', 'TEST').returncode, 0)
        self.assertTrue(any('special:scratchpad' in c for c in self.data['dispatches']))

    def test_rotated_scaled_monitor_and_bottom_geometry(self):
        self.data['monitors'][0].update(width=2160, height=3840, scale=2, transform=1, x=-1920)
        self.assertEqual(self.run_helper('show', 'bottom', 'TEST').returncode, 0)
        self.assertTrue(any('exact 1888 680,address:0xa' in c for c in self.data['dispatches']))
        self.assertTrue(any('exact -1904 384,address:0xa' in c for c in self.data['dispatches']))

    def test_dbus_launch_opens_home_without_a_launcher_child(self):
        self.identity.unlink()
        r = self.run_helper('show')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(self.identity.read_text())['address'], '0xc')
        self.assertEqual(len(self.data['requests']), 1)
        self.assertEqual(self.data['requests'][0][1], ':1.42')
        self.assertEqual(self.data['requests'][0][-2], 'new-window')
        self.assertEqual([a[-1] for a in self.data['actions']], ['go-home', 'new-tab', 'close-other-tabs'])
        self.assertEqual(self.data['locations']['/org/gnome/Nautilus/window/20'], [Path(os.environ['HOME']).as_uri()])
        self.assertFalse(list(self.identity.parent.glob('file-shelf-launch.*')))
        self.assertEqual(self.run_helper('status').stdout.strip(), 'open')

    def test_state_path_with_spaces_and_punctuation_is_uri_encoded(self):
        state_home = self.root / "state with spaces # and 'quotes'"
        self.identity = state_home / 'omarchy/file-shelf.window'
        self.env['XDG_STATE_HOME'] = str(state_home)
        r = self.run_helper('show')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('%20', self.data['bootstrap_uri'])
        self.assertIn('%23', self.data['bootstrap_uri'])
        self.assertNotIn(' ', self.data['bootstrap_uri'])

    def test_cleanup_preserves_files_added_to_bootstrap_directory(self):
        self.identity.unlink()
        self.data['preserve_bootstrap_file'] = True
        r = self.run_helper('show')
        self.assertEqual(r.returncode, 0, r.stderr)
        files = list(self.identity.parent.glob('file-shelf-launch.*/user-note.txt'))
        self.assertEqual(len(files), 1)
        self.assertEqual(files[0].read_text(), 'keep this')

    def test_simultaneous_and_earlier_unrelated_windows_are_untouched(self):
        for delay in (0, 4):
            with self.subTest(delay=delay):
                self.identity.unlink(missing_ok=True)
                self.data['clients'] = [client()]
                self.data['dispatches'] = []
                self.data['polls'] = 0
                self.data['delay_bootstrap'] = delay
                self.data['other_new_clients'] = [dict(client('0xb', 789, '3'), title='Home'),
                                                   dict(client('0xd', 456, '3'), title='Downloads')]
                r = self.run_helper('show')
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(json.loads(self.identity.read_text())['address'], '0xc')
                self.assertTrue(all('address:0xb' not in c and 'address:0xd' not in c and 'address:0xa' not in c
                                    for c in self.data['dispatches']))

    def test_duplicate_request_identity_does_not_move_any_window(self):
        self.identity.unlink()
        self.data['duplicate_token'] = True
        self.assertNotEqual(self.run_helper('show').returncode, 0)
        self.assertFalse(self.data.get('dispatches'))
        self.assertNotIn('address', json.loads(self.identity.read_text()))

    def test_dbus_activation_failure_does_not_launch_or_adopt(self):
        self.identity.unlink()
        self.data['fail_activation'] = True
        self.assertNotEqual(self.run_helper('show').returncode, 0)
        self.assertFalse(self.data.get('requests'))
        self.assertFalse(self.data.get('dispatches'))

    def test_disappearing_dbus_owner_does_not_adopt_another_process(self):
        self.identity.unlink()
        self.data['owner_gone'] = True
        self.assertNotEqual(self.run_helper('show').returncode, 0)
        self.assertFalse(self.data.get('dispatches'))

    def test_window_recycled_before_tag_is_rejected(self):
        self.identity.unlink()
        self.data['recycled_before_tag'] = True
        self.assertNotEqual(self.run_helper('show').returncode, 0)
        self.assertNotIn('address', json.loads(self.identity.read_text()))
        self.assertTrue(all('window.move' not in c for c in self.data.get('dispatches', [])))

    def test_lost_open_reply_does_not_create_a_second_window(self):
        self.identity.unlink()
        self.data['fail_open_after_delivery'] = True
        self.assertNotEqual(self.run_helper('show').returncode, 0)
        self.data.pop('fail_open_after_delivery')
        r = self.run_helper('show')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.data['requests']), 1)

    def test_failed_preparation_retries_same_window(self):
        self.identity.unlink()
        self.data['fail_action'] = 'new-tab'
        self.assertNotEqual(self.run_helper('show').returncode, 0)
        self.assertIn('launch', json.loads(self.identity.read_text()))
        self.data.pop('fail_action')
        r = self.run_helper('show')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.data['requests']), 1)
        self.assertNotIn('launch', json.loads(self.identity.read_text()))

    def test_unexpected_tabs_are_not_closed_during_recovery(self):
        self.identity.unlink()
        self.data['fail_action'] = 'new-tab'
        self.assertNotEqual(self.run_helper('show').returncode, 0)
        self.data.pop('fail_action')
        self.data['locations']['/org/gnome/Nautilus/window/20'] = ['file:///important-work']
        self.assertNotEqual(self.run_helper('show').returncode, 0)
        self.assertFalse(any(a[-1] == 'close-other-tabs' for a in self.data['actions']))

    def test_compositor_failure_is_an_error_not_closed(self):
        self.data['query_fail'] = True
        self.assertNotEqual(self.run_helper('status').returncode, 0)

    def test_failed_dispatch_reports_error(self):
        self.data['dispatch_fail'] = True
        self.assertNotEqual(self.run_helper('hide').returncode, 0)

    def test_invalid_edge_does_not_touch_windows(self):
        self.assertNotEqual(self.run_helper('show', 'top').returncode, 0)
        self.assertFalse(self.data.get('dispatches'))

if __name__ == '__main__':
    unittest.main()
