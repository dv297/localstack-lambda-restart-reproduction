# Issue Reproduction

To see the issue, perform the following steps:

```bash
# Set up virtual environment
pyenv local 3.11
. ./setup_virtualenv.sh

# Spin up application in LocalStack
cd terraform
terraform init
localstack start -D
tflocal apply --var "stack_name=local" --var "is_localstack_deploy=true" -auto-approve
```