"""Exercise real shell entrypoints with isolated command stubs; no RPC or credentials.

Run: python3 -m unittest discover -s test/deployment -p 'test_*.py' -v
The separate FixedPriceRollout.js test checks the actual Foundry/RPC integration.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(os.environ.get('MARKETPLACE_SCRIPT_SOURCE', str(Path(__file__).resolve().parents[2])))
DEPLOYMENTS = {
    'deploy_03_mech_marketplace.sh': 'mechMarketplaceAddress',
    'deploy_04_mech_marketplace_proxy.sh': 'mechMarketplaceProxyAddress',
    'deploy_05_mech_factory_fixed_price_native.sh': 'mechFactoryFixedPriceNativeAddress',
    'deploy_07a_mech_factory_fixed_price_token_olas.sh': 'mechFactoryFixedPriceTokenOLASAddress',
    'deploy_07b_mech_factory_fixed_price_token_usdc.sh': 'mechFactoryFixedPriceTokenUSDCAddress',
}
TRANSACTIONS = {
    'script_06_change_implementaion_mech_marketplace_proxy.sh': [],
    'script_02a_marketplace_set_factories_fixed.sh': ['native', 'olas', 'usdc'],
    'script_03a_marketplace_set_balance_trackers_fixed.sh': ['native', 'olas', 'usdc'],
}
SENDER = '0x' + '11' * 20
DEPLOYED = '0x' + 'aa' * 20
HASH = '0x' + 'ab' * 32
PAYMENTS = {
    'FixedPriceNative': '0xba699a34be8fe0e7725e93dcbce1701b0211a8ca61330aaeb8a05bf2ec7abed1',
    'FixedPriceToken': '0x3679d66ef546e66ce9057c4a052f317b135bc8e8c509638f7966edfd4fcf45e9',  # gitleaks:allow -- public PAYMENT_TYPE constant, not a credential
    'FixedPriceTokenUSDC': '0x6406bb5f31a732f898e1ce9fdd988a80a808d36ab5d9a4a4805a8be8d197d5e3',  # gitleaks:allow -- public PAYMENT_TYPE constant, not a credential
}
CONFIG = dict(contractVerification=False, useLedger=True, derivationPath="m/44'/60'/0'/0/0",
              chainId='31337', networkURL='http://127.0.0.1:1', fee='100',
              minResponseTimeout='10', maxResponseTimeout='20')
for index, key in enumerate([
    'serviceRegistryAddress', 'karmaProxyAddress', 'mechMarketplaceAddress', 'mechMarketplaceProxyAddress',
    'mechFactoryFixedPriceNativeAddress', 'mechFactoryFixedPriceTokenOLASAddress',
    'mechFactoryFixedPriceTokenUSDCAddress', 'balanceTrackerFixedPriceNativeAddress',
    'balanceTrackerFixedPriceTokenOLASAddress', 'balanceTrackerFixedPriceTokenUSDCAddress',
    'wrappedNativeTokenAddress', 'olasAddress', 'usdcAddress',
], 1):
    CONFIG[key] = '0x' + f'{index:040x}'

STUB = r"""
import json, os, pathlib, sys
args = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
mode = os.environ['TEST_MODE']
config = json.loads(pathlib.Path(os.environ['TEST_ORIGINAL']).read_text())
state_file = pathlib.Path(os.environ['TEST_STATE'])
state = json.loads(state_file.read_text())
with open(os.environ['TEST_TRACE'], 'a') as stream:
    stream.write(json.dumps([name, *args]) + '\n')
sender = '0x' + '11' * 20
deployed = '0x' + 'aa' * 20
other = '0x' + 'cc' * 20
tx = '0x' + 'ab' * 32
payments = json.loads(os.environ['TEST_PAYMENTS'])
factory_fields = ['mechFactoryFixedPriceNativeAddress', 'mechFactoryFixedPriceTokenOLASAddress', 'mechFactoryFixedPriceTokenUSDCAddress']
factory_names = ['MechFactoryFixedPriceNative', 'MechFactoryFixedPriceToken', 'MechFactoryFixedPriceTokenUSDC']
def factory_code(index, proxy=None):
    immutable = (proxy or config['mechMarketplaceProxyAddress'])[2:].zfill(64)
    return '0x60' + f'{index + 1:02x}' + '7f' + immutable + '00'
