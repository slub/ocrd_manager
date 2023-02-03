from fastapi import APIRouter, Response, Request
from fastapi.templating import Jinja2Templates
from fastapi.responses import RedirectResponse


def create_logview(templates: Jinja2Templates, port: int) -> APIRouter:
    router = APIRouter()

    @router.get("/logview")
    def logview(request: Request) -> Response:
        url = request.url.replace(port=str(port), path='/')
        return RedirectResponse(url)

    return router
