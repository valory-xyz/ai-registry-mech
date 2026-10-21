"""Compare deployed factory code with a fresh Foundry artifact and the intended proxy.

The fixed-price factories have one immutable, mechMarketplace. Solc records every place
where the constructor inserts that address into the runtime code. Fill those positions
with the expected address, then require exact equality, including metadata and embedded
mech creation code. An unknown artifact layout fails closed.
"""
import json
from pathlib import Path
import re
import sys


def expected_code(artifact, proxy):
    if not re.fullmatch(r'0x[0-9a-fA-F]{40}', proxy) or int(proxy, 16) == 0:
        raise ValueError('Invalid expected Marketplace proxy')
    deployed = artifact['deployedBytecode']
    text = deployed['object']
    if not re.fullmatch(r'0x(?:[0-9a-fA-F]{2})+', text):
        raise ValueError('Invalid or unlinked compiled factory code')
    if deployed.get('linkReferences'):
        raise ValueError('Linked factories require an explicit comparison procedure')
    references = deployed['immutableReferences']
    if len(references) != 1:
        raise ValueError('Expected exactly one factory immutable: mechMarketplace')
    positions = next(iter(references.values()))
    if not positions:
        raise ValueError('Missing Marketplace immutable positions')
    code = bytearray.fromhex(text[2:])
    address = bytes.fromhex(proxy[2:].zfill(64))
    occupied = set()
    for position in positions:
        start, length = position['start'], position['length']
        if type(start) is not int or type(length) is not int or start < 0 or length != 32 or start + length > len(code):
            raise ValueError('Invalid Marketplace immutable position')
        indexes = set(range(start, start + length))
        if indexes & occupied:
            raise ValueError('Overlapping Marketplace immutable positions')
        occupied.update(indexes)
        code[start:start + length] = address
    return bytes(code)


def main():
    if len(sys.argv) != 3:
        raise ValueError('Usage: check_factory.py <fresh Foundry artifact> <expected proxy>')
    artifact = json.loads(Path(sys.argv[1]).read_text())
    expected = expected_code(artifact, sys.argv[2])
    actual = sys.stdin.read().strip()
    if not re.fullmatch(r'0x(?:[0-9a-fA-F]{2})+', actual) or bytes.fromhex(actual[2:]) != expected:
        raise ValueError('Factory code does not match the current build for the selected type and Marketplace proxy; deploy its factory from this checkout')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, StopIteration) as error:
        print('Error: ' + str(error), file=sys.stderr)
        sys.exit(1)