def emit(value):
    print(json.dumps(value) if isinstance(value, dict) else value)
    sys.exit(0)
def receipt():
    return {'status': '0x0' if mode == 'receipt_failure' else '0x1',
            'transactionHash': ('0x' + 'cd' * 32) if mode == 'wrong_receipt_hash' else tx,
            'contractAddress': other if mode == 'wrong_receipt' else deployed, 'from': sender}
if name == 'forge':
    if args[0] == 'build':
        if mode == 'factory_build_failure': sys.exit(9)
        output = pathlib.Path(args[args.index('--out') + 1])
        if mode != 'missing_factory_artifact':
            for index, factory_name in enumerate(factory_names):
                artifact = output / (factory_name + '.sol') / (factory_name + '.json')
                artifact.parent.mkdir(parents=True, exist_ok=True)
                compiled = factory_code(index, '0x' + '0' * 40)
                artifact.write_text(json.dumps({'bytecode': {'object': '0x6000' + f'{index:02x}'}, 'deployedBytecode': {'object': compiled,
                    'linkReferences': {}, 'immutableReferences': {'10': [{'start': 3, 'length': 32}]}}}))
        for index, contract_name in enumerate(['MechMarketplace', 'MechMarketplaceProxy'], 3):
            artifact = output / (contract_name + '.sol') / (contract_name + '.json')
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_text(json.dumps({'bytecode': {'object': '0x6000' + f'{index:02x}'}}))
        sys.exit(0)
    if args[0] == 'verify-contract':
        sys.exit(9 if mode == 'verification_failure' else 0)
    if mode == 'diagnostic_failure':
        print(json.dumps({'deployedTo': deployed, 'transactionHash': tx}))
        print('Receipt timeout at ' + config['networkURL'] + ' key=' + os.environ['PRIVATE_KEY'] + ' api=' + os.environ['ETHERSCAN_API_KEY'], file=sys.stderr)
        sys.exit(9)
    if mode == 'command_failure': sys.exit(9)
    if mode == 'bad_json': emit('invalid JSON')
    if mode == 'bad_address': deployed = '0x' + 'z' * 40
    if any(arg.endswith('MechMarketplaceProxy.sol:MechMarketplaceProxy') for arg in args):
        state['implementation'] = args[args.index('--constructor-args') + 1]
        state['version'] = '1.2.0'
        state_file.write_text(json.dumps(state))
    emit({'deployedTo': deployed, 'transactionHash': tx})
command = args[0]
if command == 'chain-id':
    if mode == 'rpc_failure': sys.exit(9)
    emit('1' if mode == 'wrong_chain' else config['chainId'])
if command == 'nonce': emit('0')
if command == 'wallet':
    if mode == 'wallet_failure': sys.exit(9)
    emit(sender)
if command == 'code':
    if mode == 'no_code': emit('0x')
    address = args[-1]
    if mode == 'deployed_no_code' and address == deployed: emit('0x')
    for index, field in enumerate(factory_fields):
        if address == config.get(field):
            actual = factory_code((index + 1) % 3 if mode == 'wrong_factory_type' else index)
            if mode == 'old_factory_code': actual = actual[:-2] + '5b'
            emit(actual)
    emit('0x6000')
if command == 'calldata':
    if mode == 'calldata_failure': sys.exit(9)
    emit('0x12345678')
