"""Applies this fork's defaults to upstream's source, inside the image build.

Dockerfile.web runs it from the repository root after copying the source in.
It edits that copy only: in git, upstream's files stay as upstream wrote them,
so merging upstream never conflicts. When upstream moves something an edit
relies on, the script stops with an error and the build fails, rather than
shipping a bundle without the fork's defaults.

    python3 docker/fork_overlay.py [--check] [DEFAULT_NODE_HEX]

DEFAULT_NODE_HEX  the node a new user starts on; it must already be one of
                  upstream's trusted nodes. Empty keeps upstream's default.
--check           verify that every edit applies, without writing anything.
"""

import json
import re
import sys
from pathlib import Path

CONFIG_RS = Path("rust/src/config.rs")
DEFAULTS_DART = Path("lib/core/mostro_defaults.dart")
METHODS_JSON = Path("assets/data/payment_methods.json")
FORK_METHODS_JSON = Path("docker/payment_methods.json")

RS_DEFAULT = re.compile(r'(pub const DEFAULT_MOSTRO_PUBKEY: &str =\s*")([0-9a-f]{64})(";)')


def fail(message):
    sys.exit(f"fork_overlay: {message}. Upstream may have moved it: update docker/fork_overlay.py")


def replace_once(pattern, replacement, text, what):
    result, count = re.subn(pattern, replacement, text)
    if count != 1:
        fail(f"{what}: expected 1 match, found {count}")
    return result


def default_node_edits(node):
    """New contents of config.rs and mostro_defaults.dart, or {} to keep upstream's node."""
    if not node:
        return {}
    if not re.fullmatch(r"[0-9a-f]{64}", node):
        sys.exit(f"fork_overlay: the default node must be 64 lowercase hex characters, not {node!r}")
    rs = CONFIG_RS.read_text(encoding="utf-8")
    match = RS_DEFAULT.search(rs)
    if not match:
        fail(f"DEFAULT_MOSTRO_PUBKEY not found in {CONFIG_RS}")
    upstream = match.group(2)
    if node == upstream:
        return {}
    if rs.count(f'pubkey: "{node}",') != 1:
        fail(f"{node} is not in TRUSTED_MOSTRO_NODES ({CONFIG_RS}); the default node must be a trusted one")
    rs = replace_once(RS_DEFAULT, rf"\g<1>{node}\g<3>", rs, f"DEFAULT_MOSTRO_PUBKEY in {CONFIG_RS}")
    # Upstream's own node keeps its place in the registry, by its literal key.
    rs = replace_once(
        r"pubkey: DEFAULT_MOSTRO_PUBKEY,",
        f'pubkey: "{upstream}",',
        rs,
        f"the default node's entry in TRUSTED_MOSTRO_NODES ({CONFIG_RS})",
    )
    dart = DEFAULTS_DART.read_text(encoding="utf-8")
    dart = replace_once(
        rf"(const defaultMostroPubkey =\s*'){upstream}(';)",
        rf"\g<1>{node}\g<2>",
        dart,
        f"defaultMostroPubkey in {DEFAULTS_DART}",
    )
    return {CONFIG_RS: rs, DEFAULTS_DART: dart}


def is_method_map(value):
    return isinstance(value, dict) and all(
        isinstance(methods, list) and all(isinstance(m, str) for m in methods)
        for methods in value.values()
    )


def payment_method_edits():
    """Each currency of docker/payment_methods.json gets its methods first, then upstream's."""
    methods = json.loads(METHODS_JSON.read_text(encoding="utf-8"))
    ours = json.loads(FORK_METHODS_JSON.read_text(encoding="utf-8"))
    if not is_method_map(methods):
        fail(f"{METHODS_JSON} is no longer a map of currency to a list of names")
    if not is_method_map(ours):
        sys.exit(f"fork_overlay: {FORK_METHODS_JSON} must map a currency code to a list of names")
    for code, first in ours.items():
        methods[code] = first + [m for m in methods.get(code, []) if m not in first]
    return {METHODS_JSON: json.dumps(methods, ensure_ascii=False, indent=2) + "\n"}


def main(args):
    check = "--check" in args
    rest = [a for a in args if a != "--check"]
    if len(rest) > 1:
        sys.exit(__doc__)
    edits = {**default_node_edits(rest[0] if rest else ""), **payment_method_edits()}
    for path, contents in edits.items():
        if not check:
            path.write_text(contents, encoding="utf-8")
        print(f"fork_overlay: {'would edit' if check else 'edited'} {path}")


if __name__ == "__main__":
    main(sys.argv[1:])
