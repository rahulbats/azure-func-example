import azure.functions as func
import os
import logging
from azure.identity import DefaultAzureCredential
from azure.appconfiguration import AzureAppConfigurationClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# Initialize App Configuration client
def get_app_config_client():
    """Create an App Configuration client using managed identity."""
    app_config_endpoint = os.environ.get("APP_CONFIG_ENDPOINT")
    if not app_config_endpoint:
        logging.warning("APP_CONFIG_ENDPOINT not set, will fall back to environment variables")
        return None
    
    credential = DefaultAzureCredential()
    return AzureAppConfigurationClient(endpoint=app_config_endpoint, credential=credential)

@app.route(route="azure_func_example_with_app_config")
def azure_func_example_with_app_config(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')

    try:
        # Try to get configurations from App Configuration
        client = get_app_config_client()
        if client:
            try:
                app_name = client.get_configuration_setting(key="APP_NAME").value
                app_version = client.get_configuration_setting(key="APP_VERSION").value
                logging.info(f"Retrieved configuration from App Configuration")
            except Exception as e:
                logging.warning(f"Failed to get config from App Configuration: {e}")
                # Fall back to environment variables
                app_name = os.environ.get("APP_NAME", "")
                app_version = os.environ.get("APP_VERSION", "")
        else:
            # Fall back to environment variables if endpoint not available
            app_name = os.environ.get("APP_NAME", "")
            app_version = os.environ.get("APP_VERSION", "")

        logging.info(f"APP_NAME={app_name}")
        logging.info(f"APP_VERSION={app_version}")

        if app_name:
            return func.HttpResponse(f"these are the app details,app-name {app_name}, app-version {app_version}. This HTTP triggered function executed successfully.")
        else:
            return func.HttpResponse(
                 f"{app_name} configuration is not set.",
                 status_code=200
            )
    except Exception as e:
        logging.error(f"Error in function: {e}")
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)