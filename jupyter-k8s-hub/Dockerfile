FROM jupyterhub/k8s-hub:0.9.0

USER root
RUN pip3 install --no-cache-dir -U \
    PyJWT

USER ${NB_USER}