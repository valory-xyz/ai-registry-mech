"""Run the actual six upgrade scripts with isolated tools; no RPC access or real keys.

python3 -B -m unittest discover -s test/deployment -p 'test_*.py' -v
"""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DEPLOYMENTS = {
    'deploy_03_mech_marketplace.sh': 'mechMarketplaceAddress',
    'deploy_05_mech_factory_fixed_price_native.sh': 'mechFactoryFixedPriceNativeAddress',
    'deploy_07a_mech_factory_fixed_price_token_olas.sh': 'mechFactoryFixedPriceTokenOLASAddress',
    'deploy_07b_mech_factory_fixed_price_token_usdc.sh': 'mechFactoryFixedPriceTokenUSDCAddress',
}
UPGRADE = 'script_06_change_implementaion_mech_marketplace_proxy.sh'
REGISTER = 'script_02a_marketplace_set_factories_fixed.sh'
CHECKER = 'check_marketplace_implementation.py'
SCRIPTS = [*DEPLOYMENTS, UPGRADE, REGISTER]
SENDER, DEPLOYED, OTHER = ['0x' + c * 40 for c in ['1', 'a', 'c']]
HASH = '0x' + 'b' * 64
FIELDS = ['serviceRegistryAddress', 'karmaProxyAddress', 'mechMarketplaceAddress', 'mechMarketplaceProxyAddress',
          'mechFactoryFixedPriceNativeAddress', 'mechFactoryFixedPriceTokenOLASAddress', 'mechFactoryFixedPriceTokenUSDCAddress',
          'balanceTrackerFixedPriceNativeAddress', 'balanceTrackerFixedPriceTokenOLASAddress', 'balanceTrackerFixedPriceTokenUSDCAddress',
          'wrappedNativeTokenAddress', 'olasAddress', 'usdcAddress']
CONFIG = {field: '0x' + f'{i:040x}' for i, field in enumerate(FIELDS, 2)}
CONFIG.update(chainId='31337', networkURL='http://127.0.0.1:1', useLedger=True,
              derivationPath="m/44'/60'/0'/0/0", contractVerification=False)

