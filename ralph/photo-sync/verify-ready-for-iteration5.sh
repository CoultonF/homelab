#!/bin/bash
# Verification script for Iteration 5 readiness
# Checks that both Immich and authentication are ready

set -e

echo "════════════════════════════════════════════════════════════"
echo "  Photo Sync System - Iteration 5 Readiness Check"
echo "════════════════════════════════════════════════════════════"
echo ""

READY=true

# Check 1: Photo-sync infrastructure
echo "✓ Checking photo-sync infrastructure..."
if kubectl get namespace photo-sync &>/dev/null; then
    echo "  ✅ Namespace: photo-sync exists"
else
    echo "  ❌ Namespace: photo-sync NOT FOUND"
    READY=false
fi

if kubectl get cronjob -n photo-sync icloudpd-sync &>/dev/null; then
    SCHEDULE=$(kubectl get cronjob -n photo-sync icloudpd-sync -o jsonpath='{.spec.schedule}')
    echo "  ✅ CronJob: icloudpd-sync exists (schedule: $SCHEDULE)"
else
    echo "  ❌ CronJob: icloudpd-sync NOT FOUND"
    READY=false
fi

if kubectl get pvc -n photo-sync icloud-photos &>/dev/null; then
    STATUS=$(kubectl get pvc -n photo-sync icloud-photos -o jsonpath='{.status.phase}')
    echo "  ✅ PVC: icloud-photos exists (status: $STATUS)"
    if [ "$STATUS" != "Bound" ] && [ "$STATUS" != "Pending" ]; then
        echo "     ⚠️  WARNING: Unexpected PVC status"
    fi
else
    echo "  ❌ PVC: icloud-photos NOT FOUND"
    READY=false
fi

echo ""

# Check 2: Authentication status
echo "✓ Checking iCloud authentication..."
if kubectl get secret -n photo-sync icloud-credentials &>/dev/null; then
    USERNAME=$(kubectl get secret -n photo-sync icloud-credentials -o jsonpath='{.data.username}' | base64 -d)
    echo "  ✅ Credentials: Apple ID configured ($USERNAME)"
else
    echo "  ❌ Credentials: icloud-credentials secret NOT FOUND"
    READY=false
fi

if kubectl get pvc -n photo-sync icloudpd-config &>/dev/null; then
    CONFIG_STATUS=$(kubectl get pvc -n photo-sync icloudpd-config -o jsonpath='{.status.phase}')
    echo "  ✅ Config PVC: icloudpd-config exists (status: $CONFIG_STATUS)"

    if [ "$CONFIG_STATUS" = "Bound" ]; then
        echo "     ℹ️  PVC is bound - authentication may be complete"
        echo "     💡 Verify session files exist inside the PVC"
    else
        echo "     ⚠️  PVC status: $CONFIG_STATUS (auth not yet run)"
        echo "     💡 Run authentication pod to complete Iteration 3"
    fi
else
    echo "  ❌ Config PVC: icloudpd-config NOT FOUND"
    READY=false
fi

echo ""

# Check 3: Immich installation
echo "✓ Checking Immich installation..."
IMMICH_FOUND=false
IMMICH_NAMESPACE=""
IMMICH_DEPLOYMENT=""

# Search for Immich deployments
if kubectl get deployments -A -o json | jq -r '.items[] | select(.metadata.name | contains("immich")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | grep -q immich; then
    IMMICH_DEPLOYMENTS=$(kubectl get deployments -A -o json | jq -r '.items[] | select(.metadata.name | contains("immich")) | "\(.metadata.namespace)/\(.metadata.name)"')
    echo "  ✅ Immich deployments found:"
    echo "$IMMICH_DEPLOYMENTS" | while read -r deployment; do
        NAMESPACE=$(echo "$deployment" | cut -d'/' -f1)
        NAME=$(echo "$deployment" | cut -d'/' -f2)
        REPLICAS=$(kubectl get deployment -n "$NAMESPACE" "$NAME" -o jsonpath='{.status.readyReplicas}/{.status.replicas}')
        echo "     - $NAMESPACE/$NAME (ready: $REPLICAS)"
        IMMICH_FOUND=true
        IMMICH_NAMESPACE="$NAMESPACE"
        IMMICH_DEPLOYMENT="$NAME"
    done
else
    echo "  ❌ Immich: NOT FOUND"
    echo "     💡 Install Immich to proceed with Iteration 5"
    READY=false
fi

if [ "$IMMICH_FOUND" = true ]; then
    # Check for Immich service
    if kubectl get svc -n "$IMMICH_NAMESPACE" -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name | contains("immich")) | "\(.metadata.name):\(.spec.ports[0].port)"' | grep -q .; then
        echo "  ✅ Immich services found:"
        kubectl get svc -n "$IMMICH_NAMESPACE" -o json | jq -r '.items[] | select(.metadata.name | contains("immich")) | "     - \(.metadata.name):\(.spec.ports[0].port)"'
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════"

# Final status
if [ "$READY" = true ]; then
    echo "  ✅ READY FOR ITERATION 5"
    echo ""
    echo "  Next steps:"
    echo "  1. Review REMAINING_ITERATIONS_GUIDE.md"
    echo "  2. Continue to Iteration 5: Immich Integration"
    echo ""
    if [ "$CONFIG_STATUS" != "Bound" ]; then
        echo "  ⚠️  NOTE: Authentication may not be complete yet"
        echo "     This is OK - you can proceed with Iteration 5"
        echo "     Just complete authentication before running the CronJob"
        echo ""
    fi
else
    echo "  ❌ NOT READY - Action required"
    echo ""
    echo "  See: USER_ACTION_REQUIRED.md for next steps"
    echo ""
fi

echo "════════════════════════════════════════════════════════════"

exit 0
