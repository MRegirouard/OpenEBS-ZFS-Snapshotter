# Uses the kubectl image from Bitnami, and installs timegaps on top of it
FROM bitnami/kubectl

# Switch to root to install python, pip, and then timegaps
USER root
RUN apt update -y
RUN apt install -y python3 python3-pip
RUN pip install timegaps

# Switch back to the regular user
USER 1001

# Make sure timegaps can be used
RUN timegaps --help

# Copy necessary files into the container
COPY VolumeSnapshot.yaml /
COPY ManageSnaps.sh /

ENTRYPOINT [ "/ManageSnaps.sh" ]
