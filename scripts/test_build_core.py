"""Exercise the build script against local Git remotes and a fake compiler."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


BUILD_SCRIPT = Path(__file__).with_name("build-core-libraries.sh")


class BuildCoreTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="huginn-core-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.env = dict(os.environ)
        self.env.update(
            GIT_CONFIG_NOSYSTEM="1",
            GIT_CONFIG_GLOBAL="/dev/null",
            GIT_ALLOW_PROTOCOL="file",
            GIT_AUTHOR_NAME="Build test",
            GIT_AUTHOR_EMAIL="build@example.invalid",
            GIT_COMMITTER_NAME="Build test",
            GIT_COMMITTER_EMAIL="build@example.invalid",
        )
        self.upstream = self.directory / "core"
        parent = self.directory / "parent"
        self.git(self.directory, "init", "-b", "main", str(self.upstream))
        self.first = self.advance_core("first")
        self.git(self.directory, "init", "-b", "main", str(parent))
        (parent / "scripts").mkdir()
        shutil.copy2(BUILD_SCRIPT, parent / "scripts" / BUILD_SCRIPT.name)
        self.git(parent, "submodule", "add", "-b", "main", str(self.upstream), "src/huginn-messenger")
        self.git(parent, "add", ".")
        self.git(parent, "commit", "-m", "Record first core revision")
        self.checkout = self.directory / "client"
        self.git(self.directory, "clone", str(parent), str(self.checkout))
        self.latest = self.advance_core("second")

        binaries = self.directory / "bin"
        binaries.mkdir()
        fake_go = binaries / "go"
        fake_go.write_text("""#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
if sys.argv[1:] == ['env', 'GOHOSTARCH']:
    print('amd64')
    sys.exit(0)
assert sys.argv[1] == 'build'
assert '-buildmode=c-shared' in sys.argv
assert '-ldflags=-checklinkname=0' in sys.argv
output = Path(sys.argv[sys.argv.index('-o') + 1])
payload = {key: os.environ.get(key, '') for key in ['GOOS', 'GOARCH', 'GOARM', 'CC', 'CGO_ENABLED']}
payload['source'] = Path('revision.txt').read_text()
output.write_text(json.dumps(payload))
output.with_suffix('.h').write_text('generated header')
""")
        fake_go.chmod(0o755)
        self.env["PATH"] = str(binaries) + os.pathsep + self.env["PATH"]
        ndk = self.directory / "ndk with spaces"
        ndk_bin = ndk / "toolchains/llvm/prebuilt/linux-x86_64/bin"
        ndk_bin.mkdir(parents=True)
        for triple in ("aarch64-linux-android", "armv7a-linux-androideabi", "x86_64-linux-android", "i686-linux-android"):
            compiler = ndk_bin / f"{triple}24-clang"
            compiler.write_text("#!/bin/sh\nexit 0\n")
            compiler.chmod(0o755)
        self.env["ANDROID_NDK_HOME"] = str(ndk)

    def git(self, cwd, *arguments):
        result = subprocess.run(
            ["git", "-C", str(cwd), *arguments], env=self.env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        return result.stdout.strip()

    def advance_core(self, value):
        (self.upstream / "revision.txt").write_text(value)
        self.git(self.upstream, "add", ".")
        self.git(self.upstream, "commit", "-m", value)
        return self.git(self.upstream, "rev-parse", "HEAD")

    def build(self, target="all"):
        return subprocess.run(
            ["bash", str(self.checkout / "scripts" / BUILD_SCRIPT.name), target],
            cwd=self.directory, env=self.env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )

    def test_build_fetches_main_and_packages_every_platform(self):
        # Even a local branch override must not select an old revision.
        self.git(self.checkout, "config", "submodule.src/huginn-messenger.branch", "missing-branch")
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stdout)
        core = self.checkout / "src/huginn-messenger"
        self.assertEqual(self.git(core, "rev-parse", "HEAD"), self.latest)
        self.assertIn(self.first, self.git(self.checkout, "ls-tree", "HEAD", "src/huginn-messenger"))
        linux = self.checkout / "native/linux/amd64/libhuginn_messenger.so"
        self.assertEqual(json.loads(linux.read_text())["source"], "second")
        self.assertEqual(json.loads(linux.read_text())["GOOS"], "linux")
        self.assertEqual((self.checkout / "native/include/libhuginn_messenger.h").read_text(), "generated header")
        for abi, arch, arm in (("arm64-v8a", "arm64", ""), ("armeabi-v7a", "arm", "7"), ("x86_64", "amd64", ""), ("x86", "386", "")):
            library = self.checkout / f"android/app/src/main/jniLibs/{abi}/libhuginn_messenger.so"
            payload = json.loads(library.read_text())
            self.assertEqual((payload["GOOS"], payload["GOARCH"], payload["GOARM"], payload["CGO_ENABLED"]), ("android", arch, arm, "1"))
            self.assertEqual(payload["source"], "second")
            self.assertTrue(payload["CC"].endswith("24-clang"))
        third = self.advance_core("third")
        result = self.build("linux")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.git(core, "rev-parse", "HEAD"), third)
        self.assertEqual(json.loads(linux.read_text())["source"], "third")

    def test_dirty_core_is_preserved(self):
        self.assertEqual(self.build("linux").returncode, 0)
        source = self.checkout / "src/huginn-messenger/revision.txt"
        source.write_text("local edit")
        self.advance_core("third")
        result = self.build("linux")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local changes", result.stdout)
        self.assertEqual(source.read_text(), "local edit")

    def test_fetch_failure_stops_before_compiling(self):
        self.assertEqual(self.build("linux").returncode, 0)
        library = self.checkout / "native/linux/amd64/libhuginn_messenger.so"
        library.write_text("previous artifact")
        self.upstream.rename(self.directory / "unavailable-core")
        result = self.build("linux")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(library.read_text(), "previous artifact")

    def test_linux_build_does_not_require_ndk(self):
        self.env["ANDROID_NDK_HOME"] = str(self.directory / "missing-ndk")
        result = self.build("linux")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.checkout / "android").exists())
        result = self.build("android")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Android NDK compiler not found", result.stdout)

    def test_ndk_discovery_uses_latest_version_directory(self):
        ndk = Path(self.env.pop("ANDROID_NDK_HOME"))
        self.env.pop("ANDROID_NDK_ROOT", None)
        sdk = self.directory / "sdk"
        versions = sdk / "ndk"
        versions.mkdir(parents=True)
        shutil.copytree(ndk, versions / "9.0.0")
        shutil.copytree(ndk, versions / "28.2.13676358")
        shutil.copytree(ndk, versions / "wrap.sh")
        self.env["ANDROID_HOME"] = str(sdk)
        result = self.build("android")
        self.assertEqual(result.returncode, 0, result.stdout)
        library = self.checkout / "android/app/src/main/jniLibs/arm64-v8a/libhuginn_messenger.so"
        self.assertIn("/ndk/28.2.13676358/", json.loads(library.read_text())["CC"])


if __name__ == "__main__":
    unittest.main()
