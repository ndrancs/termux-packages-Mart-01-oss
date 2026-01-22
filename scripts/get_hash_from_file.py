#!/usr/bin/env python3

import sys, os

def _strip_debian_revision(ver: str) -> str:
    """Strip a trailing Debian revision ("-<digits>") if present.

    This allows comparing upstream versions when only the revision differs.
    """
    if "-" not in ver:
        return ver
    base, last = ver.rsplit("-", 1)
    return base if last.isdigit() else ver


def get_pkg_hash_from_Packages(Packages_file, package, version, hash_type="SHA256"):
    """Print '<Filename> ' and then '<Hash>' for a package/version.

    Notes:
    - TERMUX_WITHOUT_DEPVERSION_BINDING=true disables version checks.
    - TERMUX_ALLOW_REVISION_MISMATCH=true allows matching when only the Debian
      revision differs (e.g. requested 4.2.2-1 but repo has 4.2.2).

    This function must not print partial output for non-matching stanzas.
    """

    without_binding = os.getenv('TERMUX_WITHOUT_DEPVERSION_BINDING') == 'true'
    allow_revision_mismatch = os.getenv('TERMUX_ALLOW_REVISION_MISMATCH') == 'true'

    with open(Packages_file, 'r') as Packages:
        package_list = Packages.read().split('\n\n')

    for pkg in package_list:
        lines = [l for l in pkg.split('\n') if l]
        if not lines:
            continue
        if lines[0] != "Package: " + package:
            continue

        filename = None
        ver = None
        h = None
        for line in lines:
            if line.startswith('Filename:'):
                parts = line.split(None, 1)
                if len(parts) == 2:
                    filename = parts[1]
            elif line.startswith('Version:'):
                parts = line.split(None, 1)
                if len(parts) == 2:
                    ver = parts[1]
            elif line.startswith(hash_type + ':'):
                parts = line.split(None, 1)
                if len(parts) == 2:
                    h = parts[1]

        if not filename or not ver or not h:
            continue

        if without_binding:
            print(filename + " ")
            print(h)
            return

        if ver == version:
            print(filename + " ")
            print(h)
            return

        if allow_revision_mismatch and _strip_debian_revision(ver) == _strip_debian_revision(version):
            print(filename + " ")
            print(h)
            return

def get_Packages_hash_from_Release(Release_file, arch, component, hash_type="SHA256"):
    string_to_find = component+'/binary-'+arch+'/Packages'
    with open(Release_file, 'r') as Release:
        hash_list = Release.readlines()
    for i in range(len(hash_list)):
        if hash_list[i].startswith(hash_type+':'):
            break
    for j in range(i, len(hash_list)):
        if string_to_find in hash_list[j].strip(' ') and string_to_find+"." not in hash_list[j].strip(' '):
            hash_entry = list(filter(lambda s: s != '', hash_list[j].strip('').split(' ')))
            if hash_entry[2].startswith(".work_"):
                continue
            print(hash_entry[0])
            break

if __name__ == '__main__':
    if len(sys.argv) < 4:
        sys.exit('Too few arguments, I need the path to a Packages file, a package name and a version, or an InRelease file, an architecture and a component name. Exiting')

    if sys.argv[1].endswith('Packages'):
        get_pkg_hash_from_Packages(sys.argv[1], sys.argv[2], sys.argv[3])
    elif sys.argv[1].endswith(('InRelease', 'Release')):
        get_Packages_hash_from_Release(sys.argv[1], sys.argv[2], sys.argv[3])
    else:
        sys.exit(sys.argv[1]+' does not seem to be a path to a Packages or InRelease/Release file')