if command == 'abi-encode': emit('0x12345678')
if command == 'keccak': emit(payments[args[1]])
if command == 'receipt': emit(receipt())
if command == 'send':
    if mode == 'command_failure': sys.exit(9)
    if mode == 'bad_json': emit('invalid JSON')
    pathlib.Path(os.environ['TEST_SENT']).touch()
    methods = ['changeImplementation(address)', 'setMechFactoryStatuses(address[],bool[])',
               'setPaymentTypeBalanceTrackers(bytes32[],address[])']
    index = next(i for i, arg in enumerate(args) if arg in methods)
    # An unrelated target, reverted call or simulated no-op must not update the expected proxy.
    if args[index - 1] == config['mechMarketplaceProxyAddress'] and mode not in ['receipt_failure', 'send_no_effect']:
        method = args[index]
        if method == methods[0]:
            state['implementation'] = args[index + 1]
            state['version'] = '1.3.0' if mode == 'upgrade_wrong_version' else '1.2.0'
            if mode == 'upgrade_changed_owner': state['owner'] = other
            if mode == 'upgrade_changed_domain': state['domain'] = '0x' + 'aa' * 32
        elif method == methods[1]:
            addresses = args[index + 1].strip('[]').split(',')
            flags = args[index + 2].strip('[]').split(',')
            state['factories'].update(dict(zip(addresses, [flag == 'true' for flag in flags])))
        else:
            types = args[index + 1].strip('[]').split(',')
            addresses = args[index + 2].strip('[]').split(',')
            state['trackers'].update(dict(zip(types, addresses)))
        state_file.write_text(json.dumps(state))
    emit(receipt())
if command == 'call':
    if mode == 'getter_failure': sys.exit(9)
    if mode == 'readback_failure' and pathlib.Path(os.environ['TEST_SENT']).exists(): sys.exit(9)
    # Options precede the target in dp_call.
    address, signature = args[3:5]
    if signature == 'VERSION()(string)':
        emit('"' + (state['version'] if address == config.get('mechMarketplaceProxyAddress') else '1.2.0') + '"')
    if signature == 'owner()(address)': emit(other if mode == 'wrong_owner' else state['owner'])
    if signature == 'serviceRegistry()(address)':
        emit(other if mode == 'upgrade_registry_mismatch' and address == config['mechMarketplaceAddress'] else config['serviceRegistryAddress'])
    if signature == 'karma()(address)':
        emit(other if mode == 'upgrade_karma_mismatch' and address == config['mechMarketplaceAddress'] else config['karmaProxyAddress'])
    if signature == 'getImplementation()(address)': emit(state['implementation'])
    if signature == 'getDomainSeparator()(bytes32)': emit(state['domain'])
    if signature == 'mechMarketplace()(address)': emit(other if mode == 'wrong_binding' else config['mechMarketplaceProxyAddress'])
    if signature == 'mapMechFactories(address)(bool)': emit('true' if state['factories'].get(args[5], False) else 'false')
    if signature == 'wrappedNativeToken()(address)': emit(other if mode == 'wrong_asset' else config['wrappedNativeTokenAddress'])
    if signature == 'token()(address)':
        asset = 'usdcAddress' if address == config.get('balanceTrackerFixedPriceTokenUSDCAddress') else 'olasAddress'
        emit(other if mode == 'wrong_asset' or (mode == 'wrong_usdc_asset' and asset == 'usdcAddress') else config[asset])
    if signature == 'mapPaymentTypeBalanceTrackers(bytes32)(address)':
        if mode == 'tracker_not_set': emit('0x' + '0' * 40)
        emit(state['trackers'].get(args[5], '0x' + '0' * 40))
