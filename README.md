

## Setup

1. Setup terraform, AWS, etc.
2. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`, adjust as needed
3. Review `app.ts` (handler) and `lambda.ts` (event loop)

## Deploy

```shell
# increment version number in VERSION

# build a zipfile...
make zipfile

# ... upload to S3 and deploy/update the lambda WITH NO CONFIRMATION
make terraform
```

If successful, terraform will output a `curl` command to run to test the deployment. `curl` output should include:

```json
{"message":"Hello, World!"}
```

## Cleanup

```shell
# remove all terraform AWS resources
make destroy
```

## Attribution
Based on https://github.com/denoland/deno-lambda