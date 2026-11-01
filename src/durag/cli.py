"""CLI entrypoint for durag."""

from durag.version import __version__


def main():
    """Main CLI entrypoint with graceful fallback if click is not yet installed."""
    try:
        import click

        @click.group()
        @click.version_option(version=__version__, prog_name="durag")
        def cli():
            """durag - Private, long-lived operational knowledge base."""
            pass

        @cli.command()
        def info():
            """Display environment and version information."""
            click.echo(f"durag version: {__version__}")
            click.echo("Status: Phase 0 bootstrap initialized")

        cli()
    except ImportError:
        import sys
        if "--version" in sys.argv or "-v" in sys.argv:
            print(f"durag {__version__}")
        else:
            print(f"durag version: {__version__}")
            print("Notice: Install dependencies via 'pip install .' to enable the full CLI interface.")


if __name__ == "__main__":
    main()
