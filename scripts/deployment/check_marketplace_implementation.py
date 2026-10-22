"""Check a Marketplace implementation against this checkout without a signing wallet."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def compare_runtime(artifact, actual):
    runtime = artifact['deployedBytecode']
    require(runtime['linkReferences'] == {}, 'Unexpected implementation library links')
    expected = runtime['object'].removeprefix('0x')
    actual = actual.removeprefix('0x')
    require(re.fullmatch(r'(?:[0-9a-fA-F]{2})+', expected) is not None,
            'Invalid implementation artifact bytecode')
    require(re.fullmatch(r'(?:[0-9a-fA-F]{2})+', actual) is not None,
            'Invalid deployed implementation bytecode')
    expected, actual = bytearray.fromhex(expected), bytearray.fromhex(actual)
    require(len(expected) == len(actual), 'Implementation does not match the current build')
    references = runtime['immutableReferences']
    require(isinstance(references, dict) and len(references) == 3,
            'Expected three implementation immutables')
    occupied = set()
    # AST ids identify declarations, not their names. Mask only compiler-listed slots;
    # verify registry, Karma and chainId separately through the reviewed getters.
    for slots in references.values():
        require(isinstance(slots, list) and slots, 'Missing implementation immutable slots')
        for slot in slots:
            start, length = slot['start'], slot['length']
            require(type(start) is int and type(length) is int and length == 32 and
                    0 <= start <= len(expected) - length, 'Invalid implementation immutable slot')
            positions = set(range(start, start + length))
            require(not occupied.intersection(positions), 'Overlapping implementation immutable slots')
            occupied.update(positions)
            expected[start:start + length] = actual[start:start + length] = bytes(length)
    require(expected == actual, 'Implementation does not match the current build')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--implementation', required=True)
    parser.add_argument('--chain-id', required=True, type=int)
    parser.add_argument('--proxy')
    parser.add_argument('--registry')
    parser.add_argument('--karma')
    args = parser.parse_args()
    require(bool(args.proxy) != bool(args.registry or args.karma),
            'Supply either --proxy or both --registry and --karma')
    require(args.proxy or (args.registry and args.karma), 'Supply registry and Karma together')
    rpc = os.environ.get('MARKETPLACE_RPC_URL')
    require(rpc, 'Set MARKETPLACE_RPC_URL')

    def run(command):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        # Tool diagnostics can contain RPC credentials. Report only the failed operation.
        require(result.returncode == 0, 'Implementation check failed: ' + command[0] + ' ' + command[1])
        return result.stdout.strip()

    def cast(method, *values):
        return run(['cast', method, '--rpc-url', rpc, *values])

    def address(value):
        require(isinstance(value, str) and re.fullmatch(r'0x[0-9a-fA-F]{40}', value) and
                int(value, 16) != 0, 'Invalid implementation or dependency address')
        require(cast('code', value) not in ('0x', '0x0', ''), 'No implementation or dependency code')
        return value.lower()

    require(int(cast('chain-id')) == args.chain_id, 'RPC chain ID does not match configuration')
    implementation = address(args.implementation)
    if args.proxy:
        proxy = address(args.proxy)
        registry = address(cast('call', proxy, 'serviceRegistry()(address)'))
        karma = address(cast('call', proxy, 'karma()(address)'))
    else:
        registry, karma = address(args.registry), address(args.karma)
    run(['forge', 'build', '--use', os.environ.get('FOUNDRY_SOLC', '0.8.30'), '--out', 'out',
         '--skip', 'ImportWETH.sol', '--skip', 'Proposal01FeeActivation'])
    artifact = json.loads((ROOT / 'out/MechMarketplace.sol/MechMarketplace.json').read_text())
    compare_runtime(artifact, cast('code', implementation))
    require(cast('call', implementation, 'VERSION()(string)').strip('"') == '1.2.0',
            'Wrong Marketplace version')
    require(cast('call', implementation, 'serviceRegistry()(address)').lower() == registry,
            'Wrong implementation service registry')
    require(cast('call', implementation, 'karma()(address)').lower() == karma,
            'Wrong implementation Karma contract')
    require(int(cast('call', implementation, 'chainId()(uint256)').split()[0]) == args.chain_id,
            'Wrong implementation chain ID')
    print('Marketplace implementation matches the current build and expected constructor values')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError) as error:
        # JSON/artifact errors must fail closed; never print subprocess output or the RPC URL.
        print('Error: ' + (str(error) if isinstance(error, ValueError) else 'Cannot validate implementation artifact or tools'), file=sys.stderr)
        sys.exit(1)
