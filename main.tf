resource "random_string" "random" {
  length  = 4
  lower   = true
  special = false
  upper   = false
}

module "hive_sechub_cloudwatch_event" {
  source = "git::https://github.com/cloudposse/terraform-aws-cloudwatch-events.git?ref=0.6.1"
  name   = "hive_sechub_cloudwatch-${random_string.random.id}"

  cloudwatch_event_rule_description = var.cloudwatch_event_rule_description
  cloudwatch_event_rule_pattern     = var.cloudwatch_event_rule_pattern
  cloudwatch_event_target_arn       = module.sechub_to_hive_lambda.lambda_function_arn
}

module "hive_sechub_iam_assumable_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "4.10.1"

  trusted_role_services = [
    "lambda.amazonaws.com"
  ]

  create_role = true

  role_name         = "SechubToHiveFindingsLambdaRole-${random_string.random.id}"
  role_requires_mfa = false

  custom_role_policy_arns = [
    module.hive_sechub_iam_policy.arn
  ]
}

data "aws_iam_policy_document" "jira_sec_hub_iam_policy" {
  statement {
    actions = [
      "cloudwatch:PutMetricData",
    ]

    resources = [
      "*"
    ]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "*"
    ]
  }

  statement {
    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      var.hive_api_secret_arn
    ]
  }

  statement {
    actions = [
      "kms:Decrypt",
    ]

    resources = [
      var.hive_api_secret_kms_key_arn
    ]
  }

  statement {
    actions = [
      "securityhub:BatchUpdateFindings"
    ]

    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "securityhub:ASFFSyntaxPath/Workflow.Status"

      values = [
        "NOTIFIED",
      ]
    }
  }
}

module "hive_sechub_iam_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "4.10.1"

  name        = "SechubToHiveFindingsLambda-Policy-${random_string.random.id}"
  path        = "/"
  description = "SechubToHiveFindingsLambda-Policy"
  policy      = data.aws_iam_policy_document.jira_sec_hub_iam_policy.json
}

resource "aws_lambda_permission" "hive_sechub_allow_cloudwatch" {
  statement_id  = "PermissionForEventsToInvokeLambdachk-${random_string.random.id}"
  action        = "lambda:InvokeFunction"
  function_name = module.sechub_to_hive_lambda.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.hive_sechub_cloudwatch_event.aws_cloudwatch_event_rule_arn
}

data "archive_file" "sechub_to_hive_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "lambda_sechub_hive.zip"
}

module "thehive4py_layer" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "2.7.0"

  create_layer = true

  layer_name          = "thehive4py-layer-local"
  description         = "Lambda layer containing thehive4py"
  compatible_runtimes = ["python3.9"]

  create_package         = false
  local_existing_package = "${path.module}/layer.zip"
  tags                   = var.tags
}

module "sechub_to_hive_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "2.7.0"

  function_name  = "sechub-to-hive"
  description    = "function to send sechub findings to the hive"
  handler        = "lambda_sechub_hive.lambda_handler"
  runtime        = "python3.9"
  create_package = false

  local_existing_package = "lambda_sechub_hive.zip"

  environment_variables = {
    hiveSecretArn        = var.hive_api_secret_arn
    createHiveAlert      = var.create_hive_alert
    environment          = var.environment
    excludeAccountFilter = jsonencode(var.exclude_account_filter)
    company              = var.company
    project              = var.project
  }

  layers = [
    module.thehive4py_layer.lambda_layer_arn,
  ]

  attach_policies    = true
  policies           = [module.hive_sechub_iam_policy.arn]
  number_of_policies = 1
  tags               = var.tags
}
