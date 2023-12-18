
import json
import subprocess
import time

from pytest_httpserver import HTTPServer  # type: ignore
from typing import Any

def webhook_send(httpserver: HTTPServer, keyData: str, event: str, message: str ) -> None:
    httpserver.expect_request("/endpoint", method="POST").respond_with_data("OK")
    
    if event == "INFO": 
        # including message in bash call
        subprocess.Popen(['bash', '-c', 'WEBHOOK_RECEIVER_URL={0}; WEBHOOK_KEY_DATA={1}; source tests/ocrd_lib_test.sh; webhook_send_{2} {3}'.format(httpserver.url_for("/endpoint"), keyData, event.lower(), message) ], 
                          stdout=subprocess.PIPE)
    else:    
        subprocess.Popen(['bash', '-c', 'WEBHOOK_RECEIVER_URL={0}; WEBHOOK_KEY_DATA={1}; source tests/ocrd_lib_test.sh; webhook_send_{2}'.format(httpserver.url_for("/endpoint"), keyData, event.lower()) ])
    
    time.sleep(1)

    assert len(httpserver.log) == 1

    request, response = httpserver.log[0]

    jsonStr = request.get_data().decode("utf-8")

    jsonData = validateJSON(jsonStr)
    if jsonData :
        assert jsonData["key-data"] == keyData
        assert jsonData["event"] == event
        assert jsonData["message"] == message
      
def test_webhook_info(httpserver: HTTPServer) -> None:
    webhook_send(httpserver, "test_info", "INFO", "hello")

def test_webhook_error(httpserver: HTTPServer) -> None:
    webhook_send(httpserver, "test_error", "ERROR", "Error occured during the OCR processing")    

def test_webhook_started(httpserver: HTTPServer) -> None:
    webhook_send(httpserver, "test_started", "STARTED", "OCR processing started")    

def test_webhook_completed(httpserver: HTTPServer) -> None:
    webhook_send(httpserver, "test_completed", "COMPLETED", "OCR processing completed")    

def validateJSON(jsonStr: str) -> Any:
    try:
        return json.loads(jsonStr)
    except ValueError:
        assert False, f"The json set to the receiver is not valid."
    