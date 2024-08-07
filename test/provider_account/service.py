import json
import logging
import os

log = logging.getLogger("handler")
log.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        # Obtain AWS Region where the Lambda function is located
        region = os.environ.get('AWS_REGION')
        # Log the event received
        log.info("Received event: %s", json.dumps(event))

        # Return value
        response = region
        return {
            "statusCode": 200,
            "statusDescription": "200 OK",
            "body": response
        }

    except Exception as e:
        log.exception("whoops")
        log.info(e)

        # Return exception error
        return {
            "statusCode": 500,
            "statusDescription": "500 Internal Server Error",
            "body": "Server error - check lambda logs\n"
        }