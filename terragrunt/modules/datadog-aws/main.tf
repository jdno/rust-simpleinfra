locals {
  datadog_iam_role_name = "DatadogAWSIntegrationRole"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "datadog" {
  name        = "DatadogAWSIntegrationPolicy"
  description = "Read-only access for Datadog"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "apigateway:GET",
          "autoscaling:Describe*",
          "backup:List*",
          "budgets:ViewBudget",
          "cloudfront:GetDistributionConfig",
          "cloudfront:ListDistributions",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrailStatus",
          "cloudtrail:LookupEvents",
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "codedeploy:List*",
          "codedeploy:BatchGet*",
          "directconnect:Describe*",
          "dynamodb:List*",
          "dynamodb:Describe*",
          "ec2:Describe*",
          "ecs:Describe*",
          "ecs:List*",
          "elasticache:Describe*",
          "elasticache:List*",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeTags",
          "elasticfilesystem:DescribeAccessPoints",
          "elasticloadbalancing:Describe*",
          "elasticmapreduce:List*",
          "elasticmapreduce:Describe*",
          "es:ListTags",
          "es:ListDomainNames",
          "es:DescribeElasticsearchDomains",
          "events:CreateEventBus",
          "fsx:DescribeFileSystems",
          "fsx:ListTagsForResource",
          "health:DescribeEvents",
          "health:DescribeEventDetails",
          "health:DescribeAffectedEntities",
          "kinesis:List*",
          "kinesis:Describe*",
          "lambda:GetPolicy",
          "lambda:List*",
          "logs:DeleteSubscriptionFilter",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:DescribeSubscriptionFilters",
          "logs:FilterLogEvents",
          "logs:PutSubscriptionFilter",
          "logs:TestMetricFilter",
          "organizations:Describe*",
          "organizations:List*",
          "rds:Describe*",
          "rds:List*",
          "redshift:DescribeClusters",
          "redshift:DescribeLoggingStatus",
          "route53:List*",
          "s3:GetBucketLogging",
          "s3:GetBucketLocation",
          "s3:GetBucketNotification",
          "s3:GetBucketTagging",
          "s3:ListAllMyBuckets",
          "s3:PutBucketNotification",
          "ses:Get*",
          "sns:List*",
          "sns:Publish",
          "sqs:ListQueues",
          "states:ListStateMachines",
          "states:DescribeStateMachine",
          "support:DescribeTrustedAdvisor*",
          "support:RefreshTrustedAdvisorCheck",
          "tag:GetResources",
          "tag:GetTagKeys",
          "tag:GetTagValues",
          "xray:BatchGetTraces",
          "xray:GetTraceSummaries"
        ],
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "datadog" {
  name = local.datadog_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          AWS = "464622532012"
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = datadog_integration_aws.aws.external_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "datadog" {
  role       = aws_iam_role.datadog.name
  policy_arn = aws_iam_policy.datadog.arn
}

resource "datadog_integration_aws" "aws" {
  account_id = data.aws_caller_identity.current.account_id
  role_name  = local.datadog_iam_role_name
}

data "aws_ssm_parameter" "datadog_api_key" {
  name = "/prod/datadog-aws/datadog-api-key"
}

resource "aws_secretsmanager_secret" "datadog_api_key" {
  name        = "datadog_api_key"
  description = "Encrypted Datadog API Key"
}

resource "aws_secretsmanager_secret_version" "datadog_api_key" {
  secret_id     = aws_secretsmanager_secret.datadog_api_key.id
  secret_string = data.aws_ssm_parameter.datadog_api_key.value
}

# Use the Datadog Forwarder to ship logs from S3 and CloudWatch, as well as
# observability data from Lambda functions to Datadog. For more information,
# see https://github.com/DataDog/datadog-serverless-functions/tree/master/aws/logs_monitoring
resource "aws_cloudformation_stack" "datadog_forwarder" {
  name         = "datadog-forwarder"
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM", "CAPABILITY_AUTO_EXPAND"]
  parameters = {
    DdApiKeySecretArn = aws_secretsmanager_secret.datadog_api_key.arn
    DdSite            = "datadoghq.com"
    FunctionName      = "datadog-forwarder"
  }
  template_url = "https://datadog-cloudformation-template.s3.amazonaws.com/aws/forwarder/latest.yaml"
}

data "aws_lambda_function" "datadog_forwarder" {
  depends_on = [aws_cloudformation_stack.datadog_forwarder]

  function_name = aws_cloudformation_stack.datadog_forwarder.name
}

data "aws_s3_bucket" "logs" {
  for_each = toset(var.s3_log_buckets)
  bucket   = each.value
}

resource "aws_s3_bucket_notification" "logs_to_datadog" {
  for_each = data.aws_s3_bucket.logs

  bucket = each.value.bucket

  lambda_function {
    lambda_function_arn = data.aws_lambda_function.datadog_forwarder.arn
    events              = ["s3:ObjectCreated:*"]
  }
}
