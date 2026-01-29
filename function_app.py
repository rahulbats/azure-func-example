import azure.functions as func
import os
import logging

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

@app.route(route="azure_func_example_with_variable")
def azure_func_example_with_variable(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')


    app_name = os.environ.get("APP_NAME", "")
    app_version = os.environ.get("APP_VERSION", "")

    logging.info(f"APP_NAME={app_name}")
    logging.info(f"APP_VERSION={app_version}")


    if app_name:
        return func.HttpResponse(f"these are the app details,app-name {app_name}, app-version {app_version}. This HTTP triggered function executed successfully.")
    else:
        return func.HttpResponse(
             "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.",
             status_code=200
        )