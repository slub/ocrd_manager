import nox


@nox.session(python=("3.9", "3.10", "3.11"))
def mypy(session: nox.Session) -> None:
    session.install("-r", "requirements.txt")
    session.install("-r", "requirements.dev.txt")
    session.install("mypy")
    session.run(
        "mypy", "--non-interactive", "--install-types", "ocrdbrowser", "ocrdmonitor"
    )
    session.run("mypy", "--strict", "ocrdbrowser", "ocrdmonitor")


@nox.session(python=("3.9", "3.10", "3.11"))
def pytest(session: nox.Session) -> None:
    session.install("-r", "requirements.txt")
    session.install("-r", "requirements.dev.txt")
    session.install("pytest")
    session.install("pytest-clarity")

    session.run("pytest", "-vv", "tests")
