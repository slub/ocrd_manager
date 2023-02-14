from ocrdmonitor.server.settings import Settings
from ocrdmonitor.server.app import create_app

settings = Settings()
app = create_app(settings)
