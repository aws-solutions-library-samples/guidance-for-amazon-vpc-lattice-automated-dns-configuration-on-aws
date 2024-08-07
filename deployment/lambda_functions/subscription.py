import json
import logging
import boto3
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')
sqs = boto3.client('sqs')

def lambda_handler(event, context):

    sqs_arn = os.environ['SQS_ARN']
    sns_arn = event['resources'][0]
    tag_value = event['detail']['tags']['NewSNS']

    if tag_value == 'true':
        logger.info('New service SNS topic tag found')
        logger.info('SNS ARN: {}'.format(sns_arn))

        # Subscribe the SQS queue to the SNS topic
        response = sns.subscribe(
                TopicArn = sns_arn,
                Protocol = 'sqs',
                Endpoint = sqs_arn,
                ReturnSubscriptionArn = True
        )
    
    return {
        'statusCode': 200,
        'body': response
    }
