#!/bin/bash

# This script is intended to be run as a Kubernetes CronJob.
# It will first create a new snapshot, then remove old snapshots using timegaps.

set -e

echo "Running snapshot management script."

NAMESPACE="${NAMESPACE:-$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)}"
SNAPSHOT_CLASS="${SNAPSHOT_CLASS:-zfs-snap-class}"
TIMEZONE="${TIMEZONE:-UTC}"
DATE_FORMAT="${DATE_FORMAT:-%Y-%m-%d.%H-%M-%S}"
TIMEGAPS_CONFIG="${TIMEGAPS_CONFIG:-recent30,hours48,days21,weeks20,months48,years10}"
NAME_PREFIX="${NAME_PREFIX:-snap-}"

if [ -z "$PVC_NAMES" ]; then
	echo "No PersistentVolumeClaims given to take snapshots of, exiting..."
	exit 1
fi

if [ -z "$NAMESPACES" ]; then
	echo "No namespaces given to take snapshots in, exiting..."
	exit 1
fi

echo ""
echo "Settings: "
echo "SNAPSHOT_CLASS: $SNAPSHOT_CLASS"
echo "NAMESPACES: $NAMESPACES"
echo "PVC_NAMES: $PVC_NAMES"
echo "TIMEZONE: $TIMEZONE"
echo "DATE_FORMAT: $DATE_FORMAT"
echo "TIMEGAPS_CONFIG: $TIMEGAPS_CONFIG"
echo "NAME_PREFIX: $NAME_PREFIX"
echo ""

DATE=$(TZ=$TIMEZONE date +$DATE_FORMAT)
REF_DATE=$(TZ=$TIMEZONE date +%Y%m%d-%H%M%S)
echo "Current date: $DATE"
echo "timegaps reference date: $REF_DATE"
sed -i 's@${NAME_PREFIX}@'"$NAME_PREFIX"'@' /VolumeSnapshot.yaml
sed -i 's@${DATE}@'"$DATE"'@' /VolumeSnapshot.yaml
sed -i 's@${SNAPSHOT_CLASS}@'"$SNAPSHOT_CLASS"'@' /VolumeSnapshot.yaml

echo "Managing snapshots..."

PVC_NAMES_ARR=($PVC_NAMES)
NAMESPACES_ARR=($NAMESPACES)

for ((i=0; i<${#PVC_NAMES_ARR[@]}; i++)) do
	PVC=${PVC_NAMES_ARR[$i]}
	NAMESPACE=${NAMESPACES_ARR[$i]}
	echo ""
	echo ""
	echo "Managing snapshots of PVC \"$PVC\" in namespace \"$NAMESPACE\"..."
	sed 's@${PVC_NAME}@'"$PVC"'@' /VolumeSnapshot.yaml > /VolumeSnapshot-PVC.yaml
	sed -i 's@${NAMESPACE}@'"$NAMESPACE"'@' /VolumeSnapshot-PVC.yaml

	echo "Taking new snapshot..."
	kubectl create -f /VolumeSnapshot-PVC.yaml

	echo "Getting current snapshot list..."
	kubectl get -n $NAMESPACE VolumeSnapshot --template \
	'{{range .items}}{{.metadata.name}}{{" "}}{{.spec.source.persistentVolumeClaimName}}{{"\n"}}{{end}}' | \
	awk -v PVC=$PVC '$2==PVC { print $1 }' > /Snaps.txt

	echo "Current Snapshots:"
	cat /Snaps.txt

	echo ""
	echo "Finding snapshots to remove..."
	cat /Snaps.txt | timegaps --stdin $TIMEGAPS_CONFIG -t $REF_DATE --time-from-string $NAME_PREFIX$PVC-$DATE_FORMAT > \
		/ToRemove.txt

	echo "Removing these snapshots:"
	cat /ToRemove.txt

	echo ""
	echo "Removing..."
	while read TO_REMOVE; do
		kubectl delete -n $NAMESPACE VolumeSnapshot $TO_REMOVE
	done < /ToRemove.txt

	echo ""
	echo "Finished removing. Remaining snapshots:"
	kubectl get -n $NAMESPACE VolumeSnapshot --template \
	'{{range .items}}{{.metadata.name}}{{" "}}{{.spec.source.persistentVolumeClaimName}}{{"\n"}}{{end}}' | \
	awk -v PVC=$PVC '$2==PVC { print $1 }'
done

echo ""
echo "Snapshot management complete."
