"""updater.py against real git repos: `upstream` plays GitHub, `install` the copy Labia runs from."""
import subprocess

import pytest

from labia import updater
from labia.updater import DEVELOPMENT, STABLE


def run(repo, *args):
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=Prueba", "-c", "user.email=prueba@example.com",
                           *args], check=True, capture_output=True, text=True).stdout.strip()


def commit(repo, path, text="x", tag=None):
    f = repo / path
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(text, encoding="utf-8")
    run(repo, "add", path)
    run(repo, "commit", "-q", "-m", f"Change {path}")
    if tag:
        run(repo, "tag", "-a", tag, "-m", tag)


@pytest.fixture
def repos(tmp_path):
    up = tmp_path / "upstream"
    up.mkdir()
    run(up, "init", "-q", "-b", "main")
    commit(up, "linux/labia/app.py", "1.0.0", tag="v1.0.0")
    run(up, "branch", "develop")
    install = tmp_path / "install"
    subprocess.run(["git", "clone", "-q", str(up), str(install)], check=True)
    return up, install


def test_up_to_date(repos):
    _, install = repos
    c = updater.check(install, STABLE)
    assert c.update is None and c.reason is None and c.current == "1.0.0"


def test_new_release_only_restarts_the_platforms_it_touches(repos):
    up, install = repos
    commit(up, "windows/setup.ps1", "nuevo", tag="v1.0.1")
    win = updater.check(install, STABLE, platform="win32")
    assert win.update.label == "1.0.1" and win.update.affects and not win.update.needs_pip
    assert win.update.changed == ["windows/setup.ps1"] and win.update.branch == "main"
    assert not updater.check(install, STABLE, platform="linux").update.affects

    commit(up, "Sources/Labia/AppModel.swift", "mac", tag="v1.0.2")
    mac_only = updater.check(install, STABLE, platform="linux").update  # 1.0.0 -> 1.0.2 still includes windows/
    assert mac_only.label == "1.0.2" and not mac_only.affects


def test_mac_only_release_needs_no_restart(repos):
    up, install = repos
    commit(up, "Sources/Labia/AppModel.swift", "mac", tag="v1.0.1")
    u = updater.check(install, STABLE, platform="win32").update
    assert u.label == "1.0.1" and not u.affects


def test_requirements_change_needs_pip(repos):
    up, install = repos
    commit(up, "linux/requirements.txt", "numpy", tag="v1.1.0")
    assert updater.check(install, STABLE, platform="win32").update.needs_pip


def test_picks_highest_release_on_main_only(repos):
    up, install = repos
    commit(up, "linux/a.py", tag="v1.0.9")
    commit(up, "linux/b.py", tag="v1.0.10")  # semver, not text order
    run(up, "switch", "-q", "develop")
    commit(up, "linux/c.py", tag="v2.0.0")  # not released: only on develop
    run(up, "switch", "-q", "main")
    assert updater.check(install, STABLE).update.label == "1.0.10"


def test_never_touches_a_developer_copy(repos):
    up, install = repos
    commit(up, "linux/labia/app.py", "nuevo", tag="v1.0.1")

    (install / "linux/labia/app.py").write_text("mi cambio", encoding="utf-8")
    assert "cambios sin guardar" in updater.check(install, STABLE).reason
    run(install, "checkout", "-q", "--", ".")

    run(install, "switch", "-q", "-c", "feature/algo")
    assert "rama feature/algo" in updater.check(install, STABLE).reason
    run(install, "switch", "-q", "main")

    commit(install, "linux/mio.py", "sin subir")
    c = updater.check(install, STABLE)
    assert c.update is None and "commits que no están en GitHub" in c.reason


def test_advance_and_roll_back(repos):
    up, install = repos
    commit(up, "linux/labia/app.py", "1.0.1", tag="v1.0.1")
    u = updater.check(install, STABLE).update
    old = updater.advance(install, u)
    assert (install / "linux/labia/app.py").read_text() == "1.0.1" and updater.describe(install) == "1.0.1"
    updater.roll_back(install, old)
    assert (install / "linux/labia/app.py").read_text() == "1.0.0" and updater.describe(install) == "1.0.0"
    assert updater.check(install, STABLE, do_fetch=False).update.label == "1.0.1"  # still on main, still offered


def test_development_channel_follows_develop_and_back(repos):
    up, install = repos
    run(up, "switch", "-q", "develop")
    commit(up, "linux/labia/stream.py", "en desarrollo")
    dev_tip = run(up, "rev-parse", "HEAD")
    run(up, "switch", "-q", "main")

    u = updater.check(install, DEVELOPMENT).update
    assert u.branch == "develop" and u.target == dev_tip and u.label == f"develop {dev_tip[:7]}"
    updater.advance(install, u)
    assert run(install, "branch", "--show-current") == "develop"
    assert updater.describe(install).startswith("1.0.0+1 (")
    assert updater.check(install, DEVELOPMENT).update is None

    back = updater.check(install, STABLE).update  # back to the release, even though it is older
    assert back.branch == "main" and back.label == "1.0.0" and back.affects
    updater.advance(install, back)
    assert run(install, "branch", "--show-current") == "main" and updater.describe(install) == "1.0.0"


def test_describe_sees_git_flow_releases_from_develop(repos):
    # git flow: release/1.1.0 is merged into main (tagged there) and into develop, never main into develop.
    up, _ = repos
    run(up, "switch", "-q", "-c", "release/1.1.0", "develop")
    commit(up, "CHANGELOG.md", "1.1.0")
    run(up, "switch", "-q", "main")
    run(up, "merge", "-q", "--no-ff", "-m", "Release 1.1.0", "release/1.1.0")
    run(up, "tag", "-a", "v1.1.0", "-m", "v1.1.0")
    run(up, "switch", "-q", "develop")
    run(up, "merge", "-q", "--no-ff", "-m", "Merge release/1.1.0 into develop", "release/1.1.0")
    assert updater.describe(up).startswith("1.1.0+1 (")  # not «1.0.0+3»
    run(up, "switch", "-q", "main")
    assert updater.describe(up) == "1.1.0"


def test_not_a_git_copy(tmp_path):
    assert updater.repo_root(tmp_path) is None
