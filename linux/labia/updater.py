"""Is there a newer Labia for this install, and does it change anything this platform runs?

Windows and Linux run from a git copy of github.com/ReyDavidAG/labia, so updating is moving that copy forward:

- Stable channel: the highest `vX.Y.Z` tag that is on origin/main (a published release).
- Development channel: the tip of origin/develop.

Only a clean copy on main or develop, with no commits of its own, updates itself: a developer's working copy
(another branch, uncommitted changes, unpushed commits) is never touched. See updates/plan.md.
"""
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

STABLE, DEVELOPMENT = "estable", "desarrollo"
BRANCH = {STABLE: "main", DEVELOPMENT: "develop"}
# What each platform runs: a change elsewhere (macOS sources, docs) needs no restart there.
PLATFORM_PATHS = {"win32": ("linux/", "windows/"), "linux": ("linux/",)}
REQUIREMENTS = "linux/requirements.txt"
TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
PACKAGE_ROOT = Path(__file__).resolve().parent


class GitError(RuntimeError):
    pass


def git(root, *args):
    """Run git in `root` and return stdout without the final newline. No console window on Windows."""
    try:
        r = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True, encoding="utf-8",
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), timeout=120)
    except (OSError, subprocess.TimeoutExpired) as err:
        raise GitError(f"git {args[0]}: {err}") from err
    if r.returncode != 0:
        raise GitError(f"git {' '.join(args)}: {r.stderr.strip() or r.returncode}")
    return r.stdout.rstrip("\n")


def repo_root(start=PACKAGE_ROOT):
    """The git copy Labia runs from, or None (installed some other way)."""
    try:
        return Path(git(start, "rev-parse", "--show-toplevel"))
    except GitError:
        return None


def describe(root):
    """'1.0.1' on a release, '1.0.1+3 (a1b2c3d)' past it, 'a1b2c3d' with no tags."""
    try:
        d = git(root, "describe", "--tags", "--long", "--match", "v[0-9]*")  # v1.0.1-3-ga1b2c3d
    except GitError:
        return git(root, "rev-parse", "--short", "HEAD")
    tag, ahead, sha = d.rsplit("-", 2)
    return tag[1:] if ahead == "0" else f"{tag[1:]}+{ahead} ({sha[1:]})"


@dataclass
class Update:
    target: str  # commit to move to
    label: str  # what the user reads: '1.0.1' or 'develop a1b2c3d'
    branch: str  # branch to leave checked out at `target` ('main' or 'develop')
    changed: list = field(default_factory=list)  # files that differ from the installed commit
    affects: bool = True  # changes something this platform runs: needs a restart
    needs_pip: bool = False  # requirements.txt changed


@dataclass
class Check:
    current: str  # describe() of the installed copy
    update: Update = None  # None: up to date (or can't update, see reason)
    reason: str = None  # why this copy doesn't update itself


def _semver(tag):
    m = TAG.match(tag)
    return tuple(map(int, m.groups())) if m else None


def latest_release(root):
    """(tag, commit) of the highest vX.Y.Z on origin/main, or None."""
    tags = [t for t in git(root, "tag", "--merged", "origin/main", "--list", "v*").splitlines() if _semver(t)]
    if not tags:
        return None
    tag = max(tags, key=_semver)
    return tag, git(root, "rev-parse", f"{tag}^{{commit}}")


def _is_ancestor(root, a, b):
    try:
        git(root, "merge-base", "--is-ancestor", a, b)
        return True
    except GitError:
        return False


def _branch(root):
    try:
        return git(root, "symbolic-ref", "--short", "-q", "HEAD")
    except GitError:
        return None


def _has_own_commits(root, branch):
    """True if the local `branch` has commits GitHub doesn't (a missing branch has none)."""
    try:
        git(root, "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}")
    except GitError:
        return False
    return not _is_ancestor(root, branch, f"origin/{branch}")


def blocked(root, channel):
    """Why this copy must not update itself, or None. Call after fetch().

    It may sit on either channel's branch (switching channels moves it), but nothing of its own may be lost:
    no uncommitted changes and no local commits on main or develop.
    """
    current = _branch(root)
    if current not in BRANCH.values():
        return f"Copia de desarrollo (rama {current or 'sin rama'}): no se actualiza sola"
    if git(root, "status", "--porcelain", "--untracked-files=no"):
        return "Hay cambios sin guardar en la copia: no se actualiza sola"
    if any(_has_own_commits(root, b) for b in {current, BRANCH[channel]}):
        return "La copia tiene commits que no están en GitHub: no se actualiza sola"
    return None


def fetch(root):
    git(root, "fetch", "--quiet", "--tags", "--force", "--prune", "origin")


def check(root, channel=STABLE, platform=sys.platform, do_fetch=True):
    """What to do with this copy. Network only in fetch()."""
    if channel not in BRANCH:
        channel = STABLE
    if do_fetch:
        fetch(root)
    current = describe(root)
    if reason := blocked(root, channel):
        return Check(current, reason=reason)
    head, branch = git(root, "rev-parse", "HEAD"), BRANCH[channel]
    switching = _branch(root) != branch
    if channel == STABLE:
        release = latest_release(root)
        if not release:
            return Check(current)
        tag, target = release
        label = tag[1:]
    else:
        target = git(root, "rev-parse", "origin/develop")
        label = f"develop {target[:7]}"
    if not switching and (target == head or _is_ancestor(root, target, head)):
        return Check(current)
    if switching and target == head:
        return Check(current, Update(target, label, branch, affects=False))
    changed = git(root, "diff", "--name-only", head, target).splitlines()
    paths = PLATFORM_PATHS.get(platform, ("linux/",))
    return Check(current, Update(target, label, branch, changed,
                                 affects=any(f.startswith(paths) for f in changed),
                                 needs_pip=REQUIREMENTS in changed))


def advance(root, update):
    """Leave `update.branch` checked out at `update.target`. Returns (branch, commit) to roll back to.

    blocked() already made sure no local branch has commits of its own, so moving it loses nothing.
    """
    old = (_branch(root), git(root, "rev-parse", "HEAD"))
    _checkout(root, update.branch, update.target)
    return old


def roll_back(root, old):
    """Back to where advance() found the copy."""
    _checkout(root, *old)


def _checkout(root, branch, commit):
    git(root, "checkout", "--quiet", "-B", branch, commit)
    git(root, "branch", "--quiet", f"--set-upstream-to=origin/{branch}", branch)