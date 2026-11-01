"""Basic tests for package imports and versioning."""

import unittest
from durag import __version__
from durag.version import __version__ as version_var


class TestDuragPackage(unittest.TestCase):
    def test_version(self):
        """Verify package version is set."""
        self.assertEqual(__version__, "0.1.0")
        self.assertEqual(version_var, "0.1.0")

    def test_cli_import(self):
        """Verify CLI entrypoint is importable."""
        from durag.cli import main
        self.assertTrue(callable(main))


if __name__ == "__main__":
    unittest.main()
