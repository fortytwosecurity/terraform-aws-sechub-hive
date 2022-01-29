# Terraform Aws Ecr Scan Hive

secret value:

```
{
  "url": "https://hive.domain.com",
  "apikey": "putapikeyhere"
}
```

Make sure to only trigger the lambda for findings with workflow status NEW,
for example the following filter:

```
  sechub_cloudwatch_event_rule_pattern = {
    "source" : [
      "aws.securityhub"
    ],
    "detail-type" : [
      "Security Hub Findings - Imported"
    ],
    "detail" : {
      "findings" : {
        "Compliance" : {
          "Status" : [
            "FAILED"
          ]
        },
        "Severity" : {
          "Normalized" : [{ "numeric" : [">=", 40] }]
        },
        "Workflow" : {
          "Status" : [
            "NEW"
          ]
        }
      }
    }
  }
  ```

<!--- BEGIN_TF_DOCS --->

<!--- END_TF_DOCS --->
