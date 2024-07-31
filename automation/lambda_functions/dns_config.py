import json
import logging
import boto3
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

router = boto3.client('route53')
sns = boto3.client('sns')

def lambda_handler(event, context):
    message = event['Records'][0]
    x = json.loads(message['body'])
    message = x['Message']
    logger.info(message)
    m = json.loads(message)
    custom_domain_name = m["Custom Domain Name"]
    vpc_lattice_name = m["VPC Lattice Domain Name"]
    vpc_lattice_hostedzone = m["VPC Lattice Hosted Zone ID"]

    # Update PHZ / Create ALIAS record in Route 53
    response = router.change_resource_record_sets(
    HostedZoneId=os.environ['PHZ_ID'],
    ChangeBatch={
    'Changes': [
        {
            'Action': 'UPSERT',
            'ResourceRecordSet': {
                'Name': custom_domain_name,
                'Type': 'A',
                'AliasTarget': {
                    'HostedZoneId': vpc_lattice_hostedzone,
                    'DNSName': vpc_lattice_name,  # Specify the DNS name of the target resource
                    'EvaluateTargetHealth': False  # Set to True if you want Route 53 to evaluate the health of the target resource
                }
            }
        }
    ]
    }
    )

    logger.info(response)

    sns.publish(
            TopicArn="arn:aws:sns:eu-west-1:590183737881:SNS_TOPIC_PHZ_UPDATED",
            Message=json.dumps("PHZ updated"),
            Subject='PHZ updated'
    )
    

    return {
        'statusCode': 200,
        'body': json.dumps('Hello from Lambda!')
    }


