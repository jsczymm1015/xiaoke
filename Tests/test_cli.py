import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'cli/xiaoke'
loader = importlib.machinery.SourceFileLoader('xiaoke', str(CLI))
spec = importlib.util.spec_from_loader(loader.name, loader)
xiaoke = importlib.util.module_from_spec(spec)
loader.exec_module(xiaoke)

class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.old = os.environ.get('XIAOKE_DATA_DIR')
        os.environ['XIAOKE_DATA_DIR'] = self.temp.name
    def tearDown(self):
        if self.old is None: os.environ.pop('XIAOKE_DATA_DIR', None)
        else: os.environ['XIAOKE_DATA_DIR'] = self.old
        self.temp.cleanup()
    def event(self):
        return json.loads(next((Path(self.temp.name) / 'agent-inbox').glob('*.json')).read_text())
    def call(self, *args, **kwargs):
        return subprocess.run([sys.executable, str(CLI), *args], capture_output=True, text=True, **kwargs)
    def test_atomic_update_and_permissions(self):
        xiaoke.emit('test', 'one', 'started')
        xiaoke.emit('test', 'one', 'completed')
        self.assertEqual(self.event()['status'], 'completed')
        files = list((Path(self.temp.name) / 'agent-inbox').glob('*.json'))
        self.assertEqual(len(files), 1)
        self.assertEqual(files[0].stat().st_mode & 0o777, 0o600)
    def test_invalid_events(self):
        for values in [dict(provider='../bad'), dict(task='bad/x'), dict(ttl=0), dict(title='bad\n'), dict(completed=5,total=2)]:
            args = dict(provider='test', task='one', status='started'); args.update(values)
            with self.assertRaises(ValueError): xiaoke.emit(**args)
    def test_success_and_exit_code(self):
        result = self.call('run', '--provider', 'test', '--', sys.executable, '-c', 'print("visible")')
        self.assertEqual(result.returncode, 0)
        self.assertIn('visible', result.stdout)
        self.assertEqual(self.event()['status'], 'completed')
        result = self.call('run', '--provider', 'test', '--task', self.event()['taskID'], '--', sys.executable, '-c', 'raise SystemExit(7)')
        self.assertEqual(result.returncode, 7)
        self.assertEqual(self.event()['status'], 'failed')
        self.assertNotIn('SystemExit', json.dumps(self.event()))
    def test_missing_command(self):
        self.assertEqual(self.call('run', '--', '/nonexistent-xiaoke-command').returncode, 2)
        self.assertEqual(self.event()['status'], 'failed')
    def test_hook_keeps_no_prompt(self):
        payload = dict(hook_event_name='UserPromptSubmit',session_id='session',prompt='PRIVATE TEXT',transcript_path='/private/file')
        self.assertEqual(self.call('hook','claude-code',input=json.dumps(payload)).returncode,0)
        self.assertNotIn('PRIVATE',json.dumps(self.event()))
        payload['hook_event_name']='PermissionRequest'
        self.call('hook','claude-code',input=json.dumps(payload))
        self.assertEqual(self.event()['status'],'waiting')
    def test_bad_hook_never_blocks(self):
        self.assertEqual(self.call('hook','claude-code',input='bad').returncode,0)
    def test_install_merges_and_is_idempotent(self):
        settings=Path(self.temp.name)/'settings.json'
        original={'env':{'KEEP':'yes'},'hooks':{'Stop':[{'hooks':[{'type':'command','command':'echo existing'}]}]}}
        settings.write_text(json.dumps(original))
        for _ in range(2): self.assertEqual(self.call('install-claude','--settings',str(settings)).returncode,0)
        result=json.loads(settings.read_text())
        self.assertEqual(result['env'],original['env'])
        self.assertEqual(len(result['hooks']['Stop']),2)
        self.assertEqual(result['hooks']['Stop'][0],original['hooks']['Stop'][0])
        self.assertTrue(list(settings.parent.glob('*.xiaoke-backup-*')))
    def test_invalid_settings_untouched(self):
        settings=Path(self.temp.name)/'bad.json';settings.write_text('broken')
        self.assertEqual(self.call('install-claude','--settings',str(settings)).returncode,2)
        self.assertEqual(settings.read_text(),'broken')

if __name__ == '__main__': unittest.main()
