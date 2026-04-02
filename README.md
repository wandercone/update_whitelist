# update_whitelist.sh

Resolves a domain's DNS A records and updates an nginx IP whitelist file, inserting new entries above the deny block. Stale entries for the domain are automatically replaced on each run. If the resolved IPs already match what's in the file, the script exits early with no changes.

Each allow entry is tagged with the source domain so the script can track and update only the entries it owns:

```nginx
allow 1.2.3.4; # host: myhome.example.com
```

## Requirements

- `dig`
- `grep`
- `mktemp`

## Usage

```
update_whitelist.sh -d <domain> [-f <file>] [-b]

  -d, --domain  Domain to resolve (required)
  -f, --file    Path to whitelist file
                (default: /docker/swag/nginx/include/ip_access.conf)
  -b, --backup  Create a timestamped backup before modifying
  -h, --help    Show this help message
```

## Examples

```bash
# Basic run
./update_whitelist.sh -d myhome.example.com

# Custom whitelist file with backup
./update_whitelist.sh -d myhome.example.com -f /path/to/ip_access.conf -b
```

## Whitelist file format

The script inserts entries above a `#Deny everyone else` / `deny all;` block:

```nginx
allow 1.2.3.4; # host: myhome.example.com
#Deny everyone else
deny all;
```

If no deny block is found, entries are appended to the end of the file with a warning.