STUB = r'''
import json, os, pathlib, sys
args = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
mode = os.environ['MODE']
config = json.loads(pathlib.Path(os.environ['CONFIG']).read_text())
state_path = pathlib.Path(os.environ['STATE'])
state = json.loads(state_path.read_text())
with open(os.environ['TRACE'], 'a') as stream: stream.write(json.dumps([name, *args]) + '\n')
sender, deployed, other = ['0x' + c * 40 for c in ['1','a','c']]
tx = '0x' + 'b' * 64
suffixes = ['Native', 'TokenOLAS', 'TokenUSDC']
names = ['MechFactoryFixedPriceNative', 'MechFactoryFixedPriceToken', 'MechFactoryFixedPriceTokenUSDC']
types = ['FixedPriceNative', 'FixedPriceToken', 'FixedPriceTokenUSDC']
def payment(i): return '0x' + f'{i + 1:064x}'
def code(i, proxy=None): return '0x60' + f'{i + 1:02x}' + '7f' + (proxy or config['mechMarketplaceProxyAddress'])[2:].zfill(64) + '00'
def implementation_code(blank=False):
    values = [config['serviceRegistryAddress'], config['karmaProxyAddress'], hex(int(config['chainId']))]
    return '0x60' + ''.join('7f' + ('0'*64 if blank else value[2:].zfill(64)) + '50' for value in values) + '00'
def emit(value):
    print(json.dumps(value) if isinstance(value, dict) else value)
    sys.exit(0)
def receipt():
    return dict(status='0x0' if mode == 'receipt_failure' else '0x1',
                transactionHash='0x' + ('d' if mode == 'wrong_receipt_hash' else 'b') * 64,
                contractAddress=other if mode == 'wrong_receipt_address' else deployed)
if name == 'forge':
    if args[0] == 'build':
        if mode == 'build_failure': sys.exit(7)
        for i, factory in enumerate(names):
            path = pathlib.Path('out') / (factory + '.sol') / (factory + '.json')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({'deployedBytecode': {'object': code(i, '0x' + '0'*40),
                'immutableReferences': {'1': [{'start': 3, 'length': 32}]}, 'linkReferences': {}}}))
        path = pathlib.Path('out/MechMarketplace.sol/MechMarketplace.json')
        path.parent.mkdir(parents=True, exist_ok=True)
        artifact = {'deployedBytecode': {'object': implementation_code(True), 'linkReferences': {},
            'immutableReferences': {str(i + 11): [{'start': 2 + 34*i, 'length': 32}] for i in range(3)}}}
        if mode == 'missing_immutables': del artifact['deployedBytecode']['immutableReferences']
        if mode == 'invalid_immutable_slot': artifact['deployedBytecode']['immutableReferences']['11'][0]['start'] = 99999
        if mode == 'linked_implementation': artifact['deployedBytecode']['linkReferences'] = {'Unexpected.sol': {'Library': []}}
        path.write_text('not JSON' if mode == 'malformed_artifact' else json.dumps(artifact))
        sys.exit(0)
    if args[0] == 'verify-contract': sys.exit(7 if mode == 'verification_failure' else 0)
    if mode == 'bad_json': emit('not JSON')
    print(json.dumps(dict(deployedTo='0x' + 'z' * 40 if mode == 'invalid_address' else deployed, transactionHash=tx)))
    if mode == 'command_failure': sys.exit(7)
    if mode == 'diagnostic_failure':
        print(os.environ['PRIVATE_KEY'] + ' ' + config['networkURL'] + ' ' + os.environ['ETHERSCAN_API_KEY'], file=sys.stderr)
        sys.exit(7)
    sys.exit(0)
method = args[0]
if method == 'chain-id':
    if mode == 'rpc_failure': sys.exit(7)
    emit('1' if mode == 'wrong_chain' else config['chainId'])
if method == 'wallet':
    if mode == 'wallet_failure': sys.exit(7)
    emit(sender)
if method == 'abi-encode': emit('0x1234')
if method == 'receipt': emit(receipt())
if method == 'keccak': emit(payment(types.index(args[1])))
if method == 'code':
    address = args[-1]
    if mode == 'no_code' or (mode == 'no_deployed_code' and address == deployed): emit('0x')
    for i, suffix in enumerate(suffixes):
        if address == config.get('mechFactoryFixedPrice' + suffix + 'Address'):
            actual = code((i + 1) % 3 if mode == 'wrong_factory_type' else i)
            emit(actual[:-2] + '5b' if mode in ['old_factory','optimized_old_factory'] else actual)
    if address in [deployed, config['mechMarketplaceAddress']]:
        actual = implementation_code()
        emit(actual[:-2] + '5b' if mode == 'wrong_implementation_code' else actual)
    emit('0x6000')
if method == 'send':
    if mode == 'command_failure': sys.exit(7)
    if mode == 'bad_json': emit('not JSON')
    if mode == 'missing_hash_failure': emit(dict(status='0x0'))
    if mode == 'invalid_hash_failure': emit(dict(status='0x0', transactionHash='invalid-transaction-hash'))
    signature = 'changeImplementation(address)' if os.environ['SCRIPT'] == 'upgrade' else 'setMechFactoryStatuses(address[],bool[])'
    index = args.index(signature)
    if args[index - 1] == config['mechMarketplaceProxyAddress'] and mode not in ['receipt_failure', 'no_state_change']:
        if signature.startswith('changeImplementation'):
            state.update(implementation=args[index + 1], version='1.3.0' if mode == 'changed_version' else '1.2.0')
            if mode == 'changed_owner': state['owner'] = other
            if mode == 'changed_domain': state['domain'] = '0x' + 'a' * 64
        else:
            factories = args[index + 1].strip('[]').split(',')
            flags = args[index + 2].strip('[]').split(',')
            state['factories'].update(dict(zip(factories, flags)))
        state_path.write_text(json.dumps(state))
    if mode in ['command_failure_with_hash', 'diagnostic_failure']:
        print(json.dumps(receipt()))
        if mode == 'diagnostic_failure':
            print(os.environ['PRIVATE_KEY'] + ' ' + config['networkURL'] + ' ' + os.environ['ETHERSCAN_API_KEY'], file=sys.stderr)
        sys.exit(7)
    emit(receipt())
if method == 'call':
    if mode == 'read_failure': sys.exit(7)
    address, signature = args[3:5]
    proxy = address == config['mechMarketplaceProxyAddress']
    if signature == 'VERSION()(string)': emit('"' + (state['version'] if proxy else '1.2.0') + '"')
    if signature == 'chainId()(uint256)': emit('999' if mode == 'wrong_implementation_chain' else config['chainId'])
    if signature == 'owner()(address)': emit(other if mode == 'wrong_owner' else state['owner'])
    if signature == 'getImplementation()(address)': emit(state['implementation'])
    if signature == 'getDomainSeparator()(bytes32)': emit(state['domain'])
    if signature in ['serviceRegistry()(address)', 'karma()(address)']:
        field = 'serviceRegistryAddress' if signature.startswith('serviceRegistry') else 'karmaProxyAddress'
        emit(other if mode == 'wrong_' + field and not proxy else config[field])
    if signature == 'mechMarketplace()(address)': emit(other if mode == 'wrong_binding' else config['mechMarketplaceProxyAddress'])
    if signature == 'wrappedNativeToken()(address)': emit(other if mode == 'wrong_asset' else config['wrappedNativeTokenAddress'])
    if signature == 'token()(address)':
        emit(other if mode == 'wrong_asset' else config['usdcAddress' if address == config.get('balanceTrackerFixedPriceTokenUSDCAddress') else 'olasAddress'])
    if signature == 'mapPaymentTypeBalanceTrackers(bytes32)(address)':
        emit('0x' + '0' * 40 if mode == 'missing_tracker' else config['balanceTrackerFixedPrice' + suffixes[int(args[5],16)-1] + 'Address'])
    if signature == 'mapMechFactories(address)(bool)': emit(state['factories'].get(args[5], 'false'))
sys.exit(99)
'''


