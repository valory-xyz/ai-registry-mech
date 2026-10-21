"""Deployment command diagnostics and local recovery records. No signing keys are recorded."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def redact(text):
    secrets = set()
    for name, value in os.environ.items():
        if value and ('API_KEY' in name or name == 'PRIVATE_KEY'):
            secrets.add(value)
            if name == 'PRIVATE_KEY' and value.startswith('0x'):
                secrets.add(value[2:])
    for secret in sorted(secrets, key=len, reverse=True):
        text = text.replace(secret, '[redacted]')
    return re.sub(r'https?:[\\/]+[^\s\'"<>]+', '[redacted URL]', text)


def atomic_json(path, document):
    path = Path(path)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
            temporary = stream.name
            json.dump(document, stream, indent=2)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def configured(path, key):
    value = json.loads(Path(path).read_text()).get(key)
    return '' if value in (None, '', '0x' + '0' * 40) else str(value).lower()


def run_command(arguments):
    process = subprocess.run(arguments, capture_output=True, text=True, errors='replace')
    diagnostic = redact(process.stderr + ('\n' + process.stdout if process.returncode else ''))
    if diagnostic:
        print(diagnostic, file=sys.stderr, end='' if diagnostic.endswith('\n') else '\n')
    record = os.environ.get('DP_COMMAND_RECORD')
    if record:
        document = json.loads(Path(record).read_text())
        try:
            output = json.loads(process.stdout)
        except (ValueError, TypeError):
            output = {}
        if isinstance(output, dict):
            for key, pattern in [('transactionHash', r'0x[0-9a-fA-F]{64}'), ('deployedTo', r'0x[0-9a-fA-F]{40}')]:
                value = output.get(key)
                if isinstance(value, str) and re.fullmatch(pattern, value):
                    document[key] = value
        document['lastExitCode'] = process.returncode
        document['diagnostic'] = diagnostic
        atomic_json(record, document)
    if not process.returncode:
        sys.stdout.write(process.stdout)
    return process.returncode if process.returncode > 0 else (1 if process.returncode else 0)


def main(arguments):
    operation, *args = arguments
    if operation == 'run':
        return run_command(args)
    if operation == 'begin':
        record, globals_path, key, expected_previous, metadata = args
        path = Path(record)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        try:
            descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            raise ValueError('Unresolved deployment attempt exists; inspect the transaction before any further deployment')
        try:
            with os.fdopen(descriptor, 'w') as stream:
                if configured(globals_path, key) != expected_previous.lower():
                    raise ValueError('Configured deployment changed before submission; no transaction was sent')
                document = json.loads(metadata)
                document.update(state='pending', previousAddress=expected_previous)
                json.dump(document, stream, indent=2)
                stream.write('\n')
                stream.flush()
                os.fsync(stream.fileno())
        except Exception:
            path.unlink()
            raise
    elif operation == 'finish':
        record, metadata, transaction_hash, address = args
        path = Path(record)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        confirmed = path.with_name(path.name.replace('.pending.json', '.' + transaction_hash + '.json'))
        previous = path if path.exists() else confirmed
        document = json.loads(previous.read_text()) if previous.exists() else {}
        document.update(json.loads(metadata))
        document.update(state='confirmed', transactionHash=transaction_hash, deployedTo=address)
        atomic_json(confirmed, document)
        if path.exists():
            path.unlink()
    else:
        raise ValueError('Unknown deployment recovery operation')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('Error: ' + redact(str(error)), file=sys.stderr)
        sys.exit(1)
