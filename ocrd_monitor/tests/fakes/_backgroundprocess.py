import multiprocessing as mp
import time
from typing import Any, Protocol


class AnyFunc(Protocol):
    def __call__(self, *args, **kwargs) -> Any:
        ...


class BackgroundProcess:
    def __init__(self, process_func: AnyFunc, *args: Any) -> None:
        self._process: mp.Process | None = None
        self._func = process_func
        self._args = args

    def __enter__(self) -> "BackgroundProcess":
        self.launch()
        return self

    def __exit__(self, *args: Any, **kwargs: Any) -> None:
        self.shutdown()

    @property
    def is_running(self) -> bool:
        return self._process is not None and self._process.is_alive()

    def launch(self) -> None:
        if self.is_running:
            return

        self._process = mp.Process(target=self._func, args=self._args)

        self._process.start()
        time.sleep(1)

    def shutdown(self) -> None:
        if not self.is_running:
            return

        self._process.kill()  # type: ignore
        self._process = None
