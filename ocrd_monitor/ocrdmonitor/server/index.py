from fastapi import APIRouter, Response, Request
from fastapi.templating import Jinja2Templates


def create_index(templates: Jinja2Templates) -> APIRouter:
    router = APIRouter()

    @router.get("/")
    def index(request: Request) -> Response:
        return templates.TemplateResponse("index.html.j2", {"request": request})

    return router
