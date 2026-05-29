#!/bin/bash
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/aws-functions.sh

if [ "$DEBUG" = true ]; then
  set -x
fi

# ----------------------------
# IAM ROLE ASSUMPTION
# ----------------------------
if [ "$ASSUME_OTHER_ROLE" == true ]; then
  role_output=$(aws sts assume-role \
    --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME \
    --role-session-name $ROLE_SESSION_NAME)

  if [ $? -ne 0 ]; then
    logErrorMessage "ERROR: Failed to assume role."
    exit 1
  fi

  export AWS_ACCESS_KEY_ID=$(echo $role_output | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo $role_output | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo $role_output | jq -r '.Credentials.SessionToken')

  logInfoMessage "Assumed Role Identity:"
  aws sts get-caller-identity --region "$AWS_REGION"
fi

# ----------------------------
# INPUTS
# ----------------------------
TAG_KEY=${TAG_KEY}
TAG_VALUE=${TAG_VALUE}
ACTION=${ACTION}               # Set | ScaleUp | ScaleDown
DESIRED_CAPACITY=${DESIRED_CAPACITY}

logInfoMessage "-------------------------------------"
logInfoMessage "ASG TAG     : $TAG_KEY=$TAG_VALUE"
logInfoMessage "ACTION      : $ACTION"
logInfoMessage "VALUE       : $DESIRED_CAPACITY"
logInfoMessage "-------------------------------------"

# ----------------------------
# GET ASGs
# ----------------------------
ASG_NAMES=$(aws autoscaling describe-tags \
  --filters "Name=key,Values=$TAG_KEY" "Name=value,Values=$TAG_VALUE" \
  --query "Tags[].ResourceId" \
  --output text)

if [ -z "$ASG_NAMES" ]; then
  echo "No matching ASGs found."
  exit 0
fi

logInfoMessage "Found ASGs: $ASG_NAMES"

FAILED=""

# ----------------------------
# PROCESS ASGs
# ----------------------------
for asg in $ASG_NAMES; do
  logInfoMessage "====================================="
  logInfoMessage "Processing ASG: $asg"

  CURRENT_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$asg" \
    --query "AutoScalingGroups[0].DesiredCapacity" \
    --output text)

  logInfoMessage "Current Desired Capacity: $CURRENT_DESIRED"

  # ----------------------------
  # CALCULATE NEW DESIRED
  # ----------------------------
  if [ "$ACTION" == "Set" ]; then
    NEW_DESIRED=$DESIRED_CAPACITY

  elif [ "$ACTION" == "ScaleUp" ]; then
    NEW_DESIRED=$((CURRENT_DESIRED + DESIRED_CAPACITY))

  elif [ "$ACTION" == "ScaleDown" ]; then
    NEW_DESIRED=$((CURRENT_DESIRED - DESIRED_CAPACITY))

  else
    logErrorMessage "ERROR: Invalid ACTION"
    exit 1
  fi

  # Safety
  if [ "$NEW_DESIRED" -lt 0 ]; then
    NEW_DESIRED=0
  fi

  logInfoMessage "Final Desired Capacity => $NEW_DESIRED"

  # ----------------------------
  #  KEY FIX: FIRST SET MIN/MAX SAME VALUE
  # ----------------------------
  logInfoMessage "Setting MIN/MAX equal to DesiredCapacity..."

  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$asg" \
    --min-size "$NEW_DESIRED" \
    --max-size "$NEW_DESIRED"

  # ----------------------------
  # THEN SET DESIRED
  # ----------------------------
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$asg" \
    --desired-capacity "$NEW_DESIRED"

  if [ $? -ne 0 ]; then
    logErrorMessage "FAILED: Update failed for $asg"
    FAILED="$FAILED\n$asg"
    continue
  fi

  logInfoMessage "SUCCESS: ASG locked to $NEW_DESIRED"
done

# ----------------------------
# FINAL RESULT
# ----------------------------
echo "====================================="

if [ -n "$FAILED" ]; then
  echo -e "Some ASG updates failed:\n$FAILED"
  exit 1
else
  logInfoMessage "All ASG operations completed successfully."
fi
