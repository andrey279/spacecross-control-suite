"""Local authenticated operator control queue; no unauthenticated HTTP command API."""
import argparse
import json
from pathlib import Path
from .crypto import address, text
from .store import Store


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--database', type=Path, required=True)
    commands = p.add_subparsers(dest='command', required=True)
    put = commands.add_parser('enqueue')
    for key in ('node', 'model', 'action'):
        put.add_argument('--' + key, required=True)
    put.add_argument('--args', default='{}', help='JSON object; use --args-file for sensitive or multiline input')
    put.add_argument('--args-file', type=Path)
    get = commands.add_parser('get'); get.add_argument('id')
    whitelist = commands.add_parser('whitelist-set')
    whitelist.add_argument('--node', required=True)
    whitelist.add_argument('--entries-file', type=Path, required=True)
    whitelist_get = commands.add_parser('whitelist-get')
    whitelist_get.add_argument('--node', required=True)
    status = commands.add_parser('satellite-status')
    status.add_argument('--node', required=True)
    alerts = commands.add_parser('satellite-alerts')
    alerts.add_argument('--node', required=True)
    alerts.add_argument('--limit', type=int, default=100)
    args = p.parse_args(); store = Store(args.database)
    try:
        if args.command == 'enqueue':
            value = json.loads(args.args_file.read_text() if args.args_file else args.args)
            print(store.enqueue(address(args.node.encode()), text(args.model.encode()), text(args.action.encode()), value))
        elif args.command == 'get':
            print(json.dumps(store.command(args.id), ensure_ascii=False, indent=2))
        elif args.command == 'whitelist-set':
            print(json.dumps(store.set_satellite_whitelist(address(args.node.encode()),
                json.loads(args.entries_file.read_text())), ensure_ascii=False))
        elif args.command == 'whitelist-get':
            print(json.dumps(store.satellite_whitelist(address(args.node.encode())), ensure_ascii=False))
        elif args.command == 'satellite-status':
            print(json.dumps(store.satellite_status(address(args.node.encode())), ensure_ascii=False, indent=2))
        else:
            print(json.dumps(store.satellite_alerts(address(args.node.encode()), args.limit), ensure_ascii=False, indent=2))
    finally:
        store.close()


if __name__ == '__main__':
    main()
