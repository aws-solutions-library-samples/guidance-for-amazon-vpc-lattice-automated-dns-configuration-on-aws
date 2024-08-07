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
                            'DNSName': vpc_lattice_name,
                            'EvaluateTargetHealth': False 
                        }
                    }
                }
            ]
        }
    )
    logger.info(response)
    
    return {
        'statusCode': 200,
        'body': response
    }