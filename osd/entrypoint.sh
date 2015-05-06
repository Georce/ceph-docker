#!/bin/bash
set -e

: ${CLUSTER:=ceph}
: ${WEIGHT:=1.0}

# CONFIG_ROOT - etcd root for ceph-related keys
: ${CONFIG_ROOT:=/ceph}

# CLUSTER_PATH - etcd path where configuration should be stored
: ${CLUSTER_PATH:=${CONFIG_ROOT}/${CLUSTER}/config}

# ETCDCTL_PEERS - where to find etcd peers by Georce

if [ -n "${ETCDCTL_PEERS}" ]; then
  echo "Downloading the Configuration from Etcd"
  echo "Configuration found for cluster ${CLUSTER}. Writing to disk."
  
  etcdctl -C ${ETCDCTL_PEERS} --no-sync get ${CLUSTER_PATH}/ceph.conf > /etc/ceph/ceph.conf
  etcdctl -C ${ETCDCTL_PEERS} --no-sync get ${CLUSTER_PATH}/ceph.mon.keyring > /etc/ceph/ceph.mon.keyring
  etcdctl -C ${ETCDCTL_PEERS} --no-sync get ${CLUSTER_PATH}/ceph.client.admin.keyring > /etc/ceph/ceph.client.admin.keyring
fi

for OSD_ID in $(ls /var/lib/ceph/osd |  awk 'BEGIN { FS = "-" } ; { print $2 }')
do
   if [ -n "${JOURNAL_DIR}" ]; then
      OSD_J="${JOURNAL_DIR}/journal.${OSD_ID}"
   else      
      if [ -n "${JOURNAL}" ]; then
         OSD_J=${JOURNAL}
      else
         OSD_J=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/journal
      fi
   fi

   # Check to see if our OSD has been initialized
   if [ ! -e /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring ]; then
      # Create OSD key and file structure
      ceph-osd -i $OSD_ID --mkfs --mkjournal --osd-journal ${OSD_J}

      # Add OSD key to the authentication database
      if [ ! -e /etc/ceph/${CLUSTER}.client.admin.keyring ]; then
         echo "Cannot authenticate to Ceph monitor without /etc/ceph/${CLUSTER}.client.admin.keyring.  Retrieve this from /etc/ceph on a monitor node."
         exit 1
      fi
      ceph auth get-or-create osd.${OSD_ID} osd 'allow *' mon 'allow profile osd' -o /var/lib/ceph/osd/${CLUSTER}-${OSD_ID}/keyring

      # Add the OSD to the CRUSH map
      if [ ! -n "${HOSTNAME}" ]; then
         echo "HOSTNAME not set; cannot add OSD to CRUSH map"
         exit 1
      fi
      ceph osd crush add ${OSD_ID} ${WEIGHT} root=default host=${HOSTNAME}
   fi

   mkdir -p /etc/service/ceph-${OSD_ID}
   cat >/etc/service/ceph-${OSD_ID}/run <<EOF
#!/bin/bash
echo "store-daemon: starting daemon on ${HOSTNAME}..."
exec ceph-osd -f -d -i ${OSD_ID} --osd-journal ${OSD_J} -k /var/lib/ceph/osd/ceph-${OSD_ID}/keyring
EOF

   chmod +x /etc/service/ceph-${OSD_ID}/run

done

read