class Safety(unittest.TestCase):
    def run_script(self, script, mode='success', expected_error=None, selected=None, changes=None, hash_visible=None):
        with tempfile.TemporaryDirectory(prefix='deployment safety ') as temporary:
            case = Path(temporary)
            deployment = case / 'scripts/deployment'
            deployment.mkdir(parents=True)
            shutil.copyfile(ROOT / 'scripts/deployment' / script, deployment / script)
            if script != CHECKER:
                shutil.copyfile(ROOT / 'scripts/deployment' / CHECKER, deployment / CHECKER)
            config = dict(CONFIG, **(changes or {}))
            if mode == 'diagnostic_failure': config['networkURL'] = 'http://user:password@127.0.0.1:1/?key=dummy-url-secret'
            globals_file = deployment / 'globals_test.json'
            if mode != 'missing_config': globals_file.write_text(json.dumps(config))
            before = globals_file.read_bytes() if globals_file.exists() else None
            original = case / 'original.json'
            original.write_text(json.dumps(config))
            state = case / 'state.json'
            state.write_text(json.dumps(dict(owner=SENDER, implementation=OTHER,
                version='1.1.0' if script == UPGRADE or mode == 'old_proxy' else '1.2.0',
                domain='0x' + 'e' * 64, factories={})))
            tools = case / 'bin'
            tools.mkdir()
            for name in ['cast', 'forge']:
                executable = tools / name
                executable.write_text('#!' + sys.executable + '\n' + STUB)
                executable.chmod(0o755)
            for name, target in [('python3', sys.executable), ('jq', shutil.which('jq'))]:
                self.assertIsNotNone(target)
                (tools / name).symlink_to(target)
            env = dict(PATH=str(tools) + ':/usr/bin:/bin', MODE=mode, CONFIG=str(original),
                       STATE=str(state), TRACE=str(case / 'trace'), SCRIPT='upgrade' if script == UPGRADE else 'registration')
            if mode == 'alchemy_url': env['ALCHEMY_API_KEY_MAINNET'] = 'dummy-alchemy-value'
            if mode == 'optimized_old_factory': env['PYTHONOPTIMIZE'] = '1'
            if mode == 'optimized_wrong_implementation': env['PYTHONOPTIMIZE'] = '1'; env['MODE'] = 'wrong_implementation_code'
            if mode == 'verification_failure': env['ETHERSCAN_API_KEY'] = 'dummy-explorer-value'
            if mode == 'diagnostic_failure': env.update(PRIVATE_KEY='dummy-private-value', ETHERSCAN_API_KEY='dummy-explorer-value')
            args = selected if selected is not None else (['native','olas','usdc'] if script == REGISTER else [])
            command = ['bash', str(deployment / script), 'test', *args]
            if script == CHECKER:
                env['MARKETPLACE_RPC_URL'] = config['networkURL']
                command = [sys.executable, str(deployment / script), '--implementation', config['mechMarketplaceAddress'],
                           '--proxy', config['mechMarketplaceProxyAddress'], '--chain-id', config['chainId']]
            result = subprocess.run(command, env=env, cwd='/',
                                    capture_output=True, text=True, timeout=15)
            trace = case / 'trace'
            calls = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
            if expected_error:
                self.assertNotEqual(result.returncode, 0, (script, mode, result.stdout, result.stderr))
                error_output = result.stdout + result.stderr if mode == 'missing_config' else result.stderr
                self.assertIn(expected_error, error_output)
                if mode != 'verification_failure': self.assertEqual(globals_file.read_bytes() if globals_file.exists() else None, before)
            else:
                self.assertEqual(result.returncode, 0, (script, mode, result.stdout, result.stderr, calls))
            if script in DEPLOYMENTS and (not expected_error or mode == 'verification_failure'):
                self.assertEqual(json.loads(globals_file.read_text())[DEPLOYMENTS[script]], DEPLOYED)
                create = next(call for call in calls if call[:2] == ['forge','create'])
                self.assertIn('--broadcast', create)
                self.assertIn('--json', create)
                self.assertEqual(create[create.index('--use') + 1], '0.8.30')
            if mode == 'diagnostic_failure':
                for secret in ['dummy-private-value','dummy-explorer-value','dummy-url-secret','user:password']:
                    self.assertNotIn(secret, result.stdout + result.stderr)
                self.assertIn(HASH, result.stdout + result.stderr)
            if hash_visible is not None:
                self.assertEqual('Transaction: ' + HASH in result.stdout, hash_visible)
                if not hash_visible: self.assertNotIn('Transaction:', result.stdout)
            if script == CHECKER or (expected_error and mode in ['wrong_implementation_code', 'optimized_wrong_implementation',
                    'wrong_implementation_chain', 'missing_immutables', 'invalid_immutable_slot', 'linked_implementation', 'malformed_artifact']):
                self.assertFalse(any(call[:2] == ['cast', 'send'] for call in calls))
            return calls

    def test_payment_selection_does_not_require_unselected_addresses(self):
        for selected, missing in [(['native','olas'], 'TokenUSDC'), (['native','usdc'], 'TokenOLAS')]:
            changes = {'mechFactoryFixedPrice' + missing + 'Address': None,
                       'balanceTrackerFixedPrice' + missing + 'Address': None}
            calls = self.run_script(REGISTER, selected=selected, changes=changes)
            send = next(call for call in calls if call[:2] == ['cast','send'])
            index = send.index('setMechFactoryStatuses(address[],bool[])')
            suffixes = {'native':'Native', 'olas':'TokenOLAS', 'usdc':'TokenUSDC'}
            self.assertEqual(send[index + 1], '[' + ','.join(CONFIG['mechFactoryFixedPrice' + suffixes[p] + 'Address'] for p in selected) + ']')
            self.assertFalse(any('setPaymentTypeBalanceTrackers' in ' '.join(call) for call in calls))

    def test_alchemy_credentials_are_used_for_every_rpc_call(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                url = 'https://eth-mainnet.g.alchemy.com/v2/'
                calls = self.run_script(script, 'alchemy_url', changes={'chainId':'1', 'networkURL':url})
                for call in calls:
                    if '--rpc-url' in call:
                        self.assertEqual(call[call.index('--rpc-url') + 1], url + 'dummy-alchemy-value')

    def test_diagnostic_output_contains_no_credentials(self):
        self.run_script(next(iter(DEPLOYMENTS)), 'diagnostic_failure', 'Deployment command failed')

    def test_verification_failure_retains_confirmed_address(self):
        for script in DEPLOYMENTS:
            self.run_script(script, 'verification_failure', 'Explorer verification failed', changes={'contractVerification':True})

    def test_governance_check_needs_no_signing_wallet(self):
        calls = self.run_script(CHECKER)
        self.assertFalse(any(call[:2] in [['cast', 'wallet'], ['forge', 'create'], ['cast', 'send']] for call in calls))

    def test_governance_check_matches_proxy_dependencies(self):
        self.run_script(CHECKER, 'wrong_serviceRegistryAddress', 'Wrong implementation service registry')
        self.run_script(CHECKER, 'wrong_karmaProxyAddress', 'Wrong implementation Karma contract')

    def test_send_hash_is_visible_on_failure_without_retrying(self):
        for script in [UPGRADE, REGISTER]:
            command_error = 'Upgrade submission failed' if script == UPGRADE else 'Factory registration failed'
            for mode, error, visible in [
                    ('command_failure_with_hash', command_error, True),
                    ('diagnostic_failure', command_error, True),
                    ('receipt_failure', 'Missing or unsuccessful transaction receipt', True),
                    ('command_failure', command_error, False),
                    ('bad_json', 'Missing or unsuccessful transaction receipt', False),
                    ('missing_hash_failure', 'Missing or unsuccessful transaction receipt', False),
                    ('invalid_hash_failure', 'Missing or unsuccessful transaction receipt', False)]:
                with self.subTest(script=script, mode=mode):
                    calls = self.run_script(script, mode, error, hash_visible=visible)
                    self.assertEqual(sum(call[:2] == ['cast', 'send'] for call in calls), 1)


def add_case(script, mode, error=None):
    def test(self): self.run_script(script, mode, error)
    setattr(Safety, 'test_' + script[:-3] + '_' + mode, test)

for script in SCRIPTS:
    for mode, error in [('success',None), ('missing_config',' is not found'),
                        ('wrong_chain','RPC chain ID does not match'), ('rpc_failure','Cannot read RPC chain'),
                        ('wallet_failure','Cannot read wallet address'), ('no_code','No contract code'),
                        ('receipt_failure','Missing or unsuccessful transaction receipt'),
                        ('bad_json','Invalid deployment output' if script in DEPLOYMENTS else 'Missing or unsuccessful transaction receipt'),
                        ('command_failure','Deployment command failed' if script in DEPLOYMENTS else 'submission failed' if script == UPGRADE else 'Factory registration failed')]:
        add_case(script, mode, error)
for script in DEPLOYMENTS:
    for mode, error in [('invalid_address','Invalid address'), ('no_deployed_code','No contract code: deployedAddress'),
                        ('wrong_receipt_hash','Deployment receipt does not match'), ('wrong_receipt_address','Deployment receipt does not match'),
                        ('build_failure','Cannot build current contracts')]:
        add_case(script, mode, error)
for mode, error in [('wrong_serviceRegistryAddress','Implementation dependencies differ'), ('wrong_karmaProxyAddress','Implementation dependencies differ'),
                    ('wrong_owner','Signer is not Marketplace owner'), ('no_state_change','Implementation readback failed'),
                    ('changed_owner','Owner changed'), ('changed_domain','Legacy domain changed'), ('changed_version','Version readback failed')]:
    add_case(UPGRADE, mode, error)
for mode, error in [('old_proxy','Upgrade the Marketplace proxy'), ('wrong_binding','Factory points to a different Marketplace'),
                    ('wrong_asset','Tracker asset differs'), ('missing_tracker','Expected tracker is not registered'),
                    ('old_factory','Factory does not match the current build'), ('optimized_old_factory','Factory does not match the current build'), ('wrong_factory_type','Factory does not match the current build'),
                    ('no_state_change','Factory registration readback failed'), ('read_failure','before registration (read failed)'),
                    ('wrong_owner','Signer is not Marketplace owner')]:
    add_case(REGISTER, mode, error)
for script in ['deploy_03_mech_marketplace.sh', UPGRADE, CHECKER]:
    for mode, error in [('wrong_implementation_code', 'Implementation does not match the current build'),
                        ('optimized_wrong_implementation', 'Implementation does not match the current build'),
                        ('wrong_implementation_chain', 'Wrong implementation chain ID'),
                        ('missing_immutables', 'Cannot validate implementation artifact or tools'),
                        ('invalid_immutable_slot', 'Invalid implementation immutable slot'),
                        ('linked_implementation', 'Unexpected implementation library links'),
                        ('malformed_artifact', 'Error:')]:
        add_case(script, mode, error)

if __name__ == '__main__': unittest.main()