sys.exit(99)
"""


class ShellScripts(unittest.TestCase):
    def run_case(self, script, mode='success', extra=None, changes=None, remove=(), expected=0, expected_error=None):
        with tempfile.TemporaryDirectory(prefix='marketplace shell tests ') as directory:
            case = Path(directory)
            deployment = case / 'scripts/deployment'
            deployment.mkdir(parents=True)
            for entry in (ROOT / 'scripts/deployment').glob('*.sh'):
                shutil.copyfile(entry, deployment / entry.name)
            shutil.copytree(ROOT / 'scripts/deployment/lib', deployment / 'lib')
            bin_dir = case / 'bin'
            bin_dir.mkdir()
            for name in ['cast', 'forge']:
                executable = bin_dir / name
                executable.write_text('#!' + sys.executable + '\n' + STUB)
                executable.chmod(0o755)
            # Resolve real tools once, supporting installations outside /usr/bin (e.g. Homebrew).
            for name, executable in [('jq', shutil.which('jq')), ('python3', sys.executable)]:
                self.assertIsNotNone(executable, 'Required test tool is unavailable: ' + name)
                (bin_dir / name).symlink_to(executable)
            config = dict(CONFIG)
            if script == 'deploy_04_mech_marketplace_proxy.sh':
                config.pop('mechMarketplaceProxyAddress')
            config.update(changes or {})
            for key in remove:
                config.pop(key, None)
            globals_file = deployment / 'globals_review.json'
            globals_file.write_text(json.dumps(config))
            original = case / 'original.json'
            original.write_text(json.dumps(config))
            # Reads reflect sent calls rather than always returning the desired post-operation values.
            state = {'owner': SENDER, 'implementation': '0x' + 'ee' * 20,
                     'version': '1.1.0' if script.startswith('script_06_') or mode == 'old_proxy_version' else '1.2.0',
                     'domain': '0x' + 'dd' * 32, 'factories': {}, 'trackers': {}}
            tracker_fields = ['balanceTrackerFixedPriceNativeAddress', 'balanceTrackerFixedPriceTokenOLASAddress',
                              'balanceTrackerFixedPriceTokenUSDCAddress']
            for payment_type, field in zip(PAYMENTS.values(), tracker_fields):
                if field in config:
                    state['trackers'][payment_type] = ('0x' + 'ee' * 20) if mode == 'send_no_effect' and script.startswith('script_03a_') else config[field]
            state_file = case / 'state.json'
            state_file.write_text(json.dumps(state))
            record = deployment / '.deployment-records/globals_review' / (DEPLOYMENTS.get(script, 'unused') + '.pending.json')
            if mode == 'pending_attempt':
                record.parent.mkdir(parents=True)
                record.write_text('{}')
            if mode == 'missing_globals': globals_file.unlink()
            if mode == 'invalid_config': globals_file.write_text('{broken')
            before = globals_file.read_bytes() if globals_file.exists() else None
            trace = case / 'trace'
            # Do not pass ambient keys, RPC URLs, or Foundry overrides to any test process.
            env = {'PATH': str(bin_dir) + ':/usr/bin:/bin', 'TEST_MODE': mode,
                   'TEST_ORIGINAL': str(original), 'TEST_TRACE': str(trace),
                   'TEST_SENT': str(case / 'sent'), 'TEST_STATE': str(state_file), 'TEST_SCRIPT': script, 'TEST_PAYMENTS': json.dumps(PAYMENTS)}
            if mode == 'verification_failure': env['ETHERSCAN_API_KEY'] = 'test-placeholder'
            if mode == 'diagnostic_failure':
                env.update(PRIVATE_KEY='unit-private-value', ETHERSCAN_API_KEY='unit-explorer-value')
            args = TRANSACTIONS.get(script, []) if extra is None else extra
            if extra is None and script in DEPLOYMENTS and config.get(DEPLOYMENTS[script]):
                args = ['--replace', config[DEPLOYMENTS[script]]]
            result = subprocess.run(['/bin/bash', str(deployment / script), 'review', *args],
                                    env=env, cwd='/', capture_output=True, text=True, timeout=20)
            commands = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
            self.assertEqual(result.returncode == 0, expected == 0, (script, mode, result.stdout, result.stderr, commands))
            if expected != 0:
                errors = {
                    'missing_globals': 'Configuration not found:', 'invalid_config': 'Invalid configuration JSON',
                    'wrong_chain': 'RPC chain ID does not match configuration', 'rpc_failure': 'Cannot read RPC chain ID',
                    'wallet_failure': 'Cannot read wallet address',
                    'command_failure': 'Deployment failed' if script in DEPLOYMENTS else 'Transaction submission failed',
                    'receipt_failure': 'Missing or unsuccessful transaction receipt', 'getter_failure': 'Contract read failed:',
                    'no_code': 'No contract code at',
                    'bad_json': 'Invalid deployment JSON' if script in DEPLOYMENTS else 'Missing or unsuccessful transaction receipt',
                    'bad_address': 'Invalid or zero address: deployedTo', 'wrong_receipt': 'Receipt contract address does not match deployment',
                    'wrong_owner': 'Wallet is not Marketplace owner', 'readback_failure': 'Contract read failed:',
                    'verification_failure': 'Explorer verification failed', 'wrong_binding': 'Wrong factory Marketplace',
                    'wrong_asset': 'Tracker asset differs from configuration', 'tracker_not_set': 'Configure the selected tracker before enabling its factory',
                    'old_factory_code': 'Factory code does not match the current build', 'wrong_factory_type': 'Factory code does not match the current build',
                    'factory_build_failure': 'Cannot build the current factories', 'missing_factory_artifact': 'Selected factory failed the current-build check',
                }
                error = expected_error or errors.get(mode)
                self.assertIsNotNone(error, 'Negative tests must specify the expected error')
                self.assertIn(error, result.stderr)
            if expected != 0 and mode != 'verification_failure':
                self.assertEqual(globals_file.read_bytes() if globals_file.exists() else None, before)
            if mode == 'diagnostic_failure':
                document = json.loads(record.read_text())
                self.assertEqual(document['transactionHash'], HASH)
                self.assertEqual(document['deployedTo'], DEPLOYED)
                self.assertEqual(document['lastExitCode'], 9)
                for secret in ['unit-private-value', 'unit-explorer-value', 'user:password', 'url-private-value']:
                    self.assertNotIn(secret, json.dumps(document))
            if script in DEPLOYMENTS and (expected == 0 or mode == 'verification_failure'):
                self.assertEqual(json.loads(globals_file.read_text())[DEPLOYMENTS[script]], DEPLOYED)
                create = next((command for command in commands if command[:2] == ['forge', 'create']), None)
                self.assertTrue((ROOT / create[2].split(':')[0]).is_file())
                self.assertIn('--broadcast', create)
                self.assertIn('--json', create)
                self.assertEqual(create[create.index('--mnemonic-derivation-path') + 1], CONFIG['derivationPath'])
            if extra and '--calldata' in extra:
                self.assertFalse(any(command[1] in ['send', 'wallet'] for command in commands))
            return commands, result

    def test_registration_requires_the_upgraded_proxy(self):
        for script in ['script_02a_marketplace_set_factories_fixed.sh',
                       'script_03a_marketplace_set_balance_trackers_fixed.sh']:
            for extra in [['native'], ['--calldata', 'native']]:
                with self.subTest(script=script, extra=extra):
                    commands, _ = self.run_case(script, 'old_proxy_version', extra=extra, expected=1,
                        expected_error='Upgrade the Marketplace proxy to 1.2.0 before registration')
                    self.assertFalse(any(command[:2] in [['cast', 'send'], ['cast', 'calldata'], ['cast', 'wallet']]
                                         for command in commands))

    def test_gnosis_selection_does_not_require_usdc(self):
        for script in list(TRANSACTIONS)[1:]:
            commands, _ = self.run_case(script, extra=['native', 'olas'], remove=[
                'mechFactoryFixedPriceTokenUSDCAddress', 'balanceTrackerFixedPriceTokenUSDCAddress', 'usdcAddress'])
            send = next(command for command in commands if command[:2] == ['cast', 'send'])
            self.assertNotIn(PAYMENTS['FixedPriceTokenUSDC'], str(send))

    def test_robinhood_selection_does_not_require_olas(self):
        for script in list(TRANSACTIONS)[1:]:
            self.run_case(script, extra=['native', 'usdc'], remove=[
                'mechFactoryFixedPriceTokenOLASAddress', 'balanceTrackerFixedPriceTokenOLASAddress', 'olasAddress'])

    def test_missing_selected_addresses_fail_before_submission(self):
        suffixes = {'native': 'Native', 'olas': 'TokenOLAS', 'usdc': 'TokenUSDC'}
        for payment, suffix in suffixes.items():
            for script, field in [
                ('script_02a_marketplace_set_factories_fixed.sh', 'mechFactoryFixedPrice' + suffix + 'Address'),
                ('script_03a_marketplace_set_balance_trackers_fixed.sh', 'balanceTrackerFixedPrice' + suffix + 'Address'),
            ]:
                with self.subTest(payment=payment, script=script):
                    commands, _ = self.run_case(script, extra=[payment], remove=[field], expected=1, expected_error='Missing configuration: ' + field)
                    self.assertFalse(any(command[:2] == ['cast', 'send'] for command in commands))

    def test_invalid_selected_addresses_fail_before_submission(self):
        for value in ['0x' + '0' * 40, '0x' + 'z' * 40]:
            for script, field in [
                ('script_02a_marketplace_set_factories_fixed.sh', 'mechFactoryFixedPriceNativeAddress'),
                ('script_03a_marketplace_set_balance_trackers_fixed.sh', 'balanceTrackerFixedPriceNativeAddress'),
            ]:
                with self.subTest(value=value, script=script):
                    commands, _ = self.run_case(script, extra=['native'], changes={field: value}, expected=1, expected_error='Invalid or zero address: ' + field)
                    self.assertFalse(any(command[:2] == ['cast', 'send'] for command in commands))

    def test_selection_preserves_address_and_payment_type_order(self):
        for script, fields, first_array in [
            ('script_02a_marketplace_set_factories_fixed.sh',
             ['mechFactoryFixedPriceTokenUSDCAddress', 'mechFactoryFixedPriceNativeAddress'], None),
            ('script_03a_marketplace_set_balance_trackers_fixed.sh',
             ['balanceTrackerFixedPriceTokenUSDCAddress', 'balanceTrackerFixedPriceNativeAddress'],
             '[' + PAYMENTS['FixedPriceTokenUSDC'] + ',' + PAYMENTS['FixedPriceNative'] + ']'),
        ]:
            commands, _ = self.run_case(script, extra=['usdc', 'native'])
            send = next(command for command in commands if command[:2] == ['cast', 'send'])
            addresses = '[' + ','.join(CONFIG[field] for field in fields) + ']'
            if first_array is None:
                self.assertEqual(send[-2:], [addresses, '[true,true]'])
            else:
                self.assertEqual(send[-2:], [first_array, addresses])

    def test_old_or_wrong_type_factories_are_rejected_in_both_modes(self):
        for mode in ['old_factory_code', 'wrong_factory_type']:
            for payment in ['native', 'olas', 'usdc']:
                for planning in [False, True]:
                    with self.subTest(mode=mode, payment=payment, planning=planning):
                        extra = ['--calldata', payment] if planning else [payment]
                        commands, result = self.run_case('script_02a_marketplace_set_factories_fixed.sh',
                                                         mode, extra=extra, expected=1)
                        self.assertIn('Factory code does not match the current build', result.stderr)
                        self.assertFalse(any(command[:2] == ['cast', 'send'] for command in commands))
                        self.assertNotIn('Data:', result.stdout)

    def test_factory_build_failure_stops_both_modes(self):
        for planning in [False, True]:
            extra = ['--calldata', 'native'] if planning else ['native']
            commands, result = self.run_case('script_02a_marketplace_set_factories_fixed.sh',
                                             'factory_build_failure', extra=extra, expected=1)
            self.assertIn('Cannot build the current factories', result.stderr)
            self.assertFalse(any(command[:2] == ['cast', 'send'] for command in commands))
            self.assertNotIn('Data:', result.stdout)

    def test_missing_fresh_factory_artifact_stops_registration(self):
        commands, result = self.run_case('script_02a_marketplace_set_factories_fixed.sh',
                                         'missing_factory_artifact', extra=['native'], expected=1)
        self.assertIn('Selected factory failed the current-build check', result.stderr)
        self.assertFalse(any(command[:2] == ['cast', 'send'] for command in commands))

    def test_upgrade_rejects_mismatched_dependencies_before_submission(self):
        for mode in ['upgrade_registry_mismatch', 'upgrade_karma_mismatch']:
            for planning in [False, True]:
                with self.subTest(mode=mode, planning=planning):
                    commands, result = self.run_case('script_06_change_implementaion_mech_marketplace_proxy.sh', mode,
                        extra=['--calldata'] if planning else [], expected=1,
                        expected_error='Implementation dependencies differ from the current proxy')
                    self.assertFalse(any(command[:2] == ['cast', 'send'] for command in commands))
                    self.assertNotIn('Data:', result.stdout)

    def test_usdc_asset_mismatch_stops_both_modes(self):
        for planning in [False, True]:
            with self.subTest(planning=planning):
                commands, result = self.run_case('script_03a_marketplace_set_balance_trackers_fixed.sh', 'wrong_usdc_asset',
                    extra=['--calldata', 'usdc'] if planning else ['usdc'], expected=1,
                    expected_error='Tracker asset differs from configuration')
                self.assertFalse(any(command[:2] == ['cast', 'send'] for command in commands))
                self.assertNotIn('Data:', result.stdout)

    def test_newly_deployed_address_must_have_code(self):
        for script in DEPLOYMENTS:
            with self.subTest(script=script):
                commands, _ = self.run_case(script, 'deployed_no_code', expected=1,
                    expected_error='No contract code at ' + DEPLOYED)
                self.assertTrue(any(command[:2] == ['forge', 'create'] for command in commands))
                self.assertTrue(any(command[:2] == ['cast', 'receipt'] for command in commands))

    def test_deployment_receipt_must_match_its_transaction_hash(self):
        for script in DEPLOYMENTS:
            with self.subTest(script=script):
                self.run_case(script, 'wrong_receipt_hash', expected=1, expected_error='Wrong deployment receipt')

    def test_successful_receipt_with_no_state_change_is_rejected(self):
        for script, error in [
            ('script_06_change_implementaion_mech_marketplace_proxy.sh', 'Implementation readback failed'),
            ('script_02a_marketplace_set_factories_fixed.sh', 'Factory status readback failed'),
            ('script_03a_marketplace_set_balance_trackers_fixed.sh', 'Tracker readback failed'),
        ]:
            with self.subTest(script=script):
                commands, _ = self.run_case(script, 'send_no_effect', expected=1, expected_error=error)
                self.assertTrue(any(command[:2] == ['cast', 'send'] for command in commands))

    def test_upgrade_checks_each_retained_value_after_submission(self):
        for mode, error in [
            ('upgrade_wrong_version', 'Version readback failed'),
            ('upgrade_changed_owner', 'Owner changed; inspect the completed upgrade'),
            ('upgrade_changed_domain', 'Legacy domain changed; inspect the completed upgrade'),
        ]:
            with self.subTest(mode=mode):
                commands, _ = self.run_case('script_06_change_implementaion_mech_marketplace_proxy.sh', mode,
                    expected=1, expected_error=error)
                self.assertTrue(any(command[:2] == ['cast', 'send'] for command in commands))

    def test_configured_deployments_require_explicit_replacement(self):
        for script in DEPLOYMENTS:
            if script == 'deploy_04_mech_marketplace_proxy.sh':
                continue
            with self.subTest(script=script):
                commands, _ = self.run_case(script, extra=[], expected=1, expected_error='Deployment already configured')
                self.assertFalse(any(command[:2] == ['forge', 'create'] for command in commands))

    def test_replacement_requires_the_exact_previous_address(self):
        for script in DEPLOYMENTS:
            if script == 'deploy_04_mech_marketplace_proxy.sh':
                continue
            with self.subTest(script=script):
                commands, _ = self.run_case(script, extra=['--replace', '0x' + 'cc' * 20], expected=1,
                    expected_error='Configured address differs from --replace')
                self.assertFalse(any(command[:2] == ['forge', 'create'] for command in commands))

    def test_unresolved_attempt_blocks_repeated_submission(self):
        commands, _ = self.run_case('deploy_03_mech_marketplace.sh', 'pending_attempt', expected=1,
            expected_error='Unresolved deployment attempt exists')
        self.assertFalse(any(command[:2] in [['forge', 'create'], ['cast', 'wallet']] for command in commands))

    def test_failed_command_keeps_diagnostics_and_redacts_credentials(self):
        commands, result = self.run_case('deploy_03_mech_marketplace.sh', 'diagnostic_failure',
            changes={'networkURL': 'http://user:password@127.0.0.1:1/api?token=url-private-value'}, expected=1,
            expected_error='Deployment failed')
        self.assertIn('Receipt timeout', result.stderr)
        self.assertIn(HASH, result.stderr)
        for secret in ['unit-private-value', 'unit-explorer-value', 'user:password', 'url-private-value']:
            self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertTrue(any(command[:2] == ['forge', 'create'] for command in commands))

    def test_custom_rpc_on_ethereum_does_not_need_alchemy_key(self):
        self.run_case('deploy_03_mech_marketplace.sh', changes={'chainId': '1'})

    def test_missing_alchemy_key(self):
        self.run_case('deploy_03_mech_marketplace.sh', changes={
            'chainId': '1', 'networkURL': 'https://eth-mainnet.g.alchemy.com/v2/'}, expected=1, expected_error='Set ALCHEMY_API_KEY_MAINNET')

    def test_missing_verification_key_before_broadcast(self):
        commands, _ = self.run_case('deploy_03_mech_marketplace.sh',
                                    changes={'contractVerification': True}, expected=1, expected_error='Set ETHERSCAN_API_KEY')
        self.assertFalse(any(command[:2] == ['forge', 'create'] for command in commands))

    def test_verification_failure_keeps_confirmed_address(self):
        self.run_case('deploy_03_mech_marketplace.sh', 'verification_failure',
                      changes={'contractVerification': True}, expected=1)

    def test_existing_proxy_is_not_replaced(self):
        self.run_case('deploy_04_mech_marketplace_proxy.sh',
                      changes={'mechMarketplaceProxyAddress': CONFIG['mechMarketplaceProxyAddress']}, extra=[], expected=1, expected_error='Proxy already configured')

    def test_missing_private_key(self):
        self.run_case('deploy_03_mech_marketplace.sh', changes={'useLedger': False}, expected=1, expected_error='Set PRIVATE_KEY or useLedger=true')

    def test_wrong_factory_binding(self):
        self.run_case('deploy_05_mech_factory_fixed_price_native.sh', 'wrong_binding', expected=1)

    def test_tracker_asset_mismatch(self):
        self.run_case('script_03a_marketplace_set_balance_trackers_fixed.sh', 'wrong_asset', expected=1)

    def test_trackers_required_before_enabling_factories(self):
        self.run_case('script_02a_marketplace_set_factories_fixed.sh', 'tracker_not_set', expected=1)

    def test_payment_selection_is_explicit(self):
        for extra, error in [([], 'Select at least one payment type'), (['native', 'native'], 'Duplicate payment type'),
                             (['nvm'], 'Unknown payment type'), (['usdc;exit'], 'Unknown payment type')]:
            self.run_case('script_03a_marketplace_set_balance_trackers_fixed.sh', extra=extra, expected=1, expected_error=error)

    def test_individual_registration_aliases(self):
        for script in ['script_08_marketplace_set_factory_fixed_price_token_usdc.sh',
                       'script_09_marketplace_set_balance_tracker_token_usdc.sh',
                       'script_10_marketplace_set_factory_fixed_price_native.sh',
                       'script_11_marketplace_set_balance_tracker_native.sh']:
            self.run_case(script)
            self.run_case(script, extra=['--calldata'])


def add_case(script, mode):
    def test(self):
        self.run_case(script, mode, expected=0 if mode == 'success' else 1)
    setattr(ShellScripts, 'test_' + script.replace('.sh', '') + '_' + mode, test)


for filename in [*DEPLOYMENTS, *TRANSACTIONS]:
    for case_mode in ['success', 'missing_globals', 'invalid_config', 'wrong_chain',
                      'rpc_failure', 'wallet_failure', 'command_failure', 'receipt_failure',
                      'getter_failure', 'no_code', 'bad_json']:
        add_case(filename, case_mode)
for filename in DEPLOYMENTS:
    for case_mode in ['bad_address', 'wrong_receipt']:
        add_case(filename, case_mode)
for filename, arguments in TRANSACTIONS.items():
    for case_mode in ['wrong_owner', 'readback_failure']:
        add_case(filename, case_mode)
    def plan_test(self, script=filename, extra=arguments):
        self.run_case(script, extra=['--calldata', *extra])
    setattr(ShellScripts, 'test_' + filename.replace('.sh', '') + '_calldata', plan_test)

if __name__ == '__main__':
    unittest.main()
