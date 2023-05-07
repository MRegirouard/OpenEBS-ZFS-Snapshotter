# Uses the kubectl image from Bitnami, and installs timegaps on top of it
FROM bitnami/kubectl

# Switch to root to install python, pip, and then timegaps
USER root
RUN apt update -y
RUN apt install -y python3 python3-pip

# Install timegaps from the dev-reset-2017 branch
# This version keeps the oldest item from a "bucket", instead of the newest and seems to work better
RUN pip install git+https://github.com/jgehrcke/timegaps.git@6065b60283f464fc04b132d98de40fc30786f27b

# Switch back to the regular user
USER 1001

# Make sure timegaps can be used
RUN timegaps --help

# Copy necessary files into the container
COPY VolumeSnapshot.yaml /
COPY ManageSnaps.sh /

ENTRYPOINT [ "/ManageSnaps.sh" ]
