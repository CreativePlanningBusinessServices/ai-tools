#!/usr/bin/env python3
"""Build and deploy customrole_cp_readonly: Administrator's permissions, flipped to View.

  build   Write a scratch SDF project holding the role: every permission key SuiteCloud knows, at View,
          minus exclusions.txt and no-view-level.txt, with baseline/'s levels on top (baseline adds
          keys the SDK list lacks, such as LIST_SYSTEMNOTES), minus the account's dropped keys, plus the
          account's custom record types at View (each also listed as a manifest dependency).
  deploy  Deploy that project, and when NetSuite refuses a key ("Invalid permkey reference key X"),
          append X to the account's dropped file, rebuild and deploy again.

Run from netsuite/ai-role. See ONBOARDING.md for the whole process.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROLE_FILE = 'customrole_cp_readonly.xml'
REJECTED_KEY = re.compile(r'Invalid permkey\d* reference key ([A-Z0-9_]+)')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    for name in ('build', 'deploy'):
        cmd = sub.add_parser(name)
        cmd.add_argument('--alias', required=True, help='accounts/<alias>/ folder for this account')
        cmd.add_argument('--authid', required=True, help='admin SuiteCloud auth id, e.g. 4244448_M2M')
        cmd.add_argument('--out', required=True, help='scratch project folder (recreated each build)')
    deploy = sub.choices['deploy']
    deploy.add_argument('--max-attempts', type=int, default=40)
    args = parser.parse_args()

    if args.command == 'build':
        build(args)
    else:
        deploy_dropping_rejected(args)


def deploy_dropping_rejected(args):
    dropped_path = os.path.join('accounts', args.alias, 'dropped.txt')
    for attempt in range(1, args.max_attempts + 1):
        build(args)
        result = subprocess.run(['suitecloud', 'project:deploy'], cwd=args.out, capture_output=True, text=True)
        output = result.stdout + result.stderr
        rejected = sorted(set(REJECTED_KEY.findall(output)))
        if not rejected:
            print(f'attempt {attempt}: no rejected key')
            print('\n'.join(output.strip().splitlines()[-6:]))
            return
        print(f'attempt {attempt}: NetSuite refused {", ".join(rejected)}; dropping and retrying')
        with open(dropped_path, 'a') as dropped:
            dropped.write(''.join(f'{key}\n' for key in rejected))
    sys.exit(f'still refusing keys after {args.max_attempts} attempts; see {dropped_path}')


def build(args):
    account_dir = os.path.join('accounts', args.alias)
    if not os.path.isdir(account_dir):
        sys.exit(f'{account_dir} does not exist')
    baseline = read_permissions('baseline/' + ROLE_FILE)
    # baseline/ wins over these lists, e.g. REPO_ANALYTICS has no View level but baseline sets it at Edit.
    excluded = read_keys('exclusions.txt') | read_keys('no-view-level.txt')
    # The account's dropped keys win over baseline/ too: NetSuite refused them, or the client asked for them off.
    dropped = read_keys(os.path.join(account_dir, 'dropped.txt'))
    custom_records = sorted(read_keys(os.path.join(account_dir, 'custom-records.txt')))

    levels = {key: 'VIEW' for key in sdk_permission_keys() if key not in excluded}
    levels.update(baseline)
    for key in dropped:
        levels.pop(key, None)
    permissions = [(key, levels[key]) for key in sorted(levels)]
    permissions += [(custom_record_permkey(record), 'VIEW') for record in custom_records]

    if os.path.exists(args.out):
        shutil.rmtree(args.out)
    os.makedirs(os.path.join(args.out, 'Objects', 'Roles'))
    for name in ('suitecloud.config.js', 'deploy.xml'):
        shutil.copy(name, args.out)
    with open(os.path.join(args.out, 'project.json'), 'w') as project:
        json.dump({'defaultAuthId': args.authid}, project)
    write_manifest(os.path.join(args.out, 'manifest.xml'), custom_records)
    write_role(os.path.join(args.out, 'Objects', 'Roles', ROLE_FILE), permissions)
    print(f'{args.out}: {len(permissions)} permissions ({len(custom_records)} custom record types), auth {args.authid}')


def custom_record_permkey(record):
    # A segment's record type is stored on the role as the segment itself. Sending the
    # [scriptid=customrecord_cseg_x] form to a role that already has it fails with "Record must be unique".
    segment = segment_id(record)
    return f'[type=customsegment, scriptid={segment}]' if segment else f'[scriptid={record}]'


def segment_id(record):
    return record[len('customrecord_'):] if record.startswith('customrecord_cseg_') else None


def sdk_permission_keys():
    """SuiteCloud's own list of permission keys, from the newest CLI jar on this machine."""
    jars = sorted(glob.glob(os.path.expanduser('~/.suitecloud-sdk/cli/cli-*.jar')))
    if not jars:
        sys.exit('no SuiteCloud CLI jar under ~/.suitecloud-sdk/cli')
    with zipfile.ZipFile(jars[-1]) as jar:
        listing = jar.read('sdf_metadata/list/generic_permission.xml').decode()
    return set(re.findall(r'<value>((?:ADMI|LIST|REGT|REPO|TRAN)_[A-Z0-9_]+)</value>', listing))


def read_keys(path):
    if not os.path.exists(path):
        return set()
    with open(path) as keys:
        return {line.split('#')[0].strip() for line in keys} - {''}


def read_permissions(path):
    with open(path) as role:
        return dict(re.findall(r'<permkey>([^<]+)</permkey>\s*<permlevel>([A-Z]+)</permlevel>', role.read()))


def write_role(path, permissions):
    with open('baseline/' + ROLE_FILE) as baseline:
        header = baseline.read().split('  <permissions>')[0]
    body = ''.join(
        f'    <permission>\n      <permkey>{key}</permkey>\n      <permlevel>{level}</permlevel>\n    </permission>\n'
        for key, level in permissions)
    with open(path, 'w') as role:
        role.write(f'{header}  <permissions>\n{body}  </permissions>\n</role>\n')


def write_manifest(path, custom_records):
    with open('manifest.xml') as manifest:
        text = manifest.read()
    if custom_records:
        objects = ''.join(f'      <object>{segment_id(record) or record}</object>\n' for record in custom_records)
        text = text.replace('  </dependencies>', f'    <objects>\n{objects}    </objects>\n  </dependencies>')
    with open(path, 'w') as manifest:
        manifest.write(text)


if __name__ == '__main__':
    main()
