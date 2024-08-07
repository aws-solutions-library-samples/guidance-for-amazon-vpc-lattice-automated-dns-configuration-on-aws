import json
import logging
import boto3
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')

def lambda_handler(event, context):
    # Getting SNS topic from environment variables
    sns_topic = os.environ['SNS_TOPIC']
    logger.info(sns_topic)
    # Tag SNS topic
    response = sns.tag_resource(
        ResourceArn=sns_topic,
        Tags=[
            {
                'Key': 'NewSNS',
                'Value': 'true'
            },
        ]
    )
    logger.info(response)
    
    return {
        'statusCode': 200,
        'body': response
    }